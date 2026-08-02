import XCTest

@testable import CaptureTask

/// 물방울이 상태마다 얼마나 커지는가.
///
/// 화면이 아니라 여기서 정하는 이유는 이 값들이 **서로 묶여 있기** 때문이다.
/// 가장 커진 물방울이 창을 넘으면 가장자리가 잘리고, 잘린 물방울은 물방울로
/// 보이지 않는다 — 예전에 그림자가 창 경계에서 직선으로 잘려 뿌연 네모로
/// 보였던 것과 같은 사고다.
final class DropletAppearanceTests: XCTestCase {

    /// 어떤 상태에서도 물방울이 창 안에 들어와야 한다.
    ///
    /// 테두리와 그림자가 차지하는 여백까지 포함해서 본다. 물방울만 겨우 들어가면
    /// 빛나는 가장자리가 잘린다.
    func testEveryPhaseFitsInsideThePanel() {
        for phase in DropletPhase.allCases {
            let outer = DropletAppearance.diameter(for: phase) + DropletAppearance.edgeAllowance * 2
            XCTAssertLessThanOrEqual(
                outer,
                DropletAppearance.panelSide,
                "\(phase) 에서 물방울(\(outer)pt)이 창(\(DropletAppearance.panelSide)pt)을 넘습니다"
            )
        }
    }

    /// 쉬고 있을 때가 가장 작다. 떠 있는 것은 작을수록 화면을 덜 가린다.
    func testRestingIsTheSmallest() {
        let resting = DropletAppearance.diameter(for: .idle)
        for phase in DropletPhase.allCases where phase != .idle {
            XCTAssertGreaterThan(
                DropletAppearance.diameter(for: phase), resting,
                "\(phase) 가 쉬는 상태보다 크지 않습니다 — 상태 변화가 보이지 않습니다"
            )
        }
    }

    /// 이미지를 끌고 왔을 때가 가장 크다.
    ///
    /// 겨냥하는 중에 목표가 커져야 놓기 쉽다. 작아지면 커서가 밖으로 나가
    /// 놓기가 풀리고, 풀리면 다시 커지고, 커지면 또 들어와 깜빡인다.
    func testReceivingIsTheLargest() {
        let receiving = DropletAppearance.diameter(for: .receiving)
        for phase in DropletPhase.allCases where phase != .receiving {
            XCTAssertGreaterThan(
                receiving, DropletAppearance.diameter(for: phase),
                "받을 때가 \(phase) 보다 크지 않습니다"
            )
        }
    }

    /// 누르는 것과 옮기는 것은 같은 크기다.
    ///
    /// 손가락이 물방울에 닿아 있다는 사실 하나를 말하는 것이고, 누르다가
    /// 그대로 끌기 시작할 때 크기가 한 번 더 튀면 손이 미끄러진 것처럼 보인다.
    func testPressAndMoveLookTheSame() {
        XCTAssertEqual(
            DropletAppearance.diameter(for: .pressed),
            DropletAppearance.diameter(for: .moving)
        )
    }

    /// 크기 차이가 눈에 보여야 한다. 1pt 차이는 아무것도 알려 주지 않는다.
    func testStepsAreBigEnoughToNotice() {
        let resting = DropletAppearance.diameter(for: .idle)
        XCTAssertGreaterThanOrEqual(DropletAppearance.diameter(for: .pressed) - resting, 3)
        XCTAssertGreaterThanOrEqual(
            DropletAppearance.diameter(for: .receiving)
                - DropletAppearance.diameter(for: .pressed),
            3
        )
    }

    /// 떠 있는 물방울은 작아야 한다. 커지면 그냥 창이다.
    func testTheDropletStaysSmallEnoughToFloat() {
        XCTAssertLessThanOrEqual(DropletAppearance.diameter(for: .idle), 50)
    }
}
