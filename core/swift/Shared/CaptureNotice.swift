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

    static func identifier(for captureID: UUID) -> String {
        "\(identifierPrefix)\(captureID.uuidString)"
    }

    static func isCaptureNotice(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    // MARK: - 등록하고 난 뒤

    /// **등록을 마쳤을 때.** 이게 흐름의 마지막 단계다.
    ///
    ///   스크린샷 → 공유·드롭 → 등록 → "언제 무슨 일정이 등록되었습니다"
    ///
    /// 문구에 **언제**와 **무엇**이 다 들어가야 한다. "등록했어요" 만으로는
    /// 사용자가 앱을 열어 확인해야 하고, 그러면 단계를 줄인 의미가 없다.
    ///
    /// **누르면 그 일정이 열려야 한다.** 그래서 `taskID` 를 싣는다 — 없으면 앱은
    /// 열리지만 목록 맨 위에서 사용자가 그것을 **다시 찾아야** 하고, 그건 알림을
    /// 누른 이유가 사라지는 것이다.
    static func postFiled(
        _ filed: [FiledCapture],
        captureID: UUID?,
        center: UNUserNotificationCenter = .current()
    ) {
        guard let first = filed.first else { return }
        let needing = filed.filter(\.needsReview)

        let content = UNMutableNotificationContent()
        content.title = filed.count == 1
            ? "일정을 등록했어요"
            : "일정 \(filed.count)개를 등록했어요"

        // 여러 개면 줄바꿈으로 나열한다. 알림은 펼치면 여러 줄이 보인다.
        var lines = filed.prefix(maxSummariesInBody).map(\.summary)
        if filed.count > maxSummariesInBody {
            lines.append("외 \(filed.count - maxSummariesInBody)개")
        }
        // 애매했던 것도 **등록은 됐다.** 다만 한 번 봐 달라고 덧붙인다 —
        // 이 줄이 없으면 사용자는 잘못 읽힌 일정을 영영 모른 채 지나간다.
        if !needing.isEmpty {
            lines.append(
                needing.count == filed.count
                    ? "눌러서 한 번 확인해 주세요."
                    : "\(needing.count)개는 눌러서 확인해 주세요.")
        }
        content.body = lines.joined(separator: "\n")
        content.sound = .default

        // 누르면 열 것. 봐야 하는 것이 있으면 그것을 먼저 연다.
        let target = needing.first ?? first
        content.userInfo = [
            "taskID": target.id.uuidString,
            "captureID": captureID?.uuidString ?? "",
        ]

        center.add(
            UNNotificationRequest(
                identifier: "\(identifierPrefix)filed-\(target.id.uuidString)",
                content: content,
                trigger: nil
            )
        )
    }

    /// 알림 본문에 나열할 최대 개수. 그 이상은 "외 N개" 로 줄인다.
    static let maxSummariesInBody = 3

    /// **아무것도 찾지 못했을 때.**
    ///
    /// 조용히 넘어가면 사용자는 놓기가 먹히지 않은 것으로 읽고, 같은 스크린샷을
    /// 몇 번이고 다시 끌어다 놓는다. 실패도 결과다.
    static func postNothingFound(
        captureID: UUID?,
        reason: String?,
        center: UNUserNotificationCenter = .current()
    ) {
        let content = UNMutableNotificationContent()
        content.title = "일정을 찾지 못했어요"
        content.body = reason ?? "이 스크린샷에서 날짜와 할 일을 읽지 못했어요."
        content.sound = .default
        if let captureID {
            content.userInfo = ["captureID": captureID.uuidString]
        }

        center.add(
            UNNotificationRequest(
                identifier: "\(identifierPrefix)empty-\(captureID?.uuidString ?? UUID().uuidString)",
                content: content,
                trigger: nil
            )
        )
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
