import Foundation

struct Note: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String
    var isPinned: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Title is the first non-empty line of the note (just like Apple Notes)
    var title: String {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = lines.first(where: { !$0.isEmpty }) else {
            return "Новая заметка"
        }
        return String(first)
    }

    // Body preview is the second line/remaining preview
    var previewBody: String {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let nonEmpties = lines.filter { !$0.isEmpty }
        if nonEmpties.count > 1 {
            return String(nonEmpties[1])
        }
        return "Нет дополнительного текста"
    }

    // Word and character count
    var characterCount: Int {
        text.count
    }

    var wordCount: Int {
        let words = text.split { $0.isWhitespace || $0.isNewline }
        return words.count
    }

    // Formatted date
    var formattedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(updatedAt) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: updatedAt)
        } else if calendar.isDateInYesterday(updatedAt) {
            return "Вчера"
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.dateFormat = "d MMM"
            return formatter.string(from: updatedAt)
        }
    }
}
