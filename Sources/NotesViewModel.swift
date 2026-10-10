import Foundation
import Combine

class NotesViewModel: ObservableObject {
    @Published var notes: [Note] = []
    @Published var searchText: String = ""

    private let saveKey = "minimal_notes.json"

    init() {
        loadNotes()
        if notes.isEmpty {
            createSampleNotes()
        }
    }

    // Filtered list
    var filteredNotes: [Note] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return notes
        } else {
            let query = searchText.lowercased()
            return notes.filter {
                $0.text.lowercased().contains(query)
            }
        }
    }

    var pinnedNotes: [Note] {
        filteredNotes.filter { $0.isPinned }
    }

    var otherNotes: [Note] {
        filteredNotes.filter { !$0.isPinned }
    }

    // Actions
    func createNote() -> Note {
        let newNote = Note(
            text: "",
            isPinned: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        notes.insert(newNote, at: 0)
        saveNotes()
        return newNote
    }

    func updateNote(id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        // Clean up: if note text changed
        if notes[index].text != text {
            notes[index].text = text
            notes[index].updatedAt = Date()
            
            // Re-order: keep pinned or non-pinned on top of their section
            let updated = notes.remove(at: index)
            notes.insert(updated, at: 0)
            
            saveNotes()
        }
    }

    func togglePin(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isPinned.toggle()
        saveNotes()
    }

    func deleteNote(id: UUID) {
        notes.removeAll { $0.id == id }
        saveNotes()
    }

    func cleanEmptyNotes() {
        notes.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        saveNotes()
    }

    // MARK: - Persistence
    private var fileURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(saveKey)
    }

    private func saveNotes() {
        do {
            let data = try JSONEncoder().encode(notes)
            try data.write(to: fileURL, options: [.atomicWrite, .completeFileProtection])
        } catch {
            print("Failed to save notes: \(error)")
        }
    }

    private func loadNotes() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            self.notes = try JSONDecoder().decode([Note].self, from: data)
        } catch {
            print("Failed to load notes: \(error)")
        }
    }

    private func createSampleNotes() {
        let sample = Note(
            text: "Добро пожаловать в Заметки ✨\n\nЭто минималистичное и быстрое приложение без лишних элементов:\n\n• Первая строка автоматически становится заголовком.\n• Свайп вправо закрепляет заметку.\n• Свайп влево удаляет заметку.\n• Все данные хранятся локально на вашем iPhone.",
            isPinned: true,
            createdAt: Date(),
            updatedAt: Date()
        )
        self.notes = [sample]
        saveNotes()
    }
}
