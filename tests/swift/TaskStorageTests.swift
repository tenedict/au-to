import XCTest
@testable import Whenly

/// 저장·복원 계약.
///
/// 이 계층이 조용히 실패하면 사용자는 **잃은 뒤에** 안다. 그래서 실패를 던지는지,
/// 못 읽은 파일을 지우지 않고 격리하는지, 예전 파일이 계속 열리는지를 여기서 잡는다.
final class TaskStorageTests: XCTestCase {

    private var directory: URL!
    private var storage: TaskStorage!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhenlyTests-\(UUID().uuidString)")
        storage = TaskStorage(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: - 왕복

    func testFirstRunReturnsEmptyListsWithoutThrowing() throws {
        XCTAssertTrue(try storage.loadTasks().isEmpty)
        XCTAssertTrue(try storage.loadDrafts().isEmpty)
    }

    func testTasksSurviveSaveAndLoad() throws {
        let task = AssistantTask(
            title: "치과 예약",
            notes: "강남점",
            dueDate: Date(timeIntervalSince1970: 1_786_000_000),
            hasExplicitTime: true,
            confidence: 0.91,
            remindersEnabled: false,
            createdAt: Date(timeIntervalSince1970: 1_785_000_000)
        )

        try storage.saveTasks([task])

        let loaded = try storage.loadTasks()
        XCTAssertEqual(loaded, [task])
        XCTAssertEqual(loaded.first?.wantsReminders, false)
    }

    /// 저장 형식은 ISO 8601 문자열이라 **밀리초까지** 남는다.
    ///
    /// 이 정밀도를 적어 두는 이유는, 초 단위로 잘리면 같은 초에 만든 두 할 일의 순서가
    /// 재실행 뒤에 뒤집히기 때문이다. 사람이 파일을 열어 볼 수 있는 쪽이 더 중요해서
    /// 숫자 대신 문자열을 쓰고, 대신 소수점을 반드시 적는다.
    func testDatesKeepMillisecondPrecision() throws {
        let precise = Date(timeIntervalSince1970: 1_786_000_000.123)
        let task = AssistantTask(title: "정밀도", createdAt: precise)

        try storage.saveTasks([task])

        let loaded = try XCTUnwrap(try storage.loadTasks().first)
        XCTAssertEqual(
            loaded.createdAt.timeIntervalSince1970,
            precise.timeIntervalSince1970,
            accuracy: 0.001
        )

        let raw = try String(contentsOf: directory.appendingPathComponent("tasks.json"), encoding: .utf8)
        XCTAssertTrue(raw.contains(".123"), "소수점이 파일에 남아야 합니다: \(raw)")
    }

    /// 확인하지 않은 초안이 재실행 뒤에도 남아야 한다.
    /// 남지 않으면 같은 캡처를 다시 OCR 하고 OpenAI 를 다시 부른다.
    func testDraftsSurviveSaveAndLoad() throws {
        let draft = TaskDraft(
            title: "서류 제출",
            notes: "8월 5일까지",
            confidence: 0.6,
            ambiguities: ["연도가 없음"],
            sourceCaptureID: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_785_000_000)
        )

        try storage.saveDrafts([draft])

        XCTAssertEqual(try storage.loadDrafts(), [draft])
    }

    // MARK: - 버전 이동

    /// 새 필드는 반드시 옵셔널이다. 기본값이 있어도 예전 파일은 `keyNotFound` 로
    /// 열리지 않고, 그러면 사용자는 할 일을 **통째로** 잃는다.
    func testDecodesTaskSavedBeforeRemindersFieldExisted() throws {
        let legacy = """
        [{
          "id": "\(UUID().uuidString)",
          "title": "예전 할 일",
          "notes": "",
          "hasExplicitTime": false,
          "state": "pending",
          "origin": "manual",
          "confidence": 1,
          "createdAt": "2026-07-01T09:00:00Z"
        }]
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(legacy.utf8).write(to: directory.appendingPathComponent("tasks.json"))

        let loaded = try storage.loadTasks()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "예전 할 일")
        // 필드가 없으면 알림을 켠 것으로 본다.
        XCTAssertTrue(loaded.first?.wantsReminders ?? false)
    }

    /// R0 초기 빌드는 날짜를 숫자로 저장했다. 읽기는 두 형식을 모두 받는다.
    func testDecodesLegacyNumericDates() throws {
        let legacy = """
        [{
          "id": "\(UUID().uuidString)",
          "title": "숫자 날짜",
          "notes": "",
          "hasExplicitTime": false,
          "state": "pending",
          "origin": "manual",
          "confidence": 1,
          "createdAt": 776000000.0
        }]
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(legacy.utf8).write(to: directory.appendingPathComponent("tasks.json"))

        let loaded = try storage.loadTasks()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(
            loaded.first?.createdAt,
            Date(timeIntervalSinceReferenceDate: 776_000_000)
        )
    }

