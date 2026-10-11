import SwiftUI
import UIKit

// Universal Share Sheet compatible with iOS 15, 16, 17, 18
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct NoteDetailView: View {
    @EnvironmentObject var viewModel: NotesViewModel
    @Environment(\.dismiss) var dismiss

    let noteId: UUID

    @State private var text: String = ""
    @State private var isLoaded: Bool = false
    @State private var showingShareSheet: Bool = false
    @State private var showingDeleteAlert: Bool = false
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
                    guard isLoaded else { return }
                    viewModel.updateNote(id: noteId, text: newValue)
                }

            if let note = currentNote {
                HStack {
                    Text("\(note.wordCount) слов, \(note.characterCount) симв.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Изменено: \(note.formattedDate)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemBackground))
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if currentNote != nil {
                    // Share
                    Button {
                        showingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(.orange)
                    }

                    // Pin toggle
                    Button {
                        viewModel.togglePin(id: noteId)
                    } label: {
                        Image(systemName: (currentNote?.isPinned ?? false) ? "pin.fill" : "pin")
                            .foregroundColor(.orange)
                    }

                    // Delete button with confirmation
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }

                if isFocused {
                    Button("Готово") {
                        isFocused = false
                    }
                    .font(.body.weight(.semibold))
                    .foregroundColor(.orange)
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let note = currentNote {
                ShareSheet(activityItems: [note.text])
            }
        }
        .alert("Удалить заметку?", isPresented: $showingDeleteAlert) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                viewModel.deleteNote(id: noteId)
                dismiss()
            }
        } message: {
            Text("Это действие нельзя будет отменить.")
        }
        .onAppear {
            if let note = currentNote {
                self.text = note.text
            }
            // Delay marking loaded so initial text binding does not trigger false updatedAt update
            DispatchQueue.main.async {
                self.isLoaded = true
            }
            if text.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                }
            }
        }
        .onDisappear {
            viewModel.scheduleSave(immediate: true)
            viewModel.cleanEmptyNotes()
        }
    }
}
