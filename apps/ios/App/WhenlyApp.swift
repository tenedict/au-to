import SwiftUI
import UIKit

@main
struct WhenlyApp: App {
    /// **알림 델리게이트를 앱이 뜨기 전에 붙이기 위해** UIKit 델리게이트를 쓴다.
    ///
    /// `.onAppear` 에서 붙였더니 첫 화면이 그려진 뒤가 되고, 알림을 눌러 들어온
    /// 첫 실행은 시스템이 그 응답을 이미 버린 뒤였다 — 사용자에게는 **눌러도
    /// 아무 데도 안 가는 것**으로 보인다.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView(
                store: delegate.store,
                queue: delegate.queue,
                reminderTaps: delegate.reminderTaps
            )
        }
    }
}

/// 앱과 함께 사는 것들의 주인.
///
/// 저장소·읽기 줄·알림 라우터를 화면이 아니라 여기가 들고 있다. 화면이 들고 있으면
/// 시트가 닫히거나 탭을 옮길 때 처리가 끊긴다 (`CaptureQueue` 참고).
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    let store = TaskStore()
    let reminderTaps = ReminderTapRouter()
    private(set) lazy var queue = CaptureQueue(store: store)

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 화면보다 먼저. 이 순서가 이 함수의 존재 이유다.
        reminderTaps.install()
        return true
    }
}