    // MARK: - 손상

    /// 못 읽은 파일을 조용히 빈 목록으로 바꾸면 사용자는 할 일이 사라진 줄 안다.
    /// 지우지도 않는다 — 사용자의 데이터이므로 옆으로 치우고 알린다.
    func testCorruptFileIsQuarantinedAndReported() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("tasks.json")
        try Data("{ 이건 JSON이 아니다".utf8).write(to: url)

        XCTAssertThrowsError(try storage.loadTasks()) { error in
            guard case TaskStorageError.quarantined = error else {
                return XCTFail("격리 오류가 나와야 합니다: \(error)")
            }
            XCTAssertNotNil(error.localizedDescription)
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: url.path),
            "손상 파일은 원래 자리에서 치워져야 합니다"
        )
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(
            leftovers.contains { $0.contains("corrupt-") },
            "원본은 지우지 않고 남겨야 합니다: \(leftovers)"
        )
    }

    /// 격리 후에는 다시 빈 상태로 시작할 수 있어야 한다. 계속 던지면 앱을 못 쓴다.
    func testLoadRecoversAfterQuarantine() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("깨짐".utf8).write(to: directory.appendingPathComponent("tasks.json"))

        XCTAssertThrowsError(try storage.loadTasks())
        XCTAssertTrue(try storage.loadTasks().isEmpty)
    }
}

// MARK: - 저장 위치 옮기기

extension TaskStorageTests {
    /// 저장 위치를 App Group 으로 옮기면서 이걸 하지 않으면
    /// **사용자의 할 일이 통째로 사라진 것처럼 보인다.**
    func testAdoptsTasksLeftInTheLegacyLocation() throws {
        let legacyBase = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        )
        let legacy = legacyBase.appendingPathComponent(TaskStorage.defaultDirectoryName)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let legacyTasks = legacy.appendingPathComponent("tasks.json")
        let hadLegacy = FileManager.default.fileExists(atPath: legacyTasks.path)
        let backup = hadLegacy ? try Data(contentsOf: legacyTasks) : nil
        defer {
            try? FileManager.default.removeItem(at: legacyTasks)
            if let backup { try? backup.write(to: legacyTasks) }
        }

        let task = AssistantTask(title: "예전 위치의 할 일", createdAt: Date(timeIntervalSince1970: 1))
        try TaskStorage(directory: legacy).saveTasks([task])

        try storage.adoptLegacyStoreIfNeeded()

        XCTAssertEqual(try storage.loadTasks().map(\.title), ["예전 위치의 할 일"])
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacyTasks.path),
            "옮겼으면 예전 자리에는 남지 않아야 합니다"
        )
    }

    /// 새 자리에 이미 있으면 건드리지 않는다. 옮기다 덮어쓰는 것이 더 나쁘다.
    func testDoesNotOverwriteAnExistingStore() throws {
        let current = AssistantTask(title: "지금 것", createdAt: Date(timeIntervalSince1970: 2))
        try storage.saveTasks([current])

        try storage.adoptLegacyStoreIfNeeded()

        XCTAssertEqual(try storage.loadTasks().map(\.title), ["지금 것"])
    }

    // MARK: - 쓸 수 있는 자리 고르기

    /// `containerURL(forSecurityApplicationGroupIdentifier:)` 은 **권한이 없어도 경로를 돌려준다.**
    ///
    /// 그 경로를 그대로 쓰면 `fileExists` 가 언제나 false 라 앱이 매번 "첫 실행" 처럼
    /// 보인다. 사용자에게는 할 일이 통째로 사라진 것이다 — 실제로 macOS 앱이
    /// 이 상태였다. 자리를 고를 때 **만들어 보고** 정해야 한다.
    func testUnusableDirectoryIsRejectedBeforeItIsChosen() {
        // /dev/null 은 디렉터리가 아니므로 그 아래는 어떤 권한으로도 만들 수 없다.
        // 권한에 기대는 검사는 root 로 돌리면 통과해 버린다.
        let impossible = URL(fileURLWithPath: "/dev/null/Whenly")

        XCTAssertFalse(TaskStorage.isUsable(impossible))
    }

    func testWritableDirectoryIsAccepted() {
        XCTAssertTrue(TaskStorage.isUsable(directory))
    }

    /// 고른 자리는 실제로 쓸 수 있어야 한다. 못 쓰는 자리를 골라 놓고
    /// 조용히 빈 목록을 돌려주는 것이 이 버그의 모양이었다.
    func testDefaultStorageChoosesAPlaceItCanActuallyWrite() throws {
        let resolved = try TaskStorage.makeDefault()

        XCTAssertTrue(
            TaskStorage.isUsable(resolved.directory),
            "기본 저장 위치(\(resolved.directory.path))를 만들지 못했습니다"
        )
    }
}
