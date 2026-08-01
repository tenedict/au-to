import XCTest
@testable import CaptureTask

/// "확인해 주세요" 알림의 식별자 계약.
///
/// 이 프로젝트에는 알림 종류가 둘이다 — 마감 알림과 확인 요청 알림.
/// 앱은 **식별자 문자열만 보고** 둘을 가른다. 앞에 있을 때 배너를 띄울지,
/// 눌렀을 때 어디로 갈지가 전부 이 판정에 달려 있다.
final class CaptureNoticeTests: XCTestCase {

    func testCaptureNoticeIdentifierIsRecognized() {
        let captureID = UUID()
        let identifier = CaptureNotice.identifier(for: captureID)

        XCTAssertTrue(identifier.hasPrefix(CaptureNotice.identifierPrefix))
        XCTAssertTrue(identifier.contains(captureID.uuidString))
        XCTAssertTrue(CaptureNotice.isCaptureNotice(identifier))
    }

    func testUnconfirmedDraftsNoticeIsRecognized() {
        XCTAssertTrue(CaptureNotice.isCaptureNotice(CaptureNotice.unconfirmedDraftsIdentifier))
    }

    /// **마감 알림을 확인 요청으로 착각하면 마감 알림이 조용히 사라진다.**
    ///
    /// 앱이 앞에 있을 때 확인 요청은 배너를 띄우지 않는다 — 확인 화면이 이미 떠 있기 때문이다.
    /// 두 식별자가 겹치면 그 규칙이 마감 알림에도 적용돼, 앱을 켜 둔 사용자는
    /// 마감을 그대로 놓친다. 눈으로는 절대 못 잡는다.
    func testDueReminderIsNotMistakenForACaptureNotice() {
        let taskID = UUID()

        for identifier in ReminderSchedule.allIdentifiers(taskID: taskID) {
            XCTAssertFalse(
                CaptureNotice.isCaptureNotice(identifier),
                "마감 알림 \(identifier) 이 확인 요청으로 분류되면 앞에 있을 때 조용히 사라집니다"
            )
        }
    }

    /// 반대 방향도 막는다. 확인 요청이 마감 알림 식별자와 겹치면
    /// 할 일 하나를 지울 때 남의 알림까지 지운다.
    func testCaptureNoticeDoesNotCollideWithReminderIdentifiers() {
        let sharedID = UUID()
        let notice = CaptureNotice.identifier(for: sharedID)
        let reminders = Set(ReminderSchedule.allIdentifiers(taskID: sharedID))

        XCTAssertFalse(reminders.contains(notice))
    }

    func testEveryCaptureGetsItsOwnIdentifier() {
        let identifiers = (0..<50).map { _ in CaptureNotice.identifier(for: UUID()) }

        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }

    /// 곧바로 다시 울리면 잔소리가 되고, 하루 뒤면 이미 잊는다.
    func testUnconfirmedDraftDelayStaysWithinAUsefulWindow() {
        XCTAssertGreaterThanOrEqual(CaptureNotice.unconfirmedDraftDelay, 60 * 10)
        XCTAssertLessThanOrEqual(CaptureNotice.unconfirmedDraftDelay, 60 * 60 * 6)
    }
}
