import Foundation

/// Synchronous storage. The view model serializes writes on its own I/O queue.
struct NotesFileStore {
    let fileURL: URL

    static var defaultURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("minimal_notes.json")
    }

    /// nil means first launch; [] means the user intentionally has no notes.
    func load() throws -> [Note]? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        let notes = try JSONDecoder().decode([Note].self, from: data)
        guard Set(notes.map(\.id)).count == notes.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return notes
    }

    func save(_ notes: [Note]) throws {
        let data = try JSONEncoder().encode(notes)
        try data.write(to: fileURL, options: .atomic)
    }
}
