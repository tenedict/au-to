import XCTest
@testable import Whenly

/// 저장소가 실제로 유스케이스를 지키는지 확인한다.
///
/// 화면에서 눌러 보는 것으로는 "알림이 취소됐는가" 를 알 수 없다. 계약은 여기서 잡는다.
@MainActor
final class TaskStoreTests: XCTestCase {

    private var directory: URL!
    private var storage: TaskStorage!
    private var scheduler: RecordingReminderScheduler!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhenlyStoreTests-\(UUID().uuidString)")
        storage = TaskStorage(directory: directory)
        scheduler = RecordingReminderScheduler()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private let calendar = RecordingCalendarService()

    private func makeStore(
        understanding: any ContextUnderstandingService = StubUnderstandingService(),
        now: Date = Date(timeIntervalSince1970: 1_785_909_600)
    ) -> TaskStore {
        TaskStore(
            ocrService: StubOCRService(),
            understandingService: understanding,
            reminderScheduler: scheduler,
            calendarService: calendar,
            storage: storage,
            now: { now }
        )
    }

    // MARK: - 분석 → 등록 (막지 않는다)

    /// 붙여 넣은 텍스트도 **곧바로 할 일이 된다.**
    ///
    /// 예전에는 초안으로 남겨 두고 사용자가 확인 화면을 지나야 했다. 그러면
    /// 확인하지 않은 사람에게는 아무 일도 일어나지 않고, 그게 이 제품이 없애려던
    /// 상태였다 (ADR-4 개정).
    /// **캘린더는 주입받는다.** 저장소가 EventKit 을 직접 만들면 이 테스트가
    /// 시뮬레이터에서 권한 요청에 걸려 몇 분씩 멈춘다 — 실제로 스위트가 583초 걸렸다.
    func testCalendarIsInjectedSoTestsNeverTouchEventKit() async throws {
        let store = makeStore()

        await store.analyzeManualText("8월 10일 서류 제출")

        XCTAssertEqual(calendar.added.count, 1, "분명한 일정은 캘린더에도 들어가야 합니다")
    }

    /// 확인이 필요한 것은 **캘린더에 넣지 않는다.** 할 일은 우리 원장이라 되돌리기
    /// 쉽지만, 캘린더는 밖으로 나가는 출력이라 잘못 들어간 일정의 무게가 다르다.
    func testAmbiguousResultDoesNotReachTheCalendar() async {
        let store = makeStore(understanding: AmbiguousUnderstandingService())

        await store.analyzeManualText("언젠가 서류 제출")

        XCTAssertEqual(store.tasks.count, 1, "등록은 되어야 합니다")
        XCTAssertTrue(calendar.added.isEmpty, "확인 전에는 캘린더에 넣지 않습니다")
    }

    func testAnalysisRegistersImmediately() async throws {
        let store = makeStore()

        await store.analyzeManualText("8월 10일 서류 제출")

        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(try storage.loadTasks().count, 1, "할 일은 디스크에도 남아야 합니다")
    }

    /// **애매해도 등록한다.** 다만 봐야 할 이유를 붙인다.
    ///
    /// 날짜를 못 찾은 것을 막아 두면 사용자는 놓기가 먹히지 않은 것으로 읽고,
    /// 같은 스크린샷을 몇 번이고 다시 담는다.
    func testAmbiguousResultIsStillRegisteredButFlagged() async throws {
        let store = makeStore(understanding: AmbiguousUnderstandingService())

        await store.analyzeManualText("언젠가 서류 제출")

        let task = try XCTUnwrap(store.tasks.first)
        XCTAssertTrue(task.needsReview, "애매한 것도 등록하되 표식이 남아야 합니다")
        XCTAssertNotNil(task.reviewReason, "왜 봐야 하는지 없으면 사용자가 할 일이 없습니다")
    }

    /// 사용자가 "확인함" 을 누르면 표식만 사라지고 할 일은 그대로 남는다.
    func testMarkingReviewedClearsTheFlagButKeepsTheTask() async throws {
        let store = makeStore(understanding: AmbiguousUnderstandingService())
        await store.analyzeManualText("언젠가 서류 제출")
        let task = try XCTUnwrap(store.tasks.first)

        await store.markReviewed(task.id)

        XCTAssertFalse(try XCTUnwrap(store.tasks.first).needsReview)
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertFalse(try XCTUnwrap(storage.loadTasks().first).needsReview, "디스크에도 남아야 합니다")
    }

    /// 고쳐서 저장하면 확인한 것으로 본다. 값을 보고 저장을 눌렀기 때문이다.
    func testEditingClearsTheReviewFlag() async throws {
        let store = makeStore(understanding: AmbiguousUnderstandingService())
        await store.analyzeManualText("언젠가 서류 제출")
        let task = try XCTUnwrap(store.tasks.first)
        var edit = TaskEdit(task: task, now: Date(timeIntervalSince1970: 1_785_909_600))
        edit.title = "서류 제출"

        await store.commit(edit, to: task)

        XCTAssertFalse(try XCTUnwrap(store.tasks.first).needsReview)
        XCTAssertEqual(store.tasks.first?.title, "서류 제출")
    }

