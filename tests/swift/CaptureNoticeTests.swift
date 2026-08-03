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

/// 등록 알림에 무엇이 들어가는가.
///
/// **누르면 그 일정이 열려야 한다.** 그러려면 `taskID` 가 실려야 하는데, 알림
/// 객체는 테스트에서 눌러 볼 수 없다 — `UNNotificationResponse` 를 만들 방법이 없다.
/// 그래서 내용을 만드는 순수 함수를 따로 두고 여기서 계약을 지킨다.
final class FiledNoticeTests: XCTestCase {

    private func filed(
        title: String = "치과 검진",
        needsReview: Bool = false
    ) -> FiledCapture {
        FiledCapture(
            id: UUID(),
            title: title,
            dueDate: Date(timeIntervalSince1970: 1_786_000_000),
            hasExplicitTime: true,
            calendarEventIdentifier: nil,
            reviewReason: needsReview ? "오전인지 오후인지 모르겠어요" : nil,
            filedAt: .now)
    }

    /// **이 파일에서 가장 중요한 테스트.**
    /// 없으면 앱은 열리지만 목록 맨 위에 서 있고, 사용자는 "눌러도 안 들어가진다" 고 말한다.
    func testNoticeAlwaysCarriesTheTaskToOpen() throws {
        let one = filed()
        let notice = try XCTUnwrap(CaptureNotice.filedNotice([one], captureID: nil))

        XCTAssertEqual(notice.taskID, one.id)
    }

    /// 봐야 할 것이 있으면 **그것을** 연다. 멀쩡한 것을 열면 사용자가 다시 찾아야 한다.
    func testNoticeOpensTheOneThatNeedsReviewFirst() throws {
        let fine = filed(title: "괜찮은 것")
        let flagged = filed(title: "봐야 하는 것", needsReview: true)
        let notice = try XCTUnwrap(
            CaptureNotice.filedNotice([fine, flagged], captureID: nil))

        XCTAssertEqual(notice.taskID, flagged.id)
    }

    /// 등록됐다는 사실이 먼저다. 확인 요청만 있으면 사용자는 등록이 안 된 줄 알고
    /// 같은 스크린샷을 다시 담는다.
    func testNoticeSaysItWasRegisteredEvenWhenReviewIsNeeded() throws {
        let notice = try XCTUnwrap(
            CaptureNotice.filedNotice([filed(needsReview: true)], captureID: nil))

        XCTAssertTrue(notice.title.contains("등록"), notice.title)
        XCTAssertTrue(notice.body.contains("확인"), notice.body)
    }

    /// 문구에 **언제와 무엇**이 다 들어가야 한다. 없으면 앱을 열어 확인해야 하고,
    /// 그러면 단계를 줄인 의미가 없다.
    func testBodyCarriesWhatAndWhen() throws {
        let notice = try XCTUnwrap(CaptureNotice.filedNotice([filed()], captureID: nil))

        XCTAssertTrue(notice.body.contains("치과 검진"), notice.body)
        XCTAssertTrue(notice.body.count > "치과 검진".count, "날짜가 빠졌습니다: \(notice.body)")
    }

    /// 마감 알림과 식별자가 겹치면 한쪽을 지울 때 다른 쪽까지 지워진다.
    func testFiledNoticeDoesNotCollideWithReminderIdentifiers() throws {
        let one = filed()
        let notice = try XCTUnwrap(CaptureNotice.filedNotice([one], captureID: nil))

        XCTAssertFalse(Set(ReminderSchedule.allIdentifiers(taskID: one.id)).contains(notice.identifier))
        XCTAssertTrue(CaptureNotice.isCaptureNotice(notice.identifier))
    }

    func testNothingFiledMeansNoNotice() {
        XCTAssertNil(CaptureNotice.filedNotice([], captureID: nil))
    }
}
