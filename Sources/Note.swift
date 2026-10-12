import Foundation

struct Note: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String
    var isPinned: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Title is the first non-empty line of the note
    var title: String {
        let lines = text.split(whereSeparator: \.isNewline).lazy.map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = lines.first(where: { !$0.isEmpty }) else {
            return "Новая заметка"
        }
        return String(first)
    }

    // Body preview is the second line/remaining preview
    var previewBody: String {
        let lines = text.split(whereSeparator: \.isNewline).lazy.map { $0.trimmingCharacters(in: .whitespaces) }
        let nonEmpties = Array(lines.filter { !$0.isEmpty }.prefix(2))
        if nonEmpties.count > 1 {
            return String(nonEmpties[1])
        }
        return "Нет дополнительного текста"
    }

    var characterCount: Int {
        text.count
    }

    var wordCount: Int {
        let words = text.split { $0.isWhitespace || $0.isNewline }
        return words.count
    }

    // Static cached formatters for smooth 60/120 fps scrolling
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM"
        return f
    }()

    var formattedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(updatedAt) {
            return Note.timeFormatter.string(from: updatedAt)
        } else if calendar.isDateInYesterday(updatedAt) {
            return "Вчера"
        } else {
            return Note.dateFormatter.string(from: updatedAt)
        }
    }
}
