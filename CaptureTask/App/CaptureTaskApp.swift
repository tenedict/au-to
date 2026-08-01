import SwiftUI

@main
struct CaptureTaskApp: App {
    @StateObject private var store = TaskStore()

    var body: some Scene {
        WindowGroup {
            TaskListView(store: store)
                .task {
                    await store.importPendingCaptures()
                }
        }
    }
}
