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

    /// 물방울 지름. 커서로 겨냥하기 쉬우면서 화면을 가리지 않는 크기.
    static let diameter: CGFloat = 96

    init<Content: View>(@ViewBuilder content: () -> Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false          // 그림자는 SwiftUI 쪽에서 원형에 맞춰 그린다
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        // 전체 화면 앱 위에도 떠 있어야 한다. 그렇지 않으면 정작 필요할 때 사라진다.
        animationBehavior = .utilityWindow

        contentView = NSHostingView(rootView: content())
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
            x: visible.maxX - diameter - 28,
            y: visible.minY + 120
        )
    }

    func showDroplet() {
        setFrameAutosaveName("CaptureTaskDroplet")
        orderFrontRegardless()
    }
}
