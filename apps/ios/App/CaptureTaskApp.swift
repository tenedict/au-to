import SwiftUI

@main
struct CaptureTaskApp: App {
    @StateObject private var store = TaskStore()
    @StateObject private var reminderTaps = ReminderTapRouter()

    var body: some Scene {
        WindowGroup {
            RootView(store: store, reminderTaps: reminderTaps)
                // 델리게이트는 앱이 뜬 직후에 붙어야 한다. 첫 화면이 그려진 뒤에
                // 붙이면 잠금 화면에서 알림을 눌러 들어온 첫 실행을 놓친다.
                .onAppear { reminderTaps.install() }
        }
    }
}
