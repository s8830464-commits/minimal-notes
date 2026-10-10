import SwiftUI

struct NoteDetailView: View {
    @EnvironmentObject var viewModel: NotesViewModel
    @Environment(\.dismiss) var dismiss

    let noteId: UUID

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    private var currentNote: Note? {
        viewModel.notes.first(where: { $0.id == noteId })
    }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text)
                .focused($isFocused)
                .font(.body)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .onChange(of: text) { newValue in
                    viewModel.updateNote(id: noteId, text: newValue)
                }

            // Minimal footer with count & timestamp
            if let note = currentNote {
                HStack {
                    Text("\(note.wordCount) слов, \(note.characterCount) симв.")
                        .font(.caption2)
                        .foregroundColor(.tertiaryLabel)
                    Spacer()
                    Text("Изменено: \(note.formattedDate)")
                        .font(.caption2)
                        .foregroundColor(.tertiaryLabel)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .background(Color(uiColor: .systemBackground))
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if let note = currentNote {
                    // Share Note
                    ShareLink(item: note.text) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.orange)
                    }

                    // Pin toggle
                    Button {
                        viewModel.togglePin(id: noteId)
                    } label: {
                        Image(systemName: note.isPinned ? "pin.fill" : "pin")
                            .foregroundColor(.orange)
                    }

                    // Delete
                    Button(role: .destructive) {
                        viewModel.deleteNote(id: noteId)
                        dismiss()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }

                if isFocused {
                    Button("Готово") {
                        isFocused = false
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
                }
            }
        }
        .onAppear {
            if let note = currentNote {
                self.text = note.text
            }
            if text.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                }
            }
        }
    }
}

// Extension for tertiaryLabel compatibility across iOS versions
extension Color {
    static var tertiaryLabel: Color {
        Color(uiColor: .tertiaryLabel)
    }
}
