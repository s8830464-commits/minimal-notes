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
    @State private var showingSettingsSheet = false
    @State private var showingDeleteAlert = false
    @FocusState private var isFocused: Bool

    // Расширенные настройки (сохраняются автоматически)
    @AppStorage("note_font_size") private var fontSize: Double = 17
    @AppStorage("note_font_design") private var fontDesign: String = "default"
    @State private var isReadOnly = false

    private var currentNote: Note? { viewModel.note(id: noteId) }

    // Вычисляемый динамический шрифт
    private var editorFont: Font {
        let design: Font.Design = {
            switch fontDesign {
            case "serif": return .serif
            case "monospaced": return .monospaced
            default: return .default
            }
        }()
        return .system(size: CGFloat(fontSize), design: design)
    }

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
                .font(editorFont)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .disabled(currentNote == nil || !viewModel.canEdit || isReadOnly)
                .accessibilityLabel("Текст заметки")

            if let note = currentNote {
                HStack {
                    if isReadOnly {
                        Label("Только чтение", systemImage: "lock.fill")
                            .foregroundColor(.orange)
                    } else {
                        Text("\(note.wordCount) слов, \(note.characterCount) симв.")
                    }
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
                    // Кнопка расширенных настроек (по умолчанию всё скрыто в ней)
                    Button {
                        viewModel.flush()
                        showingSettingsSheet = true
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Параметры заметки")

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
        .sheet(isPresented: $showingSettingsSheet) {
            NoteSettingsView(
                fontSize: $fontSize,
                fontDesign: $fontDesign,
                isReadOnly: $isReadOnly,
                note: currentNote,
                onFormatText: formatText,
                onCopyAll: copyAllText
            )
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
            if showingShareSheet || showingSettingsSheet {
                viewModel.flush()
            } else {
                viewModel.finishEditing(id: noteId)
            }
        }
    }

    private func copyAllText() {
        if let note = currentNote {
            UIPasteboard.general.string = note.text
        }
    }

    private func formatText() {
        guard let note = currentNote else { return }
        let lines = note.text.components(separatedBy: .newlines)
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.updateNote(id: noteId, text: cleaned)
    }
}
