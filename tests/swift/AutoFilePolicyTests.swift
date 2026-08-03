import XCTest
@testable import Whenly

/// 등록은 언제나 하고, **무엇을 사람이 봐야 하는지**만 가린다.
///
/// 이 판정이 등록을 막던 때가 있었다. 그러면 애매한 스크린샷을 놓은 사용자에게
/// 아무 일도 일어나지 않았고, 그게 이 제품이 없애려던 상태였다 (ADR-4 개정).
///
/// 지금 이 판정이 실제로 막는 것은 **Apple 캘린더에 쓰는 것 하나뿐**이다 —
/// 할 일은 우리 원장이라 되돌리기 쉽지만, 캘린더는 밖으로 나가는 출력이라
/// 잘못 들어간 일정의 무게가 다르다.
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

    // MARK: - 봐야 하는가

    func testClearDraftNeedsNoReview() {
        XCTAssertNil(AutoFilePolicy.reviewReason(for: draft()))
        XCTAssertTrue(AutoFilePolicy.mayAutoAddToCalendar(draft()))
    }

    /// 날짜가 없으면 언제 할 일인지 아무도 모른다. 등록은 하되 반드시 물어본다.
    func testUndatedDraftAlwaysNeedsReview() throws {
        let reason = try XCTUnwrap(AutoFilePolicy.reviewReason(for: draft(due: nil, confidence: 1)))

        XCTAssertTrue(reason.contains("날짜"), reason)
        XCTAssertFalse(
            AutoFilePolicy.mayAutoAddToCalendar(draft(due: nil, confidence: 1)),
            "날짜 없이 캘린더에 넣을 수는 없습니다")
    }

    /// 모델이 스스로 헷갈린다고 말했으면 그 말을 믿는다.
    func testAmbiguityAlwaysNeedsReviewEvenAtFullConfidence() {
        XCTAssertEqual(
            AutoFilePolicy.reviewReason(
                for: draft(confidence: 1, ambiguities: ["연도가 적혀 있지 않아요"])),
            "연도가 적혀 있지 않아요")
    }

    /// **실제 호출에서 confidence 가 0.9~1.0 으로만 나온다** (12장 §3).
    /// 지금 실제로 거르고 있는 것은 ambiguities 쪽이므로, 그 검사가
    /// confidence 검사보다 **먼저** 와야 한다. 순서가 뒤집히면
    /// 모호한 초안이 높은 confidence 때문에 그냥 지나간다.
    func testAmbiguityIsCheckedBeforeConfidence() {
        XCTAssertEqual(
            AutoFilePolicy.reviewReason(
                for: draft(confidence: 0.99, ambiguities: ["오전인지 오후인지 모르겠어요"])),
            "오전인지 오후인지 모르겠어요",
            "모호점을 그대로 보여줘야 합니다")
    }

    func testLowConfidenceNeedsReview() {
        XCTAssertNotNil(
            AutoFilePolicy.reviewReason(
                for: draft(confidence: Confidence.autoCalendarThreshold - 0.01)))
    }

    func testThresholdItselfPasses() {
        XCTAssertNil(
            AutoFilePolicy.reviewReason(for: draft(confidence: Confidence.autoCalendarThreshold)))
    }

    /// 물어볼 때는 **왜** 물어보는지 함께 준다. 이유 없는 확인 요구는
    /// 사용자에게 "또 뭘 하라는 거지" 로 읽힌다 (CLAUDE 규칙 12).
    func testEveryReviewCarriesAReason() throws {
        for candidate in [draft(due: nil), draft(confidence: 0.1), draft(ambiguities: ["모호"])] {
            let reason = try XCTUnwrap(
                AutoFilePolicy.reviewReason(for: candidate), "\(candidate.title) 은 봐야 합니다")
            XCTAssertFalse(reason.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - 등록은 막지 않는다

    /// **이 파일에서 가장 중요한 테스트.**
    ///
    /// 어떤 초안이든 할 일이 된다. 여기가 무너지면 사용자는 스크린샷을 놓고도
    /// 아무 일이 일어나지 않는 것을 보게 되고, 그때 이 앱은 사진첩과 같아진다.
    func testEveryDraftBecomesATaskNoMatterHowAmbiguous() {
        let now = Date(timeIntervalSince1970: 1_786_000_000)
        let candidates = [
            draft(),
            draft(due: nil),
            draft(confidence: 0),
            draft(ambiguities: ["아무것도 모르겠어요"]),
        ]

        for candidate in candidates {
            let task = candidate.makeTask(now: now)
            XCTAssertEqual(task.id, candidate.id, "신원이 바뀌면 캡처와 이어지지 않습니다")
            XCTAssertFalse(task.title.isEmpty)
        }
    }

    /// 애매한 초안은 할 일이 되면서 **이유를 달고 온다.**
    func testAmbiguousDraftCarriesItsReasonIntoTheTask() {
        let now = Date(timeIntervalSince1970: 1_786_000_000)
        let task = draft(due: nil).makeTask(now: now)

        XCTAssertTrue(task.needsReview)
        XCTAssertEqual(task.reviewReason, AutoFilePolicy.reviewReason(for: draft(due: nil)))
    }

    func testClearDraftCarriesNoFlag() {
        XCTAssertFalse(draft().makeTask(now: .now).needsReview)
    }

    // MARK: - 등록 결과

    /// 알림이 이 값을 그대로 읽는다. 캘린더 식별자를 잃으면 지울 때 일정이 남는다.
    func testFiledCaptureRemembersTheCalendarEvent() {
        let filed = FiledCapture(
            id: UUID(),
            title: "치과",
            dueDate: Date(timeIntervalSince1970: 1_786_000_000),
            hasExplicitTime: true,
            calendarEventIdentifier: "EV-1",
            reviewReason: nil,
            filedAt: .now
        )

        XCTAssertTrue(filed.wentToCalendar)
        XCTAssertFalse(filed.needsReview)
        XCTAssertTrue(filed.summary.contains("치과"))
    }

    /// 날짜가 없어도 등록은 됐다. 알림 문구가 그 사실을 말해야 한다 —
    /// 제목만 적으면 사용자는 언제인지 모른 채 넘어간다.
    func testSummarySaysTheDateIsMissing() {
        let filed = FiledCapture(
            id: UUID(),
            title: "언젠가 할 일",
            dueDate: nil,
            hasExplicitTime: false,
            calendarEventIdentifier: nil,
            reviewReason: "날짜를 찾지 못했어요.",
            filedAt: .now
        )

        XCTAssertEqual(filed.summary, "언젠가 할 일 · 날짜 미정")
        XCTAssertTrue(filed.needsReview)
        XCTAssertFalse(filed.wentToCalendar)
    }
}
