import XCTest
@testable import Whenly

#if canImport(FoundationModels)
import FoundationModels
#endif

/// 온디바이스 모델의 출력을 우리 계약으로 옮기는 부분.
///
/// 모델 호출 자체는 기기 상태(Apple Intelligence 켜짐 여부)에 달려 있어 테스트에서
/// 부를 수 없다. 하지만 **모델이 뱉은 것을 어떻게 받아들이는가**는 순수 함수이고,
/// 여기가 틀리면 날짜가 통째로 어긋난다.
final class OnDeviceAnalysisTests: XCTestCase {

    /// 못 쓰면 **왜** 못 쓰는지 반드시 함께 온다.
    /// 이유 없이 비활성이면 사용자는 고장으로 읽는다 (CLAUDE 규칙 12).
    func testUnavailableAlwaysCarriesAReason() {
        let availability = OnDeviceContextUnderstandingService.availability

        if availability.isAvailable {
            XCTAssertNil(availability.reason)
        } else {
            let reason = availability.reason
            XCTAssertNotNil(reason)
            XCTAssertFalse(reason!.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    /// 엔진 가용성 판정이 서비스 쪽에 있어야 한다.
    /// 모델이 서비스를 알면 의존이 거꾸로 서고, 계산을 테스트하려고 프레임워크가 필요해진다.
    func testEngineAvailabilityIsDecidedByTheServiceLayer() {
        XCTAssertTrue(ContextUnderstanding.isAvailable(.backend))
        XCTAssertTrue(ContextUnderstanding.isAvailable(.ruleBased))
        XCTAssertNil(ContextUnderstanding.unavailableReason(for: .backend))

        // 온디바이스는 기기에 물어본 결과다. 어느 쪽이든 앞뒤가 맞아야 한다.
        let reason = ContextUnderstanding.unavailableReason(for: .onDevice)
        XCTAssertEqual(ContextUnderstanding.isAvailable(.onDevice), reason == nil)
    }

    /// 저장해 둔 엔진이 그 사이 못 쓰게 됐으면 기본값으로 되돌린다.
    /// 다른 기기에서 열었거나 Apple Intelligence 를 껐을 때다.
    func testStoredOnDeviceFallsBackWhenTheDeviceCannotRunIt() {
        let resolved = ContextUnderstanding.defaultEngine(stored: .onDevice, environment: [:])

        if ContextUnderstanding.isAvailable(.onDevice) {
            XCTAssertEqual(resolved, .onDevice)
        } else {
            XCTAssertEqual(resolved, .default)
        }
    }

    func testOnDeviceIsNotAlwaysAvailable() {
        XCTAssertFalse(AnalysisEngine.onDevice.alwaysAvailable)
        XCTAssertTrue(AnalysisEngine.backend.alwaysAvailable)
        XCTAssertTrue(AnalysisEngine.ruleBased.alwaysAvailable)
    }

    // MARK: - 모델 출력 받아들이기

    #if canImport(FoundationModels)

    @available(iOS 26.0, macOS 26.0, *)
    private func task(
        title: String = "치과 예약",
        dueDate: String = "2026-08-12T15:00:00+09:00",
        hasExplicitTime: Bool = true,
        confidence: Double = 0.9
    ) -> OnDeviceTask {
        OnDeviceTask(
            title: title,
            notes: "",
            dueDate: dueDate,
            hasExplicitTime: hasExplicitTime,
            confidence: confidence,
            evidence: [],
            ambiguities: []
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    func testParsesIsoDateWithOffset() throws {
        let draft = try XCTUnwrap(task().makeDraft(captureID: nil))

        XCTAssertEqual(
            draft.dueDate,
            ISO8601DateFormatter().date(from: "2026-08-12T15:00:00+09:00")
        )
        XCTAssertTrue(draft.hasExplicitTime)
    }

    /// 작은 모델은 오프셋을 자주 빠뜨린다. 그때 날짜를 통째로 버리면
    /// 사용자는 "왜 날짜를 못 읽지" 만 보게 된다.
    @available(iOS 26.0, macOS 26.0, *)
    func testAcceptsDatesWithoutAnOffset() throws {
        for raw in ["2026-08-12T15:00:00", "2026-08-12 15:00:00", "2026-08-12"] {
            let draft = try XCTUnwrap(task(dueDate: raw).makeDraft(captureID: nil), raw)
            XCTAssertNotNil(draft.dueDate, raw)
        }
    }

    /// 옵셔널 대신 빈 문자열을 쓴다 — 작은 모델은 null 을 자주 틀린다.
    @available(iOS 26.0, macOS 26.0, *)
    func testEmptyDateMeansNoDate() throws {
        let draft = try XCTUnwrap(task(dueDate: "  ").makeDraft(captureID: nil))

        XCTAssertNil(draft.dueDate)
        // 날짜 없이 시간만 명시된 것은 앱이 표현할 수 없다.
        XCTAssertFalse(draft.hasExplicitTime)
    }

    @available(iOS 26.0, macOS 26.0, *)
    func testGarbageDateBecomesNoDateInsteadOfCrashing() throws {
        let draft = try XCTUnwrap(task(dueDate: "다음 주 화요일").makeDraft(captureID: nil))

        XCTAssertNil(draft.dueDate)
    }

    /// 제목이 없으면 할 일이 아니다. 버리되 나머지는 살린다.
    @available(iOS 26.0, macOS 26.0, *)
    func testEmptyTitleIsDropped() {
        XCTAssertNil(task(title: "   ").makeDraft(captureID: nil))
    }

    /// 모델이 범위를 벗어난 신뢰도를 줄 수 있다. 그대로 두면 계약이 깨진다.
    @available(iOS 26.0, macOS 26.0, *)
    func testConfidenceIsClampedIntoRange() throws {
        let high = try XCTUnwrap(task(confidence: 4.2).makeDraft(captureID: nil))
        let low = try XCTUnwrap(task(confidence: -1).makeDraft(captureID: nil))

        XCTAssertEqual(high.confidence, 1)
        XCTAssertEqual(low.confidence, 0)
    }

    @available(iOS 26.0, macOS 26.0, *)
    func testKeepsTheSourceCapture() throws {
        let captureID = UUID()
        let draft = try XCTUnwrap(task().makeDraft(captureID: captureID))

        XCTAssertEqual(draft.sourceCaptureID, captureID)
    }

    #endif
}
