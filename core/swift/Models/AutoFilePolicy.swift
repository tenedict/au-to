import Foundation

/// 분석 결과를 받았을 때 사람이 무엇을 해야 하는가.
///
/// ## 등록은 언제나 한다
///
/// 예전에는 이 파일이 **등록을 막는** 판정을 했다. 날짜가 모호하면 할 일을 만들지
/// 않고 확인을 기다렸다. 그 결과는 이랬다 —
///
/// > 사용자가 스크린샷을 놓았는데 **아무 일도 일어나지 않는다.**
///
/// 그게 정확히 이 제품이 없애려던 상태다. 담아 두기만 하고 아무것도 안 되는 것은
/// 사진첩이 이미 잘하고 있다.
///
/// 그래서 판정의 뜻을 바꿨다. **막는 값이 아니라 붙이는 값이다.**
///
/// ```
/// 분명하다      →  등록한다
/// 애매하다      →  등록한다 + "여기를 봐 주세요" 를 붙인다
/// ```
///
/// 붙인 이유는 `AssistantTask.reviewReason` 으로 따라다니고, 사용자가 확인하면
/// 사라진다. 사람이 최종 판단을 하는 자리는 저장 앞이 아니라 **저장 뒤**다 (ADR-4).
///
/// ## 그래도 캘린더는 다르다
///
/// 할 일은 우리 원장이라 되돌리기 쉽지만, Apple 캘린더는 **밖으로 나가는 출력**이다.
/// 남의 캘린더에 잘못된 일정이 뜨는 것은 우리 목록에 한 줄 잘못 있는 것과 무게가
/// 다르다. 그래서 캘린더 자동 추가만은 확인이 필요 없을 때로 남긴다
/// (`mayAutoAddToCalendar`).
enum AutoFilePolicy {

    /// 사람이 봐야 하는 이유. 볼 것이 없으면 `nil`.
    ///
    /// 사용자에게 그대로 보여주는 문구다. "confidence 0.62" 같은 것을 적지 않는다 —
    /// 무엇을 어떻게 고치라는 것인지 알 수 없다.
    static func reviewReason(for draft: TaskDraft) -> String? {
        // 날짜가 없으면 언제 할 일인지 아무도 모른다. 가장 먼저 본다.
        guard draft.dueDate != nil else {
            return "날짜를 찾지 못했어요. 언제로 할지 정해 주세요."
        }

        // 모델이 스스로 헷갈린다고 말했다. 그 말을 믿는다.
        //
        // 이 검사를 confidence 보다 **먼저** 두는 이유 — 실제 호출에서 confidence 가
        // 0.9~1.0 으로만 나와 눈금 역할을 못 한다(12장 §3). 지금 실제로 거르고 있는
        // 것은 ambiguities 쪽이다.
        if let first = draft.ambiguities.first {
            return first
        }

        guard draft.confidence >= Confidence.autoCalendarThreshold else {
            return "내용을 확실히 읽지 못했어요. 한번 봐 주세요."
        }

        return nil
    }

    /// 확인 없이 Apple 캘린더에까지 넣어도 되는가.
    ///
    /// 할 일 등록과 달리 여기는 문턱을 남긴다 — 캘린더는 밖으로 나가는 출력이라
    /// 잘못 들어간 일정의 무게가 다르다.
    static func mayAutoAddToCalendar(_ draft: TaskDraft) -> Bool {
        reviewReason(for: draft) == nil
    }
}

/// 등록한 것 하나. 무엇이 등록됐는지 알림이 그대로 읽는다.
struct FiledCapture: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let dueDate: Date?
    let hasExplicitTime: Bool
    let calendarEventIdentifier: String?
    /// 사람이 봐야 하는 이유. 알림이 이걸 보고 문구를 고른다.
    let reviewReason: String?
    let filedAt: Date

    /// 알림과 목록에 그대로 쓰는 문구.
    var summary: String {
        guard let dueDate else { return "\(title) · 날짜 미정" }
        let when = dueDate.formatted(
            date: .abbreviated,
            time: hasExplicitTime ? .shortened : .omitted
        )
        return "\(title) · \(when)"
    }

    var needsReview: Bool { reviewReason != nil }

    var wentToCalendar: Bool { calendarEventIdentifier != nil }
}
