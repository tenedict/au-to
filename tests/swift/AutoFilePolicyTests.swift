import XCTest
@testable import CaptureTask

/// 확인 없이 캘린더에 넣어도 되는지 판정.
///
/// 이 판정이 느슨하면 **잘못된 일정이 조용히 캘린더에 들어간다.** 사용자는
/// 자기가 넣지 않은 약속을 보게 되고, 그 순간 앱 전체를 믿지 않게 된다.
final class AutoFilePolicyTests: XCTestCase {

    private func draft(
        due: Date? = Date(timeIntervalSince1970: 1_786_000_000),
        confidence: Double = 0.95,
        ambiguities: [String] = []
    ) -> TaskDraft {
        TaskDraft(
            title: "치과 예약",
            dueDate: due,
            hasExplicitTime: due != nil,
            confidence: confidence,
            ambiguities: ambiguities
        )
    }

    func testClearDraftGoesStraightToTheCalendar() {
        XCTAssertEqual(AutoFilePolicy.decide(for: draft()), .fileNow)
    }

    /// 날짜가 없으면 캘린더에 넣을 것 자체가 없다.
    func testUndatedDraftAlwaysAsks() {
        let decision = AutoFilePolicy.decide(for: draft(due: nil, confidence: 1))

        XCTAssertFalse(decision.isAutomatic)
        guard case .askFirst(let reason) = decision else { return XCTFail() }
        XCTAssertTrue(reason.contains("날짜"), reason)
    }

    /// 모델이 스스로 헷갈린다고 말했으면 그 말을 믿는다.
    func testAmbiguityAlwaysAsksEvenAtFullConfidence() {
        let decision = AutoFilePolicy.decide(
            for: draft(confidence: 1, ambiguities: ["연도가 적혀 있지 않아요"])
        )

        XCTAssertEqual(decision, .askFirst(reason: "연도가 적혀 있지 않아요"))
    }

    /// **실제 호출에서 confidence 가 0.9~1.0 으로만 나온다** (12장 §3).
    /// 지금 실제로 거르고 있는 것은 ambiguities 쪽이므로, 그 검사가
    /// confidence 검사보다 **먼저** 와야 한다. 순서가 뒤집히면
    /// 모호한 초안이 높은 confidence 때문에 통과한다.
    func testAmbiguityIsCheckedBeforeConfidence() {
        let decision = AutoFilePolicy.decide(
            for: draft(confidence: 0.99, ambiguities: ["오전인지 오후인지 모르겠어요"])
        )

        guard case .askFirst(let reason) = decision else {
            return XCTFail("모호하면 물어봐야 합니다")
        }
        XCTAssertEqual(reason, "오전인지 오후인지 모르겠어요", "모호점을 그대로 보여줘야 합니다")
    }

    func testLowConfidenceAsks() {
        let decision = AutoFilePolicy.decide(
            for: draft(confidence: Confidence.autoCalendarThreshold - 0.01)
        )
        XCTAssertFalse(decision.isAutomatic)
    }

    func testThresholdItselfPasses() {
        XCTAssertEqual(
            AutoFilePolicy.decide(for: draft(confidence: Confidence.autoCalendarThreshold)),
            .fileNow
        )
    }

    /// 물어볼 때는 **왜** 물어보는지 함께 준다. 이유 없는 확인 요구는
    /// 사용자에게 "또 뭘 하라는 거지" 로 읽힌다 (CLAUDE 규칙 12).
    func testEveryAskCarriesAReason() {
        let cases = [
            draft(due: nil),
            draft(confidence: 0.1),
            draft(ambiguities: ["모호"]),
        ]

        for candidate in cases {
            guard case .askFirst(let reason) = AutoFilePolicy.decide(for: candidate) else {
                return XCTFail("\(candidate.title) 은 물어봐야 합니다")
            }
            XCTAssertFalse(reason.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - 되돌리기

    /// 되돌리기가 할 일만 지우고 캘린더 일정을 남기면, 사용자는
    /// "취소했는데 일정이 그대로" 인 상태를 보게 된다.
    func testFiledCaptureRemembersTheCalendarEvent() {
        let filed = FiledCapture(
            id: UUID(),
            title: "치과",
            dueDate: Date(timeIntervalSince1970: 1_786_000_000),
            hasExplicitTime: true,
            calendarEventIdentifier: "EV-1",
            filedAt: .now
        )

        XCTAssertTrue(filed.wentToCalendar)
        XCTAssertTrue(filed.summary.contains("치과"))
    }

    func testSummaryWorksWithoutADate() {
        let filed = FiledCapture(
            id: UUID(),
            title: "언젠가 할 일",
            dueDate: nil,
            hasExplicitTime: false,
            calendarEventIdentifier: nil,
            filedAt: .now
        )

        XCTAssertEqual(filed.summary, "언젠가 할 일")
        XCTAssertFalse(filed.wentToCalendar)
    }
}
