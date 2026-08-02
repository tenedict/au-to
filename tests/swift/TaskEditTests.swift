import XCTest

@testable import Whenly

/// 고치는 화면의 규칙.
///
/// iOS 와 macOS 가 같은 값을 쓴다. 각자 구현하면 반드시 한쪽만 고쳐지고,
/// 그러면 같은 할 일을 어느 기기에서 고쳤느냐에 따라 결과가 달라진다.
final class TaskEditTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 열 때

    /// 캘린더 토글의 초기값은 **지금 실제로 들어가 있는지**다.
    ///
    /// 임의로 켜 두면 사용자가 제목 하나 고치고 저장하는 것만으로
    /// 캘린더에 새 일정이 생긴다.
    func testCalendarToggleStartsFromWhatIsActuallyInTheCalendar() {
        let inCalendar = AssistantTask(
            title: "검진", dueDate: now, calendarEventIdentifier: "event-1")
        let notInCalendar = AssistantTask(title: "검진", dueDate: now)

        XCTAssertTrue(TaskEdit(task: inCalendar, now: now).addToCalendar)
        XCTAssertFalse(TaskEdit(task: notInCalendar, now: now).addToCalendar)
    }

    /// 확인이 필요한 초안은 캘린더를 미리 켜지 않는다 (CLAUDE 규칙 1·2).
    func testAmbiguousDraftDoesNotPrefillTheCalendar() {
        let ambiguous = TaskDraft(
            title: "예약", dueDate: now, confidence: 1, ambiguities: ["오전인지 오후인지 모르겠어요"])

        XCTAssertFalse(TaskEdit(draft: ambiguous, now: now).addToCalendar)
    }

    /// 날짜가 없는 할 일을 열면 오늘이 후보로 들어온다.
    /// 1970년이 뜨면 사용자는 매번 스크롤해서 올라와야 한다.
    func testUndatedTaskOpensOnTheCurrentDate() {
        let edit = TaskEdit(task: AssistantTask(title: "언젠가"), now: now)

        XCTAssertFalse(edit.hasDate)
        XCTAssertEqual(edit.dueDate, now)
    }

    // MARK: - 저장할 수 있는가

    func testTitleOnlyOfSpacesCannotBeSaved() {
        var edit = TaskEdit(task: AssistantTask(title: "검진"), now: now)
        edit.title = "   \n "

        XCTAssertFalse(edit.canSave)
    }

    // MARK: - 날짜를 끄면 함께 꺼지는 것

    /// 날짜를 끄면 알림과 캘린더도 함께 꺼진다.
    ///
    /// 화면에서 토글을 비활성으로 만드는 것만으로는 부족하다 — 켜 둔 채 날짜를 끄면
    /// 값이 `true` 로 남아, 나중에 날짜를 다시 켜는 순간 사용자가 정한 적 없는
    /// 캘린더 저장이 일어난다.
    func testTurningOffTheDateTurnsOffRemindersAndCalendar() {
        var edit = TaskEdit(
            task: AssistantTask(title: "검진", dueDate: now, calendarEventIdentifier: "e"),
            now: now)
        edit.wantsReminders = true
        edit.hasDate = false

        XCTAssertFalse(edit.effectiveWantsReminders)
        XCTAssertFalse(edit.effectiveAddToCalendar)
    }

    // MARK: - 얹기

    /// 고쳐도 신원은 그대로다. `id` 가 바뀌면 같은 할 일이 목록에 두 개가 된다.
    func testEditingKeepsIdentityAndSource() {
        let captureID = UUID()
        let original = AssistantTask(
            title: "검진",
            dueDate: now,
            origin: .screenshot,
            confidence: 0.91,
            sourceCaptureID: captureID,
            calendarEventIdentifier: "event-1")

        var edit = TaskEdit(task: original, now: now)
        edit.title = "치과 검진"
        let updated = edit.apply(to: original)

        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.sourceCaptureID, captureID)
        XCTAssertEqual(updated.origin, .screenshot)
        XCTAssertEqual(updated.calendarEventIdentifier, "event-1")
        XCTAssertEqual(updated.title, "치과 검진")
    }

    /// 완료 상태는 고치는 화면이 건드리지 않는다.
    /// 여기서 되살리면 목록에서 체크한 것이 조용히 풀린다.
    func testEditingDoesNotChangeCompletion() {
        let done = AssistantTask(title: "검진", dueDate: now, state: .completed)
        var edit = TaskEdit(task: done, now: now)
        edit.notes = "메모"

        XCTAssertTrue(edit.apply(to: done).isCompleted)
    }

    /// 날짜를 끄면 시간 지정도 함께 사라진다.
    /// 남아 있으면 `AssistantTask` 안에서 "날짜는 없는데 시간은 있다" 가 된다.
    func testClearingTheDateClearsTheExplicitTime() {
        var edit = TaskEdit(
            task: AssistantTask(title: "회의", dueDate: now, hasExplicitTime: true), now: now)
        edit.hasDate = false
        let updated = edit.apply(to: AssistantTask(title: "회의", dueDate: now, hasExplicitTime: true))

        XCTAssertNil(updated.dueDate)
        XCTAssertFalse(updated.hasExplicitTime)
    }

    /// 초안을 할 일로 만들 때 초안의 신원을 물려받는다.
    ///
    /// 새 `id` 를 만들면 상자에 담긴 캡처와 이어지지 않아 원본이 영영 남는다.
    func testDraftKeepsItsIdentityWhenSaved() {
        let captureID = UUID()
        let draft = TaskDraft(
            title: "재방문", dueDate: now, confidence: 0.95, sourceCaptureID: captureID)
        let task = TaskEdit(draft: draft, now: now).makeTask(from: draft)

        XCTAssertEqual(task.id, draft.id)
        XCTAssertEqual(task.sourceCaptureID, captureID)
        XCTAssertEqual(task.origin, .screenshot)
    }
}
