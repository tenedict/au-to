import XCTest

@testable import Whenly

/// 잇달아 들어온 캡처를 얼마나 빨리 읽는가.
///
/// 지켜야 할 것이 둘이고 서로 반대 방향이라 둘 다 테스트로 못 박는다.
///   · 1분에 열 개를 넘기지 않는다 (요금 · 레이트리밋)
///   · 잇달아 몇 개 끌어다 놓는 것은 **기다림 없이** 지나간다 (정상 사용)
final class IntakeRateTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// 처음 것은 언제나 곧바로 간다.
    func testFirstOneStartsImmediately() {
        let rate = IntakeRate()
        XCTAssertEqual(rate.delay(at: start), 0)
    }

    /// 잇달아 끌어다 놓은 앞쪽 열 개는 기다리지 않는다.
    ///
    /// 여기서 간격을 벌리면 두 번째 스크린샷이 몇 초 뒤에야 반응해서,
    /// 사용자는 놓기가 먹히지 않은 것으로 읽는다.
    func testABurstUpToTheLimitNeverWaits() {
        var rate = IntakeRate()
        for step in 0..<IntakeRate.maxPerWindow {
            let now = start.addingTimeInterval(Double(step) * 0.2)
            XCTAssertEqual(rate.delay(at: now), 0, "\(step + 1)번째가 기다립니다")
            rate.record(at: now)
        }
    }

    /// 열 개를 넘기면 그때부터 기다린다.
    func testTheEleventhWaitsForTheWindowToOpen() {
        var rate = IntakeRate()
        for step in 0..<IntakeRate.maxPerWindow {
            rate.record(at: start.addingTimeInterval(Double(step) * 0.2))
        }
        let now = start.addingTimeInterval(2)
        // 가장 오래된 것(start)이 창 밖으로 나가야 자리가 생긴다.
        XCTAssertEqual(rate.delay(at: now), IntakeRate.window - 2, accuracy: 0.001)
    }

    /// 창이 지나가면 다시 열린다. 한 번 넘었다고 영영 막히면 안 된다.
    func testTheWindowSlidesOpenAgain() {
        var rate = IntakeRate()
        for step in 0..<IntakeRate.maxPerWindow {
            rate.record(at: start.addingTimeInterval(Double(step) * 0.2))
        }
        let later = start.addingTimeInterval(IntakeRate.window + 1)
        XCTAssertEqual(rate.delay(at: later), 0)
    }

    /// 창 안의 개수만 세고, 창 밖의 것은 잊는다.
    ///
    /// 잊지 않으면 목록이 무한히 자라고, 하루 종일 켜 둔 맥에서 메모리가 샌다.
    func testOldEntriesDoNotCountAgainstTheLimit() {
        var rate = IntakeRate()
        for step in 0..<IntakeRate.maxPerWindow {
            rate.record(at: start.addingTimeInterval(Double(step) * 0.2))
        }
        // 창을 넘긴 뒤 하나만 더 넣는다. 이제 창 안에는 그 하나뿐이다.
        let later = start.addingTimeInterval(IntakeRate.window + 1)
        rate.record(at: later)
        XCTAssertEqual(rate.delay(at: later.addingTimeInterval(1)), 0)
    }

    /// 분당 한도가 실제로 1분에 열 개인가.
    ///
    /// 상수를 고칠 때 이 테스트가 함께 눈에 들어와야 한다 — 숫자를 바꾸는 것은
    /// 요금이 걸린 결정이다.
    func testTheLimitIsTenPerMinute() {
        XCTAssertEqual(IntakeRate.maxPerWindow, 10)
        XCTAssertEqual(IntakeRate.window, 60)
    }
}
