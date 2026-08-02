import SwiftUI

@main
struct CaptureTaskApp: App {
    @StateObject private var store = TaskStore()
    @StateObject private var reminderTaps = ReminderTapRouter()
    /// 읽기를 들고 있는 줄. 화면이 아니라 앱이 소유한다 —
    /// 시트가 닫히거나 탭을 옮겨도 처리가 끊기면 안 된다 (`CaptureQueue` 참고).
    @StateObject private var queue: CaptureQueue

    init() {
        let store = TaskStore()
        _store = StateObject(wrappedValue: store)
        _queue = StateObject(wrappedValue: CaptureQueue(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView(store: store, queue: queue, reminderTaps: reminderTaps)
                // 델리게이트는 앱이 뜬 직후에 붙어야 한다. 첫 화면이 그려진 뒤에
                // 붙이면 잠금 화면에서 알림을 눌러 들어온 첫 실행을 놓친다.
                .onAppear { reminderTaps.install() }
        }
    }
}
