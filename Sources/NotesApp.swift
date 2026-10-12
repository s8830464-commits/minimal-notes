import SwiftUI

@main
struct NotesApp: App {
    @StateObject private var viewModel = NotesViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NotesListView()
                .environmentObject(viewModel)
                .alert(item: $viewModel.storageAlert) { alert in
                    Alert(
                        title: Text(alert.operation == .load
                                    ? "Не удалось прочитать заметки"
                                    : "Не удалось сохранить заметки"),
                        message: Text(alert.message),
                        primaryButton: .default(Text("Повторить")) {
                            viewModel.retryStorage()
                        },
                        secondaryButton: .cancel(Text("Позже"))
                    )
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                viewModel.flush()
            }
        }
    }
}
