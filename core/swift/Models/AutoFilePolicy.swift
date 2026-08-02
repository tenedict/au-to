import Foundation

/// 확인 없이 바로 캘린더에 넣어도 되는가.
///
/// 맥의 물방울에 이미지를 떨어뜨리면 **확인 화면 없이** 캘린더로 들어간다.
/// 그게 이 흐름의 전부다 — 한 번 끌어다 놓는 것.
///
/// 하지만 "AI 결과는 제안이다"(ADR-4)를 버리지는 않는다. 대신 두 갈래로 나눈다.
///
/// | 분명할 때 | 바로 넣고 **되돌릴 수 있게** 한다 |
/// | 모호할 때 | 그때만 확인 화면을 연다 |
///
/// 되돌리기가 확인 화면을 대신하는 이유 — 확인 화면은 **저장 전에** 사람을 세우고,
/// 되돌리기는 **저장 후에** 사람에게 결정권을 남긴다. 둘 다 사람이 최종 판단을 한다.
/// 다른 것은 속도뿐이다.
enum AutoFileDecision: Equatable {
    /// 바로 넣는다. 배너로 알리고 실행 취소를 준다.
    case fileNow
    /// 확인 화면을 연다. `reason` 은 사용자에게 그대로 보여준다.
    case askFirst(reason: String)

    var isAutomatic: Bool { self == .fileNow }
}

enum AutoFilePolicy {

    static func decide(for draft: TaskDraft) -> AutoFileDecision {
        // 날짜가 없으면 캘린더에 넣을 것 자체가 없다.
        guard draft.dueDate != nil else {
            return .askFirst(reason: "날짜를 찾지 못했어요. 언제로 할지 정해 주세요.")
        }

        // 모델이 스스로 헷갈린다고 말했다. 그 말을 믿는다.
        //
        // 이 검사를 confidence 보다 **먼저** 두는 이유 — 실제 호출에서 confidence 가
        // 0.9~1.0 으로만 나와 눈금 역할을 못 한다(12장 §3). 지금 실제로 거르고 있는
        // 것은 ambiguities 쪽이다.
        if let first = draft.ambiguities.first {
            return .askFirst(reason: first)
        }

        guard draft.confidence >= Confidence.autoCalendarThreshold else {
            return .askFirst(reason: "내용을 확실히 읽지 못했어요. 한번 봐 주세요.")
        }

        return .fileNow
    }
}

/// 바로 넣은 것 하나. 되돌리려면 무엇을 지워야 하는지 들고 있는다.
///
/// 캘린더 이벤트 식별자를 함께 담는 이유 — 되돌리기가 할 일만 지우고 캘린더 일정을
/// 남기면, 사용자는 "취소했는데 일정이 그대로"인 상태를 보게 된다.
struct FiledCapture: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let dueDate: Date?
    let hasExplicitTime: Bool
    let calendarEventIdentifier: String?
    let filedAt: Date

    /// 배너에 그대로 쓰는 문구.
    var summary: String {
        guard let dueDate else { return title }
        let when = dueDate.formatted(
            date: .abbreviated,
            time: hasExplicitTime ? .shortened : .omitted
        )
        return "\(title) · \(when)"
    }

    var wentToCalendar: Bool { calendarEventIdentifier != nil }
}
