import XCTest
@testable import Whenly

final class TaskDraftTests: XCTestCase {
    func testLowConfidenceDraftNeedsDateConfirmation() {
        let draft = TaskDraft(
            title: "병원 예약",
            dueDate: Date(),
            confidence: 0.79
        )

        XCTAssertTrue(draft.needsDateConfirmation)
    }

    func testHighConfidenceDatedDraftDoesNotNeedDateConfirmation() {
        let draft = TaskDraft(
            title: "병원 예약",
            dueDate: Date(),
            confidence: 0.80
        )

        XCTAssertFalse(draft.needsDateConfirmation)
    }

    func testDraftWithoutDateNeedsDateConfirmation() {
        let draft = TaskDraft(title: "장보기", confidence: 0.95)

        XCTAssertTrue(draft.needsDateConfirmation)
    }

    func testAmbiguousDraftNeedsDateConfirmation() {
        let draft = TaskDraft(
            title: "예약 확인",
            dueDate: Date(),
            confidence: 0.95,
            ambiguities: ["오전인지 오후인지 불명확"]
        )

        XCTAssertTrue(draft.needsDateConfirmation)
    }

    func testDraftCreatesScreenshotTaskWhenCaptureIDExists() {
        let captureID = UUID()
        let draft = TaskDraft(
            title: "서류 제출",
            confidence: 0.9,
            sourceCaptureID: captureID
        )

        XCTAssertEqual(draft.makeTask().origin, .screenshot)
        XCTAssertEqual(draft.makeTask().sourceCaptureID, captureID)
    }

    func testTaskCannotHaveExplicitTimeWithoutDate() {
        let task = AssistantTask(
            title: "날짜 없는 일",
            dueDate: nil,
            hasExplicitTime: true
        )

        XCTAssertFalse(task.hasExplicitTime)
    }
}
