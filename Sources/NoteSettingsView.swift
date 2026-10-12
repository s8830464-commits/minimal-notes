import SwiftUI
import UIKit

struct NoteSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var fontSize: Double
    @Binding var fontDesign: String
    @Binding var isReadOnly: Bool

    let note: Note?
    let onApplyCorrection: (String) -> Void
    let onCopyAll: () -> Void

    @AppStorage("openrouter_api_key") private var openRouterApiKey: String = ""
    @AppStorage("openrouter_model") private var selectedModel: String = AIService.defaultModel

    @State private var showCopiedNotice = false
    @State private var isProcessingAI = false
    @State private var correctionSuccessNotice = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var isKeyVisible = false

    var body: some View {
        NavigationView {
            Form {
                // Раздел: Оформление текста
                Section(header: Text("Оформление текста")) {
                    Picker("Стиль шрифта", selection: $fontDesign) {
                        Text("Стандартный").tag("default")
                        Text("С засечками").tag("serif")
                        Text("Моноширинный (код)").tag("monospaced")
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Размер шрифта")
                            Spacer()
                            Text("\(Int(fontSize)) пт")
                                .foregroundColor(.primary)
                        }
                        Slider(value: $fontSize, in: 14...28, step: 1)
                            .tint(Color(red: 0.23, green: 0.23, blue: 0.24))
                    }

                    Toggle(isOn: $isReadOnly) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Режим чтения")
                            Text("Защита от случайных правок")
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }
                    .tint(Color(red: 0.23, green: 0.23, blue: 0.24))
                }

                // Раздел: Искусственный интеллект (OpenRouter)
                Section(
                    header: Text("Нейросеть (OpenRouter)"),
                    footer: Text("Используется открытая модель Qwen 2.5 (72 млрд параметров). Ключ хранится локально на вашем устройстве.")
                        .font(.caption2)
                        .foregroundColor(.primary)
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API-ключ OpenRouter")
                            .font(.caption)
                            .foregroundColor(.primary)

                        HStack {
                            if isKeyVisible {
                                TextField("sk-or-v1-...", text: $openRouterApiKey)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .font(.system(.subheadline, design: .monospaced))
                            } else {
                                SecureField("sk-or-v1-...", text: $openRouterApiKey)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .font(.system(.subheadline, design: .monospaced))
                            }

                            Button {
                                isKeyVisible.toggle()
                            } label: {
                                Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                                    .foregroundColor(Color(red: 0.23, green: 0.23, blue: 0.24))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)

                    Picker("Модель", selection: $selectedModel) {
                        ForEach(AIService.availableModels, id: \.id) { item in
                            Text(item.name).tag(item.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Раздел: Быстрые действия
                Section(header: Text("Действия")) {
                    Button {
                        runGrammarCorrection()
                    } label: {
                        HStack {
                            Label("Исправить ошибки в тексте", systemImage: "sparkles")
                            Spacer()
                            if isProcessingAI {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else if correctionSuccessNotice {
                                Text("Исправлено")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .disabled(isProcessingAI || isReadOnly || (note?.text.isEmpty ?? true))

                    Button {
                        onCopyAll()
                        showCopiedNotice = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopiedNotice = false
                        }
                    } label: {
                        HStack {
                            Label("Скопировать весь текст", systemImage: "doc.on.doc")
                            Spacer()
                            if showCopiedNotice {
                                Text("Скопировано")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }

                // Раздел: Информация о заметке
                if let note = note {
                    Section(header: Text("Информация")) {
                        HStack {
                            Text("Символов")
                            Spacer()
                            Text("\(note.characterCount)").foregroundColor(.primary)
                        }
                        HStack {
                            Text("Слов")
                            Spacer()
                            Text("\(note.wordCount)").foregroundColor(.primary)
                        }
                        HStack {
                            Text("Примерное время чтения")
                            Spacer()
                            Text("~\(max(1, note.wordCount / 180)) мин").foregroundColor(.primary)
                        }
                        HStack {
                            Text("Последнее изменение")
                            Spacer()
                            Text(note.formattedDate).foregroundColor(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Параметры заметки")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Ошибка ИИ", isPresented: $showErrorAlert) {
                Button("ОК", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Произошла непредвиденная ошибка.")
            }
        }
        .navigationViewStyle(.stack)
    }

    private func runGrammarCorrection() {
        guard let note = note, !note.text.isEmpty else {
            errorMessage = "Заметка пустая. Добавьте текст для проверки."
            showErrorAlert = true
            return
        }

        let key = openRouterApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorMessage = "Введите ваш API-ключ OpenRouter в поле выше, чтобы исправить текст."
            showErrorAlert = true
            return
        }

        isProcessingAI = true
        correctionSuccessNotice = false

        Task {
            do {
                let corrected = try await AIService.shared.fixErrors(
                    in: note.text,
                    apiKey: key,
                    model: selectedModel
                )

                await MainActor.run {
                    onApplyCorrection(corrected)
                    isProcessingAI = false
                    correctionSuccessNotice = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        correctionSuccessNotice = false
                    }
                }
            } catch {
                await MainActor.run {
                    isProcessingAI = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
}
