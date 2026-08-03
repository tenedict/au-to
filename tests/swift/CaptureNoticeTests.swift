import XCTest
@testable import Whenly

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

    /// 등록 알림도 같은 접두사를 쓴다. 접두사만 보고 종류를 단정하면 안 된다 —
    /// 실제로 그래서 "등록했어요" 를 눌러도 아무 데도 안 갔다.
    func testFiledNoticeSharesThePrefix() {
        XCTAssertTrue(CaptureNotice.isCaptureNotice("\(CaptureNotice.identifierPrefix)filed-x"))
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

    /// 알림 본문에 나열하는 개수는 손에 잡히는 범위여야 한다.
    /// 열 줄짜리 알림은 잠금화면에서 잘리고, 잘린 줄은 없는 것과 같다.
    func testBodyListStaysShort() {
        XCTAssertGreaterThanOrEqual(CaptureNotice.maxSummariesInBody, 2)
        XCTAssertLessThanOrEqual(CaptureNotice.maxSummariesInBody, 5)
    }
}
