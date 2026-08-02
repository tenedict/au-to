import AppKit
import SwiftUI

/// 물방울을 끌어서 옮기는 일.
///
/// `isMovableByWindowBackground` 를 쓰면 AppKit 이 창을 옮겨 주지만, **옮기는 중이라는
/// 사실을 화면이 알 수 없다.** 사용자가 물방울을 잡고 있는 동안 물방울이 커져야 하므로
/// 옮기기를 직접 다룬다.
///
/// 누르기·옮기기·탭을 제스처 하나로 받는 것도 이래야 가능하다. 제스처를 나눠 달면
/// 탭과 드래그가 서로를 먹는다.
@MainActor
final class DropletMotion: ObservableObject {

    /// 옮길 창. `DropletPanel` 이 만들어진 뒤에 꽂는다.
    weak var panel: NSPanel?

    @Published private(set) var isMoving = false

    /// 이 거리를 넘어야 "옮기는 중"으로 본다.
    ///
    /// 손이 흔들려서 1~2pt 밀리는 것까지 이동으로 보면, 누르려던 사용자가
    /// 매번 창을 조금씩 옮기게 된다.
    static let threshold: CGFloat = 3

    /// 잡은 순간 마우스가 창 원점에서 얼마나 떨어져 있었나.
    private var grab: CGSize?
    /// 잡은 순간의 마우스 자리. 문턱을 재는 기준이다.
    private var start: NSPoint?

    func begin() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        grab = CGSize(width: mouse.x - panel.frame.origin.x,
                      height: mouse.y - panel.frame.origin.y)
        start = mouse
    }

    /// 마우스를 따라 창을 옮긴다.
    ///
    /// **제스처가 알려 주는 이동량(`translation`)을 쓰면 안 된다.** 그 값은 뷰의
    /// 좌표계에서 재는데, 창을 옮기면 뷰도 함께 움직여서 이동량이 상쇄된다 —
    /// 창이 마우스의 절반 속도로 따라오고, 손을 뗄 때까지 계속 뒤처진다.
    /// 실제로 그렇게 만들었다가 967pt 를 끌었는데 창은 483pt 만 움직였다.
    ///
    /// 그래서 화면 좌표(`NSEvent.mouseLocation`)를 직접 읽는다. 잡은 지점과 창
    /// 원점의 간격을 유지하는 방식이라 되먹임이 없다. AppKit 의 창 끌기와 같다.
    func drag() {
        guard let panel, let grab, let start else { return }
        let mouse = NSEvent.mouseLocation
        if !isMoving, hypot(mouse.x - start.x, mouse.y - start.y) < Self.threshold { return }
        isMoving = true
        panel.setFrameOrigin(NSPoint(x: mouse.x - grab.width, y: mouse.y - grab.height))
    }

    /// 손을 뗐다. 옮긴 것이 아니라 그냥 누른 것이었으면 `true` 를 돌려준다.
    @discardableResult
    func end() -> Bool {
        let wasTap = !isMoving
        isMoving = false
        grab = nil
        start = nil
        return wasTap
    }
}
