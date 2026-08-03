import Foundation

#if canImport(AppKit)
import AppKit
#endif

// `APP_EXTENSION` 은 project.yml 이 확장 타깃에만 켜 준다.
//
// **`UIApplication.shared` 는 확장에서 아예 쓸 수 없다** (컴파일 오류다).
// core/swift 는 앱과 확장이 함께 쓰므로 여기서 갈라 둬야 한다.
// 확장은 애초에 이 시간이 필요 없다 — 공유 확장은 자기 수명이 따로 있고,
// 위젯은 캡처를 읽지 않는다.
#if canImport(UIKit) && !APP_EXTENSION
import UIKit
#endif

/// 앱이 뒤로 가도 하던 일을 마치게 해 달라고 시스템에 요청하는 자리.
///
/// ## 왜 필요한가
///
/// 사진을 찍고 앱을 나가면 iOS 는 **몇 초 안에 앱을 재운다.** 그러면
///
///   1. 백엔드로 가던 요청이 끊긴다
///   2. 알림이 오지 않는다
///   3. 다시 들어오면 캡처가 상자에 남아 있어 처음부터 다시 읽는다
///   4. 그 사이 사용자는 "로딩 중" 과 "요청 시간이 다 됐어요" 만 본다
///
/// 실제로 그렇게 됐다. 잠금화면 위젯 → 카메라 → 찍기 는 **찍자마자 앱을 나가는**
/// 동선이라 이 문제를 정면으로 맞는다.
///
/// `beginBackgroundTask` 는 대략 30초를 준다. OCR 은 수백 밀리초, 백엔드 호출은
/// 몇 초라서 한 장에는 넉넉하다. 여러 장이면 중간에 시간이 끊길 수 있는데,
/// 그때도 **잃지는 않는다** — 캡처는 상자에 남고 다음 실행이 이어서 처리한다 (ADR-2).
///
/// ## 왜 프로토콜인가
///
/// `UIApplication` 은 테스트에서 만질 수 없고 macOS 에는 없다. 여기서 가려 두면
/// `CaptureQueue` 는 플랫폼을 모른 채로 남는다.
protocol BackgroundActivityGranting: Sendable {
    /// 일을 시작한다고 알린다. 끝나면 반드시 돌려받은 토큰으로 `end` 를 부른다.
    @MainActor func begin(reason: String) -> BackgroundActivityToken
    @MainActor func end(_ token: BackgroundActivityToken)
}

/// 시작한 일 하나. 무엇인지는 플랫폼마다 다르므로 상자에 담아 둔다.
struct BackgroundActivityToken {
    fileprivate let value: Any?

    fileprivate init(_ value: Any?) { self.value = value }

    static let none = BackgroundActivityToken(nil)
}

/// 이 기기에서 실제로 시간을 얻어 오는 구현.
struct SystemBackgroundActivity: BackgroundActivityGranting {

    @MainActor
    func begin(reason: String) -> BackgroundActivityToken {
        #if canImport(UIKit) && !APP_EXTENSION
        // 만료 처리를 반드시 준다. 없으면 시스템이 앱을 **강제 종료**한다.
        // 우리는 여기서 아무것도 정리할 것이 없다 — 캡처는 상자에 남아 있고
        // 다음 실행이 이어서 처리하기 때문이다. 토큰만 돌려준다.
        var identifier = UIBackgroundTaskIdentifier.invalid
        identifier = UIApplication.shared.beginBackgroundTask(withName: reason) {
            UIApplication.shared.endBackgroundTask(identifier)
        }
        return BackgroundActivityToken(identifier)
        #elseif canImport(AppKit)
        // macOS 는 앱을 재우지 않는다. 다만 App Nap 이 타이머와 네트워크를 늦출 수
        // 있어서, 그것만 막아 둔다.
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated], reason: reason)
        return BackgroundActivityToken(activity)
        #else
        // 확장에서는 요청할 것이 없다.
        return .none
        #endif
    }

    @MainActor
    func end(_ token: BackgroundActivityToken) {
        #if canImport(UIKit) && !APP_EXTENSION
        guard let identifier = token.value as? UIBackgroundTaskIdentifier,
              identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        #elseif canImport(AppKit)
        guard let activity = token.value as? NSObjectProtocol else { return }
        ProcessInfo.processInfo.endActivity(activity)
        #endif
    }
}

/// 테스트용. 시간을 요청한 횟수만 센다.
final class RecordingBackgroundActivity: BackgroundActivityGranting, @unchecked Sendable {
    private(set) var begun = 0
    private(set) var ended = 0

    @MainActor
    func begin(reason: String) -> BackgroundActivityToken {
        begun += 1
        return BackgroundActivityToken(begun)
    }

    @MainActor
    func end(_ token: BackgroundActivityToken) { ended += 1 }
}
