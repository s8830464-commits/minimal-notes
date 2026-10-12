import SwiftUI
import UIKit

struct NoteSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var fontSize: Double
    @Binding var fontDesign: String
    @Binding var isReadOnly: Bool

    let note: Note?
    let onFixErrors: () -> Void
    let onCopyAll: () -> Void

    @State private var showCopiedNotice = false

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
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $fontSize, in: 14...28, step: 1)
                            .tint(.orange)
                    }

                    Toggle(isOn: $isReadOnly) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Режим чтения")
                            Text("Защита от случайных правок")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(.orange)
                }

                // Раздел: Быстрые действия
                Section(header: Text("Действия")) {
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

                    Button {
                        onFixErrors()
                    } label: {
                        Label("Исправить ошибки в тексте", systemImage: "text.badge.checkmark")
                    }
                }

                // Раздел: Информация о заметке
                if let note = note {
                    Section(header: Text("Информация")) {
                        HStack {
                            Text("Символов")
                            Spacer()
                            Text("\(note.characterCount)").foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Слов")
                            Spacer()
                            Text("\(note.wordCount)").foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Примерное время чтения")
                            Spacer()
                            Text("~\(max(1, note.wordCount / 180)) мин").foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Последнее изменение")
                            Spacer()
                            Text(note.formattedDate).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Параметры заметки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                    .font(.body.weight(.semibold))
                    .foregroundColor(.orange)
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
