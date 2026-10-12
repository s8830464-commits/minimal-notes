import Foundation
import Combine

@MainActor
final class NotesViewModel: ObservableObject {
    struct StorageAlert: Identifiable {
        enum Operation { case load, save }
        let id = UUID()
        let operation: Operation
        let message: String
    }

    @Published private(set) var notes: [Note] = []
    @Published var searchText = ""
    @Published private(set) var canEdit = false
    @Published private(set) var hasUnsavedChanges = false
    @Published var storageAlert: StorageAlert?

    private let store: NotesFileStore
    private let saveQueue = DispatchQueue(label: "com.ivan.minimalnotes.storage", qos: .utility)
    private let saveDelay: TimeInterval
    private var pendingSave: Task<Void, Never>?
    private var revision: UInt64 = 0
    private var savedRevision: UInt64 = 0
    private var nextSaveAttempt: UInt64 = 0
    private var handledSaveAttempt: UInt64 = 0

    init(fileURL: URL = NotesFileStore.defaultURL, saveDelay: TimeInterval = 0.5) {
        self.store = NotesFileStore(fileURL: fileURL)
        self.saveDelay = saveDelay
        loadNotes()
    }

    var filteredNotes: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notes }
        return notes.filter { $0.text.localizedStandardContains(query) }
    }

    func note(id: UUID) -> Note? {
        notes.first { $0.id == id }
    }

    @discardableResult
    func createNote() -> Note? {
        guard canEdit else { return nil }
        let note = Note(text: "")
        notes.insert(note, at: 0)
        changed(immediate: true)
        return note
    }

    func updateNote(id: UUID, text: String) {
        guard canEdit, let index = notes.firstIndex(where: { $0.id == id }),
              notes[index].text != text else { return }
        var updatedNotes = notes
        var note = updatedNotes.remove(at: index)
        note.text = text
        note.updatedAt = Date()
        updatedNotes.insert(note, at: 0)
        notes = updatedNotes
        changed(immediate: false)
    }

    func togglePin(id: UUID) {
        guard canEdit, let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isPinned.toggle()
        changed(immediate: true)
    }

    func deleteNote(id: UUID) {
        guard canEdit, notes.contains(where: { $0.id == id }) else { return }
        notes.removeAll { $0.id == id }
        changed(immediate: true)
    }

    func finishEditing(id: UUID) {
        guard canEdit else { return }
        if let note = note(id: id),
           note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes.removeAll { $0.id == id }
            revision += 1
            hasUnsavedChanges = true
        }
        flush()
    }

    /// Drain preceding writes and persist the latest snapshot before suspension.
    /// Encoding and file access still execute on the serial I/O queue.
    func flush() {
        persist(wait: true)
    }

    func retryStorage() {
        storageAlert = nil
        if canEdit {
            persist(wait: false)
        } else {
            loadNotes()
        }
    }

    private func changed(immediate: Bool) {
        revision += 1
        hasUnsavedChanges = true
        pendingSave?.cancel()
        if immediate {
            persist(wait: false)
        } else {
            let delay = UInt64(max(0, saveDelay) * 1_000_000_000)
            pendingSave = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: delay)
                    guard !Task.isCancelled else { return }
                    self?.persist(wait: false)
                } catch {
                    // A newer edit or lifecycle flush cancels this debounce.
                }
            }
        }
    }

    private func persist(wait: Bool) {
        pendingSave?.cancel()
        pendingSave = nil
        guard canEdit, hasUnsavedChanges else { return }
        let snapshot = notes
        let snapshotRevision = revision
        nextSaveAttempt += 1
        let attempt = nextSaveAttempt
        let store = self.store
        if wait {
            let result: Result<Void, Error> = saveQueue.sync {
                Result { try store.save(snapshot) }
            }
            didSave(result, revision: snapshotRevision, attempt: attempt)
        } else {
            saveQueue.async { [weak self] in
                let result: Result<Void, Error> = Result { try store.save(snapshot) }
                DispatchQueue.main.async {
                    self?.didSave(result, revision: snapshotRevision, attempt: attempt)
                }
            }
        }
    }

    private func didSave(_ result: Result<Void, Error>, revision snapshotRevision: UInt64, attempt: UInt64) {
        // An older completion must not clear a newer failure or mark new text saved.
        guard attempt > handledSaveAttempt, snapshotRevision >= savedRevision else { return }
        handledSaveAttempt = attempt
        switch result {
        case .success:
            savedRevision = snapshotRevision
            if snapshotRevision == revision {
                hasUnsavedChanges = false
                if storageAlert?.operation == .save { storageAlert = nil }
            }
        case .failure(let error):
            guard snapshotRevision == revision, hasUnsavedChanges else { return }
            storageAlert = StorageAlert(
                operation: .save,
                message: "Последние изменения пока только в памяти. Не закрывайте приложение. Освободите место, если оно закончилось, и повторите сохранение.\n\n\(error.localizedDescription)"
            )
        }
    }

    private func loadNotes() {
        do {
            if let stored = try store.load() {
                notes = stored
                canEdit = true
            } else {
                canEdit = true
                notes = [Note(
                    text: "Добро пожаловать в Заметки\n\nПервая строка становится заголовком.\nСвайп вправо закрепляет заметку, влево — удаляет.\nВсе заметки хранятся локально на вашем устройстве.",
                    isPinned: true
                )]
                changed(immediate: true)
            }
        } catch {
            // Never seed or overwrite an unreadable existing file.
            canEdit = false
            storageAlert = StorageAlert(
                operation: .load,
                message: "Файл заметок не удалось прочитать. Он оставлен без изменений. Повторите чтение; не удаляйте приложение, если в нём есть важные записи.\n\n\(error.localizedDescription)"
            )
        }
    }
}
