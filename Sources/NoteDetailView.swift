import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct NoteDetailView: View {
    @EnvironmentObject private var viewModel: NotesViewModel
    @Environment(\.dismiss) private var dismiss
    let noteId: UUID

    @State private var didRequestFocus = false
    @State private var showingShareSheet = false
    @State private var showingDeleteAlert = false
    @FocusState private var isFocused: Bool

    private var currentNote: Note? { viewModel.note(id: noteId) }

    // One source of truth: presenting a sheet cannot reload a stale local draft.
    private var text: Binding<String> {
        Binding(
            get: { currentNote?.text ?? "" },
            set: { viewModel.updateNote(id: noteId, text: $0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: text)
                .focused($isFocused)
                .font(.body)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .disabled(currentNote == nil || !viewModel.canEdit)
                .accessibilityLabel("Текст заметки")

            if let note = currentNote {
                HStack {
                    Text("\(note.wordCount) слов, \(note.characterCount) симв.")
                    Spacer()
                    Text(viewModel.hasUnsavedChanges
                         ? "Сохранение…"
                         : "Изменено: \(note.formattedDate)")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Color(uiColor: .secondarySystemBackground))
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if let note = currentNote {
                    Button {
                        viewModel.flush()
                        showingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Поделиться заметкой")
                    .disabled(note.text.isEmpty)

                    Button {
                        viewModel.togglePin(id: noteId)
                    } label: {
                        Image(systemName: note.isPinned ? "pin.fill" : "pin")
                    }
                    .accessibilityLabel(note.isPinned ? "Открепить заметку" : "Закрепить заметку")

                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Image(systemName: "trash").foregroundColor(.red)
                    }
                    .accessibilityLabel("Удалить заметку")
                }
                if isFocused {
                    Button("Готово") {
                        isFocused = false
                        viewModel.flush()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
        .tint(.orange)
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
        .task {
            guard !didRequestFocus else { return }
            didRequestFocus = true
            guard currentNote?.text.isEmpty == true else { return }
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled else { return }
                isFocused = true
            } catch {
                // Navigation away cancels the pending keyboard request.
            }
        }
        .onDisappear {
            if showingShareSheet {
                viewModel.flush()
            } else {
                viewModel.finishEditing(id: noteId)
            }
        }
    }
}
