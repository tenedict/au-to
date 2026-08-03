import XCTest
@testable import Whenly

/// 분석기가 돌려준 한 건이 할 일이 되는 과정.
///
/// 판정 자체는 `AutoFilePolicyTests` 가 지킨다. 여기서는 **신원과 값이 그대로
/// 넘어가는지**만 본다 — 여기가 어긋나면 등록은 되는데 원본 캡처와 이어지지 않는다.
final class TaskDraftTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_786_000_000)

    func testDraftCreatesScreenshotTaskWhenCaptureIDExists() {
        let captureID = UUID()
        let draft = TaskDraft(title: "서류 제출", confidence: 0.9, sourceCaptureID: captureID)
        let task = draft.makeTask(now: now)

        XCTAssertEqual(task.origin, .screenshot)
        XCTAssertEqual(task.sourceCaptureID, captureID)
    }

    /// 캡처가 없으면 사람이 직접 넣은 것이다.
    func testDraftWithoutCaptureIsManual() {
        XCTAssertEqual(
            TaskDraft(title: "장보기", confidence: 0.9).makeTask(now: now).origin, .manual)
    }

    /// **만든 시각을 인자로 받는다.** 안에서 `.now` 를 읽으면 목록 순서를 검사하는
    /// 테스트가 실행 시각에 따라 흔들린다 (CLAUDE 규칙 10).
    func testCreationTimeComesFromTheCaller() {
        XCTAssertEqual(TaskDraft(title: "x", confidence: 1).makeTask(now: now).createdAt, now)
    }

    /// 값이 그대로 넘어가야 한다. 하나라도 빠지면 사용자는 자기가 보낸 것과
    /// 다른 일정을 보게 된다.
    func testEveryFieldSurvivesTheConversion() {
        let draft = TaskDraft(
            title: "치과 검진",
            notes: "10분 전 도착",
            dueDate: now,
            hasExplicitTime: true,
            confidence: 0.91
        )
        let task = draft.makeTask(now: now)

        XCTAssertEqual(task.title, "치과 검진")
        XCTAssertEqual(task.notes, "10분 전 도착")
        XCTAssertEqual(task.dueDate, now)
        XCTAssertTrue(task.hasExplicitTime)
        XCTAssertEqual(task.confidence, 0.91)
    }

    func testTaskCannotHaveExplicitTimeWithoutDate() {
        let task = AssistantTask(title: "날짜 없는 일", dueDate: nil, hasExplicitTime: true)

        XCTAssertFalse(task.hasExplicitTime)
    }

    /// 확인 표식을 지우면 다시 붙지 않는다. 붙으면 사용자가 확인한 것이 되돌려진다.
    func testMarkingReviewedIsFinal() {
        var task = TaskDraft(title: "예약", confidence: 0.9).makeTask(now: now)
        XCTAssertTrue(task.needsReview, "날짜가 없으므로 봐야 합니다")

        task.markReviewed()

        XCTAssertFalse(task.needsReview)
        XCTAssertNil(task.reviewReason)
    }
}
