import SwiftUI

@main
struct CaptureTaskApp: App {
    @StateObject private var store = TaskStore()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
        }
    }
}
