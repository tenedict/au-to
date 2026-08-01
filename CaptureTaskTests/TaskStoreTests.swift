import XCTest
@testable import CaptureTask

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
            .appendingPathComponent("CaptureTaskStoreTests-\(UUID().uuidString)")
        storage = TaskStorage(directory: directory)
        scheduler = RecordingReminderScheduler()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeStore(
        understanding: any ContextUnderstandingService = StubUnderstandingService(),
        now: Date = Date(timeIntervalSince1970: 1_785_909_600)
    ) -> TaskStore {
        TaskStore(
            ocrService: StubOCRService(),
            understandingService: understanding,
            reminderScheduler: scheduler,
            storage: storage,
            now: { now }
        )
    }

    // MARK: - 초안 → 할 일

    func testManualAnalysisAddsAndPersistsDraft() async throws {
        let store = makeStore()

        await store.analyzeManualText("8월 10일 서류 제출")

        XCTAssertEqual(store.pendingDrafts.count, 1)
        XCTAssertEqual(try storage.loadDrafts().count, 1, "초안은 디스크에도 남아야 합니다")
    }

    func testSavingDraftRemovesItFromPendingAndPersistsTask() async throws {
        let store = makeStore()
        await store.analyzeManualText("8월 10일 서류 제출")
        let draft = try XCTUnwrap(store.pendingDrafts.first)

        await store.save(draft.makeTask())

        XCTAssertTrue(store.pendingDrafts.isEmpty)
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(try storage.loadTasks().count, 1)
        XCTAssertTrue(try storage.loadDrafts().isEmpty)
    }

    /// 버린 초안은 다시 뜨지 않아야 한다. 남으면 앱을 열 때마다 같은 제안이 튀어나온다.
    func testDiscardingDraftRemovesItEverywhere() async throws {
        let store = makeStore()
        await store.analyzeManualText("광고 문자")
        let draft = try XCTUnwrap(store.pendingDrafts.first)

        store.discard(draft)

        XCTAssertTrue(store.pendingDrafts.isEmpty)
        XCTAssertTrue(try storage.loadDrafts().isEmpty)
        XCTAssertTrue(store.tasks.isEmpty, "버린 초안이 할 일이 되면 안 됩니다")
    }

    func testAnalysisFailureKeepsDraftListUntouchedAndReportsError() async {
        let store = makeStore(understanding: FailingUnderstandingService())

        await store.analyzeManualText("무엇이든")

        XCTAssertTrue(store.pendingDrafts.isEmpty)
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
        await first.analyzeManualText("확인 대기")

        let second = makeStore()

        XCTAssertEqual(second.tasks.map(\.title), ["남아 있어야 함"])
        XCTAssertEqual(second.pendingDrafts.count, 1)
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
    func makeDraft(from text: String, captureID: UUID?) async throws -> TaskDraft {
        TaskDraft(
            title: String(text.prefix(40)),
            notes: text,
            dueDate: Date(timeIntervalSince1970: 1_786_600_000),
            hasExplicitTime: true,
            confidence: 0.9,
            sourceCaptureID: captureID
        )
    }
}

private struct FailingUnderstandingService: ContextUnderstandingService {
    func makeDraft(from text: String, captureID: UUID?) async throws -> TaskDraft {
        throw ContextUnderstandingError.noTextFound
    }
}
