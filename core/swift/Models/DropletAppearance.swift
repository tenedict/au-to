import CoreGraphics

/// 떠 있는 물방울이 지금 무엇을 하고 있는가.
///
/// 상태는 **크기 하나로만** 말한다. 색은 쓰지 않는다 — 색만 바꾸면 흑백 화면이나
/// 색각 이상 사용자에게는 아무 일도 일어나지 않은 것과 같다 (CLAUDE 규칙 13).
enum DropletPhase: String, CaseIterable, Sendable {
    /// 쉬고 있다.
    case idle
    /// 누르고 있다.
    case pressed
    /// 위치를 옮기는 중이다.
    case moving
    /// 이미지를 끌고 왔다. 놓으면 할 일이 된다.
    ///
    /// 놓은 **직후 잠깐**도 이 상태다. 읽기는 뒤에서 도는데 물방울이 곧바로 원래
    /// 크기로 돌아가면 놓기가 먹히지 않은 것으로 보인다 — 삼킨 티가 한 번은 나야 한다.
    case receiving
}

/// 물방울의 크기 규칙.
///
/// 화면이 아니라 여기서 정하는 이유는 이 값들이 **서로 묶여 있기** 때문이다.
/// 가장 커진 물방울이 창을 넘으면 가장자리가 잘리고, 잘린 물방울은 물방울로
/// 보이지 않는다 — 예전에 그림자가 창 경계에서 직선으로 잘려 뿌연 네모로
/// 보였던 것과 같은 사고다. 그 관계를 테스트가 지킨다.
enum DropletAppearance {

    /// 창 한 변. 물방울이 가장 커졌을 때도 여백까지 여기 들어가야 한다.
    ///
    /// 창은 고정이고 물방울만 커진다. 창까지 같이 커지면 겨냥하는 중에
    /// 드롭 영역이 움직여서 커서가 안팎을 오간다.
    static let panelSide: CGFloat = 72

    /// 쉬고 있을 때 한 변.
    ///
    /// 떠 있는 것은 작을수록 화면을 덜 가린다. 다만 너무 작으면 드롭 목표로
    /// 맞히기 어려워지는데, 그건 **창**(`panelSide`)이 받아 준다 —
    /// 눈에 보이는 물방울보다 실제로 받는 영역이 넓다.
    static let restingSide: CGFloat = 44

    /// 테두리 빛과 그림자가 바깥으로 번지는 여유.
    static let edgeAllowance: CGFloat = 5

    /// 상태별 배율.
    ///
    /// `reduceMotion` 을 여기서 보지 않는다. 크기는 이 물방울의 **유일한 상태 신호**라,
    /// 모션을 줄인다고 없애면 무슨 일이 일어나는지 알 방법이 사라진다.
    /// 줄이는 것은 크기가 아니라 **애니메이션**이고, 그건 화면이 정한다.
    static func scale(for phase: DropletPhase) -> CGFloat {
        switch phase {
        case .idle: return 1.00
        // 누르는 것과 옮기는 것은 같은 크기다. 손가락이 닿아 있다는 사실 하나를
        // 말하는 것이고, 누르다 그대로 끌 때 크기가 또 튀면 미끄러진 것처럼 보인다.
        case .pressed, .moving: return 1.18
        // 겨냥하는 중에는 목표가 커져야 놓기 쉽다.
        case .receiving: return 1.32
        }
    }

    /// 상태별 한 변.
    ///
    /// 예전 이름은 `diameter` 였다 — 떠 있는 것이 원에서 둥근 사각형으로 바뀌면서
    /// 지름이 아니라 변이 됐다.
    static func side(for phase: DropletPhase) -> CGFloat {
        (restingSide * scale(for: phase)).rounded()
    }
}