    func testAnalysisFailureRegistersNothingAndReportsError() async {
        let store = makeStore(understanding: FailingUnderstandingService())

        await store.analyzeManualText("무엇이든")

        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertNotNil(store.lastErrorMessage, "실패를 삼키면 안 됩니다")
    }

    // MARK: - 알림

    func testSavingDatedTaskSchedulesReminders() async {
        let store = makeStore()
        let task = AssistantTask(
            title: "치과",
            dueDate: Date(timeIntervalSince1970: 1_786_600_000),
            hasExplicitTime: true
        )

        await store.save(task)

        XCTAssertEqual(scheduler.scheduled[task.id]?.isEmpty, false)
    }

    /// 끝낸 일로 다시 울리면 사용자는 알림 전체를 꺼 버린다.
    func testCompletingTaskClearsItsReminders() async {
        let store = makeStore()
        let task = AssistantTask(
            title: "치과",
            dueDate: Date(timeIntervalSince1970: 1_786_600_000),
            hasExplicitTime: true
        )
        await store.save(task)

        await store.toggleCompletion(for: task.id)

        XCTAssertEqual(scheduler.scheduled[task.id]?.isEmpty, true)
    }

    func testUncompletingTaskBringsRemindersBack() async {
        let store = makeStore()
        let task = AssistantTask(
            title: "치과",
            dueDate: Date(timeIntervalSince1970: 1_786_600_000),
            hasExplicitTime: true
        )
        await store.save(task)
        await store.toggleCompletion(for: task.id)

        await store.toggleCompletion(for: task.id)

        XCTAssertEqual(scheduler.scheduled[task.id]?.isEmpty, false)
    }

    func testDeletingTaskCancelsItsReminders() async {
        let store = makeStore()
        let task = AssistantTask(
            title: "치과",
            dueDate: Date(timeIntervalSince1970: 1_786_600_000),
            hasExplicitTime: true
        )
        await store.save(task)

        await store.delete(task.id)

        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertNil(scheduler.scheduled[task.id])
        XCTAssertTrue(scheduler.cancelled.contains(task.id))
    }

    func testTaskWithoutDateSchedulesNothing() async {
        let store = makeStore()
        let task = AssistantTask(title: "언젠가 정리하기", dueDate: nil)

        await store.save(task)

        XCTAssertEqual(scheduler.scheduled[task.id]?.isEmpty, true)
    }

    // MARK: - 파생 값

    /// 파생 값은 저장하지 않는다. 저장하면 반드시 한쪽이 뒤처진다.
    func testDueGroupsFollowTheStoreState() async {
        let now = Date(timeIntervalSince1970: 1_785_909_600)
        let store = makeStore(now: now)
        await store.save(
            AssistantTask(title: "지난 일", dueDate: now.addingTimeInterval(-86_400 * 2))
        )
        await store.save(
            AssistantTask(title: "나중 일", dueDate: now.addingTimeInterval(86_400 * 30))
        )

        XCTAssertEqual(store.dueGroups(asOf: now).map(\.bucket), [.overdue, .later])
    }

    func testSavingSameTaskTwiceUpdatesInsteadOfDuplicating() async {
        let store = makeStore()
        var task = AssistantTask(title: "처음 제목", dueDate: nil)
        await store.save(task)

        task.title = "고친 제목"
        await store.save(task)

        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks.first?.title, "고친 제목")
    }

    // MARK: - 시작

    func testStoreReloadsPersistedStateOnLaunch() async throws {
        let first = makeStore()
        await first.save(AssistantTask(title: "남아 있어야 함", dueDate: nil))

        let second = makeStore()

        XCTAssertEqual(second.tasks.map(\.title), ["남아 있어야 함"])
    }

    /// 손상된 파일을 만나면 빈 목록으로 시작하되 그 사실을 말한다.
    func testCorruptStoreFileIsReportedOnLaunch() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("깨짐".utf8).write(to: directory.appendingPathComponent("tasks.json"))

        let store = makeStore()

        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertNotNil(store.lastErrorMessage)
    }
}

// MARK: - 대역

private struct StubOCRService: OCRService {
    func recognizeText(in imageData: Data) async throws -> String { "인식된 텍스트" }
}

private struct StubUnderstandingService: ContextUnderstandingService {
    func makeDrafts(from text: String, captureID: UUID?) async throws -> [TaskDraft] {
        [TaskDraft(
            title: String(text.prefix(40)),
            notes: text,
            dueDate: Date(timeIntervalSince1970: 1_786_600_000),
            hasExplicitTime: true,
            confidence: 0.9,
            sourceCaptureID: captureID
        )]
    }
}

/// 날짜를 못 찾은 결과. **등록은 되어야 하고 표식이 남아야 한다.**
private struct AmbiguousUnderstandingService: ContextUnderstandingService {
    func makeDrafts(from text: String, captureID: UUID?) async throws -> [TaskDraft] {
        [TaskDraft(
            title: String(text.prefix(40)),
            notes: text,
            dueDate: nil,
            confidence: 0.9,
            sourceCaptureID: captureID
        )]
    }
}

private struct FailingUnderstandingService: ContextUnderstandingService {
    func makeDrafts(from text: String, captureID: UUID?) async throws -> [TaskDraft] {
        throw ContextUnderstandingError.noTextFound
    }
}
