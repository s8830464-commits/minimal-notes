import Foundation

enum AIError: LocalizedError {
    case missingAPIKey
    case emptyText
    case invalidResponse
    case serverError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Укажите API-ключ OpenRouter в параметрах заметки."
        case .emptyText:
            return "Заметка пустая. Напишите текст для проверки."
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

    public static let defaultModel = "qwen/qwen-2.5-72b-instruct:free"

    public static let availableModels: [(id: String, name: String)] = [
        ("qwen/qwen-2.5-72b-instruct:free", "Qwen 2.5 72B (Бесплатно)"),
        ("meta-llama/llama-3.3-70b-instruct:free", "Llama 3.3 70B (Бесплатно)"),
        ("google/gemini-2.0-flash-exp:free", "Gemini 2.0 Flash (Бесплатно)")
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

    /// Отправляет текст заметки в OpenRouter и возвращает исправленный вариант
    public func fixErrors(in text: String, apiKey: String, model: String = defaultModel) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw AIError.missingAPIKey
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw AIError.emptyText
        }

        guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw AIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("https://github.com/s8830464-commits/minimal-notes", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Minimal Notes", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 45.0

        let systemPrompt = """
Ты профессиональный корректор русского языка.
Твоя единственная задача: исправить все орфографические, пунктуационные и грамматические ошибки в тексте.
Строгие правила:
1. Сохраняй исходную структуру, разделение на абзацы и переносы строк.
2. Сохраняй авторский стиль, интонацию и эмоциональную окраску. Не подвергай текст цензуре (не удаляй и не заменяй нецензурную лексику, разговорный сленг или резкие слова).
3. Не меняй смысл и не перефразируй предложения без необходимости.
4. Верни ТОЛЬКО исправленный текст. Никаких вступительных фраз ("Вот исправленный текст:"), пояснений, списков ошибок и кавычек.
"""

        let chatRequest = ChatRequest(
            model: model.isEmpty ? Self.defaultModel : model,
            messages: [
                .init(role: "system", content: systemPrompt),
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
            throw AIError.serverError("Код ответа сервера: \(httpResponse.statusCode)")
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

        // Удаляем возможное случайное обрамление в markdown-код блоки, если модель добавила ```
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
