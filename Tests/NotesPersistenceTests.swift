import XCTest
import Combine
@testable import NotesApp

final class NotesPersistenceTests: XCTestCase {
    private func temporaryStore() throws -> NotesFileStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return NotesFileStore(fileURL: directory.appendingPathComponent("minimal_notes.json"))
    }

    func testLegacyJSONRoundTripPreservesAllFields() throws {
        let store = try temporaryStore()
        let data = Data("""
        [{"id":"138518B0-AB42-411F-BD81-3DA6E4128C54","text":"Заголовок\\nТекст 📝",
          "isPinned":true,"createdAt":100,"updatedAt":200}]
        """.utf8)
        try data.write(to: store.fileURL)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].text, "Заголовок\nТекст 📝")
        XCTAssertEqual(loaded[0].createdAt, Date(timeIntervalSinceReferenceDate: 100))
        XCTAssertTrue(loaded[0].isPinned)
        try store.save(loaded)
        XCTAssertEqual(try store.load(), loaded)
    }

    func testMissingAndIntentionallyEmptyFilesDiffer() throws {
        let store = try temporaryStore()
        XCTAssertNil(try store.load())
        try store.save([])
        XCTAssertEqual(try store.load(), [])
    }

    @MainActor
    func testCorruptFileCannotBeOverwrittenByInitializationOrEditing() async throws {
        let store = try temporaryStore()
        let original = Data("important but invalid json".utf8)
        try original.write(to: store.fileURL)
        let model = NotesViewModel(fileURL: store.fileURL)
        XCTAssertFalse(model.canEdit)
        XCTAssertNil(model.createNote())
        model.flush()
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
        XCTAssertNotNil(model.storageAlert)
    }

    func testDuplicateIDsFailWithoutModifyingFile() throws {
        let store = try temporaryStore()
        let note = Note(text: "Не терять")
        try store.save([note, note])
        let before = try Data(contentsOf: store.fileURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.fileURL), before)
    }

    @MainActor
    func testDeletingAllNotesStaysEmptyAfterRelaunch() async throws {
        let store = try temporaryStore()
        let note = Note(text: "Удалить")
        try store.save([note])
        let model = NotesViewModel(fileURL: store.fileURL)
        model.deleteNote(id: note.id)
        model.flush()
        let reopened = NotesViewModel(fileURL: store.fileURL)
        XCTAssertTrue(reopened.notes.isEmpty)
        XCTAssertTrue(reopened.canEdit)
    }

    @MainActor
    func testFlushSavesLatestTextBeforeDebounceAndPreservesWriteOrder() async throws {
        let store = try temporaryStore()
        try store.save([])
        let model = NotesViewModel(fileURL: store.fileURL, saveDelay: 60)
        let note = try XCTUnwrap(model.createNote())
        model.updateNote(id: note.id, text: "Первый текст")
        model.togglePin(id: note.id)
        model.updateNote(id: note.id, text: "Последний текст")
        model.flush()
        let saved = try XCTUnwrap(store.load())
        XCTAssertEqual(saved.first?.text, "Последний текст")
        XCTAssertEqual(saved.first?.isPinned, true)
        XCTAssertFalse(model.hasUnsavedChanges)
        // Allow old asynchronous completions to arrive after the synchronous flush.
        await Task.yield()
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    @MainActor
    func testFinishingOneDraftDoesNotRemoveOtherBlankNotes() async throws {
        let store = try temporaryStore()
        let first = Note(text: "")
        let second = Note(text: " ")
        let existing = Note(text: "Текст")
        try store.save([first, second, existing])
        let model = NotesViewModel(fileURL: store.fileURL)
        model.finishEditing(id: first.id)
        XCTAssertEqual(try store.load()?.map(\.id), [second.id, existing.id])
    }

    @MainActor
    func testUnchangedTextDoesNotChangeDateOrDirtyState() async throws {
        let store = try temporaryStore()
        let note = Note(text: "Текст")
        try store.save([note])
        let model = NotesViewModel(fileURL: store.fileURL)
        model.updateNote(id: note.id, text: note.text)
        XCTAssertEqual(model.notes, [note])
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    @MainActor
    func testFailedWriteRetainsChangesAndCanBeRetried() async throws {
        let store = try temporaryStore()
        let note = Note(text: "Старый текст")
        try store.save([note])
        let model = NotesViewModel(fileURL: store.fileURL, saveDelay: 60)
        // A directory at the file path reliably prevents an atomic file write.
        try FileManager.default.removeItem(at: store.fileURL)
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: false)
        model.updateNote(id: note.id, text: "Новый текст")
        model.flush()
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertNotNil(model.storageAlert)
        XCTAssertEqual(model.notes.first?.text, "Новый текст")
        try FileManager.default.removeItem(at: store.fileURL)
        model.flush()
        XCTAssertEqual(try store.load()?.first?.text, "Новый текст")
        XCTAssertFalse(model.hasUnsavedChanges)
        XCTAssertNil(model.storageAlert)
    }

    @MainActor
    func testReadFailureCanBeRetriedWithoutSeedingSample() async throws {
        let store = try temporaryStore()
        try Data("{".utf8).write(to: store.fileURL)
        let model = NotesViewModel(fileURL: store.fileURL)
        let note = Note(text: "Восстановленная заметка")
        try store.save([note])
        model.retryStorage()
        XCTAssertTrue(model.canEdit)
        XCTAssertEqual(model.notes, [note])
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    @MainActor
    func testSearchTrimsNewlinesAndIgnoresCase() async throws {
        let store = try temporaryStore()
        let note = Note(text: "Заметка о Москве")
        try store.save([note, Note(text: "Другой город")])
        let model = NotesViewModel(fileURL: store.fileURL)
        model.searchText = " \nМОСКВЕ\n "
        XCTAssertEqual(model.filteredNotes, [note])
    }
    @MainActor
    func testDebouncedWritePersistsWhileEditorRemainsOpen() async throws {
        let store = try temporaryStore()
        let note = Note(text: "Before")
        try store.save([note])
        let model = NotesViewModel(fileURL: store.fileURL, saveDelay: 0.01)
        model.updateNote(id: note.id, text: "After")
        let saved = expectation(description: "Debounced write completed")
        let subscription = model.$hasUnsavedChanges
            .filter { !$0 }
            .prefix(1)
            .sink { _ in saved.fulfill() }
        await fulfillment(of: [saved], timeout: 30)
        withExtendedLifetime(subscription) {}
        XCTAssertEqual(try store.load()?.first?.text, "After")
    }

}
