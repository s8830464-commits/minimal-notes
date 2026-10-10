import SwiftUI

@main
struct NotesApp: App {
    @StateObject private var viewModel = NotesViewModel()

    var body: some Scene {
        WindowGroup {
            NotesListView()
                .environmentObject(viewModel)
        }
    }
}
