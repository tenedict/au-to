import Foundation

/// 잇달아 들어온 캡처를 얼마나 빨리 읽을 것인가.
///
/// 분석 한 번은 백엔드를 거쳐 OpenAI 를 부른다. 스크린샷 폴더를 통째로 끌어다
/// 놓으면 순식간에 수십 번이 나가고, 요금과 레이트리밋이 함께 터진다.
/// 그래서 **1분에 열 개**를 넘기지 않는다.
///
/// 다만 "6초에 하나" 처럼 간격을 고르게 벌리지는 않는다. 두세 장을 잇달아 끌어다
/// 놓는 것은 이 제품의 **정상 사용**이고, 그때 두 번째 장이 6초 뒤에야 시작하면
/// 사용자는 고장으로 읽는다. 그래서 창(60초) 안의 **개수만** 본다 —
/// 앞의 열 개는 곧바로 나가고, 문턱을 넘은 뒤에만 기다림이 생긴다.
///
/// 순수 값이라 시계를 인자로 받는다. 안에서 `.now` 를 읽으면 테스트가 실제 시간에
/// 따라 흔들린다 (CLAUDE 규칙 10).
struct IntakeRate: Equatable, Sendable {

    /// 창 하나에서 시작할 수 있는 최대 개수.
    static let maxPerWindow = 10
    /// 창의 길이.
    static let window: TimeInterval = 60

    /// 창 안에서 이미 시작한 시각들. 오래된 것이 앞이다.
    private var started: [Date] = []

    init() {}

    /// 지금 시작해도 되는지. 안 되면 얼마나 기다려야 하는지.
    ///
    /// - Returns: 0 이면 곧바로 시작해도 된다.
    func delay(at now: Date) -> TimeInterval {
        let live = Self.live(started, at: now)
        guard live.count >= Self.maxPerWindow, let oldest = live.first else { return 0 }
        // 가장 오래된 것이 창 밖으로 나가는 순간 자리가 하나 생긴다.
        return max(0, oldest.addingTimeInterval(Self.window).timeIntervalSince(now))
    }

    /// 하나를 시작했다고 적어 둔다.
    mutating func record(at now: Date) {
        started = Self.live(started, at: now)
        started.append(now)
    }

    /// 창 안에 남아 있는 것만.
    private static func live(_ dates: [Date], at now: Date) -> [Date] {
        dates.filter { now.timeIntervalSince($0) < window }
    }
}
