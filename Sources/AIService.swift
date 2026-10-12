import Foundation

public enum AIProcessingMode: String, CaseIterable, Identifiable {
    case fixErrors = "fix_errors"
    case formatAndBeautify = "format_beautify"
    case summary = "summary"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fixErrors: return "Исправить ошибки"
        case .formatAndBeautify: return "Оформить и структурировать"
        case .summary: return "Краткая выжимка (тезисы)"
        }
    }

    public var systemPrompt: String {
        switch self {
        case .fixErrors:
            return """
Ты профессиональный редактор русского языка.
Твоя единственная задача: исправить все орфографические, пунктуационные и грамматические ошибки в тексте.
Строгие правила:
1. Сохраняй исходную структуру текста, разделение на абзацы и переносы строк.
2. Сохраняй авторский стиль, интонацию и эмоциональную окраску. Не подвергай текст цензуре (не удаляй и не заменяй нецензурную лексику, разговорный сленг или резкие слова).
3. Не меняй смысл и не перефразируй предложения без необходимости.
4. Верни ТОЛЬКО исправленный текст. Никаких вступительных фраз ("Вот исправленный текст:"), пояснений, списков ошибок и кавычек.
"""
        case .formatAndBeautify:
            return """
Ты мастер верстки и типографики заметок на русском языке.
Твоя задача: сделать текст аккуратным, опрятным и удобным для чтения.
Правила:
1. Исправь все орфографические и пунктуационные ошибки.
2. Разбей сплошной текст на логичные абзацы.
3. Если есть перечисления или списки дел — аккуратно оформи их списками через тире.
4. Сохраняй оригинальный смысл, слова и тон автора без цензуры.
5. Верни ТОЛЬКО готовый текст заметки без пояснений и вступительных фраз.
"""
        case .summary:
            return """
Ты аналитический редактор. Твоя задача: составить краткую и емкую выжимку из текста заметки на русском языке.
Правила:
1. Выдели главные мысли, решения или важные тезисы.
2. Изложи тезисно и понятно.
3. Верни ТОЛЬКО текст выжимки без предисловий.
"""
        }
    }
}

public enum AIError: LocalizedError {
    case missingAPIKey
    case emptyText
    case invalidResponse
    case serverError(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Не указан API-ключ OpenRouter."
        case .emptyText:
            return "Заметка пустая. Напишите текст для обработки."
        case .invalidResponse:
            return "Не удалось прочитать ответ нейросети."
        case .serverError(let message):
            return "Ошибка OpenRouter: \(message)"
        case .networkError(let message):
            return "Сетевая ошибка: \(message)"
        }
    }
}

public struct AIService {
    public static let shared = AIService()

    /// Встроенный ключ OpenRouter по умолчанию
    public static var embeddedAPIKey: String {
        let payload = "c2stb3ItdjEtYjc1OWZjZTVhY2I5MDIyY2YyN2NkMmIxYWVhZWM0MjEwM2M0MTZmNThiMTBjZjhhNTNmMWZmMzhhODllZDc5YQ=="
        guard let data = Data(base64Encoded: payload),
              let string = String(data: data, encoding: .utf8) else {
            return ""
        }
        return string
    }

    /// Модель по умолчанию (Nemotron 120B — проверенная мощная модель без цензуры)
    public static let defaultModel = "nvidia/nemotron-3-super-120b-a12b:free"
    public static let fallbackModel = "nvidia/nemotron-3.5-lightning:free"

    public static let availableModels: [(id: String, name: String)] = [
        ("nvidia/nemotron-3-super-120b-a12b:free", "Nemotron 120B (Бесплатно, лучшее качество)"),
        ("nvidia/nemotron-3.5-lightning:free", "Nemotron Lightning (Бесплатно, быстрый)"),
        ("openrouter/free", "OpenRouter Auto (Бесплатно)"),
        ("google/gemma-4-31b-it:free", "Gemma 4 31B (Бесплатно)")
    ]

    private struct ChatRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let temperature: Double
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let role: String?
                let content: String?
            }
            let message: Message?
        }
        struct ErrorDetail: Decodable {
            let message: String?
            let code: Int?
        }

        let choices: [Choice]?
        let error: ErrorDetail?
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Обработка текста заметки (исправление ошибок, форматирование или саммари)
    public func process(
        text: String,
        mode: AIProcessingMode = .fixErrors,
        apiKey: String? = nil,
        model: String = defaultModel
    ) async throws -> String {
        let key = (apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? Self.embeddedAPIKey
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw AIError.emptyText
        }

        do {
            return try await executeRequest(text: text, prompt: mode.systemPrompt, key: key, model: model)
        } catch {
            // Если выбранная модель временно перегружена (429/503), пробуем резервную
            if model != Self.fallbackModel {
                return try await executeRequest(text: text, prompt: mode.systemPrompt, key: key, model: Self.fallbackModel)
            }
            throw error
        }
    }

    /// Упрощенный вызов для исправления ошибок
    public func fixErrors(in text: String, apiKey: String? = nil, model: String = defaultModel) async throws -> String {
        try await process(text: text, mode: .fixErrors, apiKey: apiKey, model: model)
    }

    private func executeRequest(text: String, prompt: String, key: String, model: String) async throws -> String {
        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("https://github.com/s8830464-commits/minimal-notes", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Minimal Notes", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 40.0

        let chatRequest = ChatRequest(
            model: model.isEmpty ? Self.defaultModel : model,
            messages: [
                .init(role: "system", content: prompt),
                .init(role: "user", content: text)
            ],
            temperature: 0.1
        )

        do {
            request.httpBody = try JSONEncoder().encode(chatRequest)
        } catch {
            throw AIError.invalidResponse
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIError.networkError(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
               let serverMessage = decoded.error?.message {
                throw AIError.serverError(serverMessage)
            }
            throw AIError.serverError("Код ответа: \(httpResponse.statusCode)")
        }

        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw AIError.invalidResponse
        }

        if let serverError = decoded.error?.message {
            throw AIError.serverError(serverError)
        }

        guard let content = decoded.choices?.first?.message?.content else {
            throw AIError.invalidResponse
        }

        var cleanResult = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanResult.hasPrefix("```") && cleanResult.hasSuffix("```") {
            let lines = cleanResult.components(separatedBy: .newlines)
            if lines.count >= 2 {
                cleanResult = lines.dropFirst().dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return cleanResult
    }
}
