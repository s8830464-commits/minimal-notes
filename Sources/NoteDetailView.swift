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

    @StateObject private var speechService = SpeechService()

    @State private var didRequestFocus = false
    @State private var showingShareSheet = false
    @State private var showingSettingsSheet = false
    @State private var showingDeleteAlert = false
    @State private var showingAIErrorAlert = false
    @State private var aiErrorMessage = ""
    @State private var isProcessingAI = false
    @FocusState private var isFocused: Bool

    // Расширенные настройки (сохраняются автоматически)
    @AppStorage("note_font_size") private var fontSize: Double = 17
    @AppStorage("note_font_design") private var fontDesign: String = "default"
    @AppStorage("openrouter_api_key") private var openRouterApiKey: String = ""
    @AppStorage("openrouter_model") private var selectedModel: String = AIService.defaultModel
    @AppStorage("ai_processing_mode") private var processingModeRaw: String = AIProcessingMode.fixErrors.rawValue
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
                            .foregroundColor(Color(red: 0.23, green: 0.23, blue: 0.24))
                    } else {
                        Text("\(note.wordCount) слов, \(note.characterCount) симв.")
                    }
                    Spacer()
                    Text(speechService.isRecording
                         ? "Идет запись голоса… Говорите"
                         : (isProcessingAI
                            ? "Обработка нейросетью…"
                            : (viewModel.hasUnsavedChanges
                               ? "Сохранение…"
                               : "Изменено: \(note.formattedDate)")))
                }
                .font(.caption2)
                .foregroundColor(speechService.isRecording ? .red : .primary)
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
                    // Кнопка голосовой диктовки с ИИ-обработкой
                    Button {
                        toggleVoiceDictation()
                    } label: {
                        if speechService.isRecording {
                            Image(systemName: "mic.fill")
                                .foregroundColor(.red)
                        } else {
                            Image(systemName: "mic")
                        }
                    }
                    .buttonStyle(AppleSpringButtonStyle())
                    .accessibilityLabel("Диктовать заметку голосом")
                    .disabled(isProcessingAI || isReadOnly)

                    // Кнопка нейросети в 1 нажатие (Sparkles)
                    Button {
                        runDirectAIAction()
                    } label: {
                        if isProcessingAI {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Image(systemName: "sparkles")
                        }
                    }
                    .buttonStyle(AppleSpringButtonStyle())
                    .accessibilityLabel("Обработать нейросетью")
                    .disabled(isProcessingAI || isReadOnly || note.text.isEmpty)

                    Button {
                        viewModel.flush()
                        showingSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(AppleSpringButtonStyle())
                    .accessibilityLabel("Параметры заметки")

                    Button {
                        viewModel.flush()
                        showingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(AppleSpringButtonStyle())
                    .accessibilityLabel("Поделиться заметкой")
                    .disabled(note.text.isEmpty)

                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Image(systemName: "trash").foregroundColor(.red)
                    }
                    .buttonStyle(AppleSpringButtonStyle())
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
        .tint(Color(red: 0.23, green: 0.23, blue: 0.24))
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
                onApplyCorrection: { correctedText in
                    if let note = currentNote {
                        viewModel.updateNote(id: note.id, text: correctedText)
                        viewModel.flush()
                    }
                },
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
        .alert("Ошибка ИИ", isPresented: $showingAIErrorAlert) {
            Button("ОК", role: .cancel) {}
        } message: {
            Text(aiErrorMessage)
        }
        .alert("Ошибка микрофона", isPresented: Binding(
            get: { speechService.errorMessage != nil },
            set: { if !$0 { speechService.errorMessage = nil } }
        )) {
            Button("ОК", role: .cancel) {
                speechService.errorMessage = nil
            }
        } message: {
            if let errorMsg = speechService.errorMessage {
                Text(errorMsg)
            }
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
            if speechService.isRecording {
                speechService.stopRecording { _ in }
            }
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

    private func toggleVoiceDictation() {
        if speechService.isRecording {
            speechService.stopRecording { spokenText in
                guard !spokenText.isEmpty else { return }
                isProcessingAI = true
                let key = openRouterApiKey.isEmpty ? AIService.embeddedAPIKey : openRouterApiKey
                let model = selectedModel

                Task {
                    do {
                        let cleanedNote = try await AIService.shared.process(
                            text: spokenText,
                            mode: .voiceToNote,
                            apiKey: key,
                            model: model
                        )
                        await MainActor.run {
                            if let note = currentNote {
                                let newText: String
                                if note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    newText = cleanedNote
                                } else {
                                    newText = note.text + "\n\n" + cleanedNote
                                }
                                viewModel.updateNote(id: note.id, text: newText)
                                viewModel.flush()
                            }
                            isProcessingAI = false
                        }
                    } catch {
                        await MainActor.run {
                            isProcessingAI = false
                            if let note = currentNote {
                                let newText: String
                                if note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    newText = spokenText
                                } else {
                                    newText = note.text + "\n\n" + spokenText
                                }
                                viewModel.updateNote(id: note.id, text: newText)
                                viewModel.flush()
                            }
                            aiErrorMessage = "Речь записана, но произошла ошибка обработки ИИ: \(error.localizedDescription). Исходный текст сохранён."
                            showingAIErrorAlert = true
                        }
                    }
                }
            }
        } else {
            speechService.startRecording()
        }
    }

    private func runDirectAIAction() {
        guard let note = currentNote, !note.text.isEmpty, !isProcessingAI else { return }
        isProcessingAI = true
        let mode = AIProcessingMode(rawValue: processingModeRaw) ?? .fixErrors
        let key = openRouterApiKey.isEmpty ? AIService.embeddedAPIKey : openRouterApiKey
        let model = selectedModel

        Task {
            do {
                let result = try await AIService.shared.process(
                    text: note.text,
                    mode: mode,
                    apiKey: key,
                    model: model
                )
                await MainActor.run {
                    viewModel.updateNote(id: note.id, text: result)
                    viewModel.flush()
                    isProcessingAI = false
                }
            } catch {
                await MainActor.run {
                    isProcessingAI = false
                    aiErrorMessage = error.localizedDescription
                    showingAIErrorAlert = true
                }
            }
        }
    }
}
