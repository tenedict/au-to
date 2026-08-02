import AppKit
import SwiftUI

/// 화면에 떠 있는 물방울 창.
///
/// 일반 창(`NSWindow`)이 아니라 `NSPanel` 인 이유가 몇 가지 있다.
///
/// | `.nonactivatingPanel` | 물방울을 눌러도 **다른 앱이 뒤로 가지 않는다.** 작업하던 창에서 그대로 끌어다 놓을 수 있어야 한다 |
/// | `.floating` | 다른 창 위에 떠 있는다 |
/// | `canJoinAllSpaces` | 데스크톱을 바꿔도 따라온다 |
/// | 투명 배경 | 원형 물방울 밖의 사각형이 보이지 않는다 |
///
/// SwiftUI 의 `Window`/`WindowGroup` 로는 이 조합을 만들 수 없어서 AppKit 을 직접 쓴다.
final class DropletPanel: NSPanel {

    /// 창 한 변.
    ///
    /// **창은 고정이고 물방울만 커진다.** 창까지 같이 커지면 겨냥하는 중에 드롭
    /// 영역이 움직여서 커서가 안팎을 오간다 — 그러면 놓기가 풀렸다 걸렸다 깜빡인다.
    ///
    /// 그래서 눈에 보이는 물방울보다 **실제로 받는 영역이 넓다.** 떠 있는 것은
    /// 작을수록 화면을 덜 가리지만, 작으면 맞히기 어려워지는 것을 창이 받아 준다.
    static var side: CGFloat { DropletAppearance.panelSide }

    init<Content: View>(@ViewBuilder content: () -> Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.side, height: Self.side),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false          // 그림자는 SwiftUI 쪽에서 물방울 모양에 맞춰 그린다
        // 옮기기는 DropletMotion 이 직접 다룬다. AppKit 에 맡기면 **옮기는 중이라는
        // 사실을 화면이 알 수 없어서**, 잡고 있는 동안 물방울을 키울 수 없다.
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        // 전체 화면 앱 위에도 떠 있어야 한다. 그렇지 않으면 정작 필요할 때 사라진다.
        animationBehavior = .utilityWindow

        // NSHostingView 는 기본 배경을 그린다. 이걸 비우지 않으면 고리 뒤에
        // 옅은 네모가 남는다 — 창을 투명하게 해도 안쪽 뷰가 칠하면 소용없다.
        let hosting = NSHostingView(rootView: content())
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = .clear
        contentView = hosting
        setFrameOrigin(Self.defaultOrigin())
    }

    // borderless 창은 기본적으로 키를 못 받는다. 드롭과 클릭을 받으려면 열어 준다.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 처음 뜨는 자리 — 주 화면 오른쪽 아래.
    ///
    /// Dock 과 겹치지 않게 충분히 띄운다. 사용자가 옮기면 그 자리를 기억한다
    /// (`setFrameAutosaveName`).
    private static func defaultOrigin() -> NSPoint {
        guard let visible = NSScreen.main?.visibleFrame else { return NSPoint(x: 100, y: 100) }
        return NSPoint(
            x: visible.maxX - side - 28,
            y: visible.minY + 120
        )
    }

    func showDroplet() {
        setFrameAutosaveName("CaptureTaskDroplet")
        orderFrontRegardless()
    }
}
