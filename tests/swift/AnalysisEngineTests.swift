import XCTest
@testable import Whenly

/// 분석 엔진 선택 계약.
///
/// 엔진을 고르는 지점이 한 곳이어야 나중에 온디바이스로 옮길 때 화면·저장소·테스트를
/// 건드리지 않는다 (ADR-3). 여기서는 그 한 곳이 실제로 지켜지는지 본다.
@MainActor
final class AnalysisEngineTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "AnalysisEngineTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func makeStore() -> TaskStore {
        TaskStore(
            ocrService: StubOCR(),
            reminderScheduler: RecordingReminderScheduler(),
            storage: TaskStorage(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("AnalysisEngineTests-\(UUID().uuidString)")
            ),
            defaults: defaults
        )
    }

    // MARK: - 고를 수 있는 것

    /// 온디바이스는 기기 사정에 달려 있다. 나머지는 언제나 쓸 수 있다.
    func testOnlyOnDeviceDependsOnTheDevice() {
        XCTAssertFalse(AnalysisEngine.onDevice.alwaysAvailable)
        XCTAssertTrue(AnalysisEngine.backend.alwaysAvailable)
        XCTAssertTrue(AnalysisEngine.ruleBased.alwaysAvailable)
    }

    /// 고를 수 있는 엔진에는 "왜 못 고르는지" 가 붙으면 안 된다.
    /// 붙어 있으면 화면이 이유를 띄운 채로 선택은 되는 모순이 생긴다.
    func testAvailableEnginesHaveNoUnavailableReason() {
        for engine in AnalysisEngine.allCases
        where ContextUnderstanding.isAvailable(engine) {
            XCTAssertNil(ContextUnderstanding.unavailableReason(for: engine), "\(engine)")
        }
    }

    func testEveryEngineExplainsItself() {
        for engine in AnalysisEngine.allCases {
            XCTAssertFalse(engine.title.isEmpty, "\(engine)")
            XCTAssertFalse(engine.detail.isEmpty, "\(engine)")
            XCTAssertFalse(engine.symbolName.isEmpty, "\(engine)")
        }
    }

    /// 규칙 기반은 문맥을 모른다. 신뢰도 임계값과 **별개로** 엔진 수준에서 막는다 —
    /// 임계값 하나에만 기대면 나중에 그 값을 올리는 순간 규칙 기반 결과가 통과한다.
    func testOnlyBackendMayEverPrefillCalendar() {
        XCTAssertTrue(AnalysisEngine.backend.mayEverPrefillCalendar)
        XCTAssertFalse(AnalysisEngine.ruleBased.mayEverPrefillCalendar)
    }

    // MARK: - 기억

    func testEngineChoiceSurvivesRelaunch() {
        let first = makeStore()
        first.engine = .ruleBased

        let second = makeStore()

        XCTAssertEqual(second.engine, .ruleBased)
    }

    func testDefaultEngineIsBackend() {
        XCTAssertEqual(makeStore().engine, .backend)
    }

    /// 못 고르는 엔진으로 바꾸려 하면 원래 값이 남아야 한다.
    /// 바뀐 척하고 분석기는 그대로면 사용자는 온디바이스로 돌고 있다고 믿는다.
    func testSelectingAnUnavailableEngineIsRejected() throws {
        // 이 기기에서 온디바이스를 쓸 수 있으면 이 검사는 의미가 없다.
        try XCTSkipIf(
            ContextUnderstanding.isAvailable(.onDevice),
            "이 기기는 온디바이스를 쓸 수 있어 이 검사가 성립하지 않습니다"
        )
        let store = makeStore()

        store.engine = .onDevice

        XCTAssertEqual(store.engine, .backend, "못 쓰는 엔진으로 바뀌면 안 됩니다")
    }

    /// 저장해 둔 엔진이 그 사이 못 쓰게 됐으면 기본값으로 되돌린다.
    func testStoredUnavailableEngineFallsBackToDefault() throws {
        try XCTSkipIf(
            ContextUnderstanding.isAvailable(.onDevice),
            "이 기기는 온디바이스를 쓸 수 있어 이 검사가 성립하지 않습니다"
        )
        XCTAssertEqual(
            ContextUnderstanding.defaultEngine(stored: .onDevice, environment: [:]),
            .default
        )
    }

    func testStoredAvailableEngineIsHonoured() {
        XCTAssertEqual(
            ContextUnderstanding.defaultEngine(stored: .ruleBased, environment: [:]),
            .ruleBased
        )
    }

    #if DEBUG
    /// 백엔드 없이 전체 흐름을 눌러 볼 수 있어야 한다.
    func testOfflineEnvironmentStartsWithRuleBasedEngine() {
        XCTAssertEqual(
            ContextUnderstanding.defaultEngine(
                stored: .backend,
                environment: ["WHENLY_OFFLINE": "1"]
            ),
            .ruleBased
        )
    }
    #endif

    // MARK: - 구현이 실제로 갈리는가

    func testEachEngineMakesADistinctImplementation() {
        XCTAssertTrue(ContextUnderstanding.make(.backend) is BackendContextUnderstandingService)
        XCTAssertTrue(ContextUnderstanding.make(.ruleBased) is RuleBasedContextUnderstandingService)
    }
}

private struct StubOCR: OCRService {
    func recognizeText(in imageData: Data) async throws -> String { "인식된 텍스트" }
}
