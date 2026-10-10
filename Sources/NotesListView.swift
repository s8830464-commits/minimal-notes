import SwiftUI

struct NotesListView: View {
    @EnvironmentObject var viewModel: NotesViewModel
    @State private var activeNoteId: UUID?
    @State private var showingNewNote = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                if viewModel.filteredNotes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: viewModel.searchText.isEmpty ? "square.and.pencil" : "magnifyingglass")
                            .font(.system(size: 48, weight: .light))
                            .foregroundColor(.secondary)
                        Text(viewModel.searchText.isEmpty ? "Нет заметок" : "Ничего не найдено")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                } else {
                    List {
                        if !viewModel.pinnedNotes.isEmpty {
                            Section(header: Text("Закрепленные").font(.caption).textCase(nil)) {
                                ForEach(viewModel.pinnedNotes) { note in
                                    NavigationLink(value: note.id) {
                                        NoteRowView(note: note)
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            viewModel.togglePin(id: note.id)
                                        } label: {
                                            Label("Открепить", systemImage: "pin.slash.fill")
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
                        }

                        if !viewModel.otherNotes.isEmpty {
                            Section(header: !viewModel.pinnedNotes.isEmpty ? Text("Заметки").font(.caption).textCase(nil) : nil) {
                                ForEach(viewModel.otherNotes) { note in
                                    NavigationLink(value: note.id) {
                                        NoteRowView(note: note)
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            viewModel.togglePin(id: note.id)
                                        } label: {
                                            Label("Закрепить", systemImage: "pin.fill")
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
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Заметки")
            .searchable(text: $viewModel.searchText, prompt: "Поиск")
            .navigationDestination(for: UUID.self) { noteId in
                NoteDetailView(noteId: noteId)
            }
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer()
                    Text("\(viewModel.notes.count) \(notesCountString(viewModel.notes.count))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        let newNote = viewModel.createNote()
                        activeNoteId = newNote.id
                        showingNewNote = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.title3)
                            .foregroundColor(.orange)
                    }
                }
            }
            .navigationDestination(isPresented: $showingNewNote) {
                if let id = activeNoteId {
                    NoteDetailView(noteId: id)
                }
            }
            .onAppear {
                viewModel.cleanEmptyNotes()
            }
        }
    }

    private func notesCountString(_ count: Int) -> String {
        let remainder10 = count % 10
        let remainder100 = count % 100
        if remainder100 >= 11 && remainder100 <= 19 {
            return "заметок"
        }
        switch remainder10 {
        case 1:
            return "заметка"
        case 2, 3, 4:
            return "заметки"
        default:
            return "заметок"
        }
    }
}

struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                Text(note.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text(note.formattedDate)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(note.previewBody)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
