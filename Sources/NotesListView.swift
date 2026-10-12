import SwiftUI

struct NotesListView: View {
    @EnvironmentObject private var viewModel: NotesViewModel
    @State private var path: [UUID] = []
    @State private var activeNoteId: UUID?
    @State private var navigateToDetail = false

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack(path: $path) {
                content
                    .navigationDestination(for: UUID.self) { id in
                        NoteDetailView(noteId: id)
                    }
            }
        } else {
            NavigationView {
                content
                    .background(
                        NavigationLink(isActive: $navigateToDetail) {
                            if let id = activeNoteId {
                                NoteDetailView(noteId: id).id(id)
                            }
                        } label: {
                            EmptyView()
                        }
                        .hidden()
                    )
            }
            .navigationViewStyle(.stack)
        }
    }

    private var content: some View {
        let filtered = viewModel.filteredNotes
        let pinned = filtered.filter(\.isPinned)
        let other = filtered.filter { !$0.isPinned }
        let searching = !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            if !viewModel.canEdit {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text("Не удалось прочитать заметки").font(.headline)
                    Text("Файл сохранён без изменений.").foregroundColor(.secondary)
                    Button("Повторить чтение") { viewModel.retryStorage() }
                }
                .padding()
            } else if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: searching ? "magnifyingglass" : "square.and.pencil")
                        .font(.system(size: 48, weight: .light))
                    Text(searching ? "Ничего не найдено" : "Нет заметок").font(.headline)
                }
                .foregroundColor(.secondary)
                .padding()
            } else {
                List {
                    if !pinned.isEmpty {
                        Section(header: Text("Закреплённые").font(.caption).textCase(nil)) {
                            rows(pinned)
                        }
                    }
                    if !other.isEmpty {
                        Section(header: !pinned.isEmpty ? Text("Заметки").font(.caption).textCase(nil) : nil) {
                            rows(other)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Заметки")
        .searchable(text: $viewModel.searchText, prompt: "Поиск")
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                Button {
                    guard let note = viewModel.createNote() else { return }
                    if #available(iOS 16.0, *) {
                        path.append(note.id)
                    } else {
                        activeNoteId = note.id
                        navigateToDetail = true
                    }
                } label: {
                    Image(systemName: "square.and.pencil").font(.title3)
                }
                .disabled(!viewModel.canEdit)
                .accessibilityLabel("Создать заметку")
            }
        }
        .tint(.orange)
    }

    private func rows(_ notes: [Note]) -> some View {
        ForEach(notes) { note in
            noteLink(note)
                .swipeActions(edge: .leading) {
                    Button {
                        viewModel.togglePin(id: note.id)
                    } label: {
                        Label(note.isPinned ? "Открепить" : "Закрепить",
                              systemImage: note.isPinned ? "pin.slash.fill" : "pin.fill")
                    }
                    .tint(.orange)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        viewModel.deleteNote(id: note.id)
                    } label: {
                        Label("Удалить", systemImage: "trash.fill")
                    }
                }
        }
    }

    @ViewBuilder
    private func noteLink(_ note: Note) -> some View {
        if #available(iOS 16.0, *) {
            NavigationLink(value: note.id) { NoteRowView(note: note) }
        } else {
            NavigationLink {
                NoteDetailView(noteId: note.id).id(note.id)
            } label: {
                NoteRowView(note: note)
            }
        }
    }
}

struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if note.isPinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundColor(.orange)
                }
                Text(note.title).font(.body.weight(.semibold)).lineLimit(1)
            }
            HStack(spacing: 8) {
                Text(note.formattedDate).font(.subheadline).foregroundColor(.secondary)
                Text(note.previewBody).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
