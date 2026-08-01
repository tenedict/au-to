import Foundation
import UserNotifications

/// "확인해 주세요" 알림. 앱과 Share Extension 이 함께 쓴다.
///
/// **왜 필요한가** — 분석은 메인 앱에서만 돈다. 공유 시트로 담고 앱을 열지 않으면
/// 스크린샷은 상자에 그대로 남고 사용자에게는 아무 일도 일어나지 않는다.
/// 담은 것을 잊으면 이 제품은 사진첩과 같아진다.
///
/// **왜 Extension 이 이걸 해도 되나** — 프로젝트 규칙 3 은 Extension 에서
/// 네트워크·EventKit·Vision 을 막는다. 그것들은 수백 밀리초에서 수 초가 걸려
/// 시스템이 Extension 을 죽이기 때문이다. 로컬 알림 예약은 파일 쓰기 한 번 수준이라
/// 같은 위험이 없다. 그래서 이것만 허용하고 나머지는 그대로 막는다.
enum CaptureNotice {

    /// 이 접두사로 마감 알림과 구분한다. 앞에 붙은 것만 보고 지울 수 있어야 한다.
    static let identifierPrefix = "capture#"

    /// 확인 안 한 초안을 남기고 앱을 나갔을 때 다시 알리기까지의 시간.
    ///
    /// 곧바로 다시 울리면 잔소리가 되고, 하루 뒤면 이미 잊는다.
    static let unconfirmedDraftDelay: TimeInterval = 60 * 60

    static func identifier(for captureID: UUID) -> String {
        "\(identifierPrefix)\(captureID.uuidString)"
    }

    static let unconfirmedDraftsIdentifier = "\(identifierPrefix)unconfirmed-drafts"

    static func isCaptureNotice(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    // MARK: - 담았을 때 (Share Extension)

    /// 스크린샷을 담은 직후 알린다.
    ///
    /// 문구가 "할 일을 만들었어요" 가 아닌 이유 — 이 시점에는 아직 아무것도 읽지 않았다.
    /// 하지 않은 일을 했다고 말하면 열어 봤을 때 어긋난다.
    static func postCaptureTaken(captureID: UUID, center: UNUserNotificationCenter = .current()) {
        let content = UNMutableNotificationContent()
        content.title = "스크린샷을 담았어요"
        content.body = "눌러서 할 일로 만들지 확인해 주세요."
        content.sound = .default
        content.userInfo = ["captureID": captureID.uuidString]

        // trigger 가 nil 이면 곧바로 전달된다. Extension 이 닫힌 뒤에도 남는다.
        center.add(
            UNNotificationRequest(
                identifier: identifier(for: captureID),
                content: content,
                trigger: nil
            )
        )
    }

    // MARK: - 확인 안 한 초안이 남았을 때 (메인 앱)

    /// 확인을 기다리는 초안이 있는 채로 앱을 나갔을 때 다시 알린다.
    static func scheduleUnconfirmedDrafts(
        count: Int,
        center: UNUserNotificationCenter = .current()
    ) {
        guard count > 0 else {
            cancelUnconfirmedDrafts(center: center)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "확인할 할 일 \(count)개가 있어요"
        content.body = "저장하기 전에 제목과 날짜를 확인해 주세요."
        content.sound = .default

        center.add(
            UNNotificationRequest(
                identifier: unconfirmedDraftsIdentifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: unconfirmedDraftDelay,
                    repeats: false
                )
            )
        )
    }

    static func cancelUnconfirmedDrafts(center: UNUserNotificationCenter = .current()) {
        center.removePendingNotificationRequests(withIdentifiers: [unconfirmedDraftsIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [unconfirmedDraftsIdentifier])
    }

    // MARK: - 정리

    /// 이 캡처의 알림을 지운다.
    ///
    /// **전달된 것까지 지운다.** 예약만 지우면 알림 센터에 남아, 사용자는 이미 처리한
    /// 스크린샷을 확인하러 앱을 다시 연다.
    static func clear(captureID: UUID, center: UNUserNotificationCenter = .current()) {
        let ids = [identifier(for: captureID)]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }
}
