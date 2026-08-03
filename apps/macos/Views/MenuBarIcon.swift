import AppKit
import SwiftUI

/// 메뉴바 아이콘 — 앱 아이콘을 아주 단순하게 줄인 표식.
///
/// **메뉴바 아이콘은 템플릿 이미지다.** 시스템이 알파 채널만 보고 색을 스스로 칠한다 —
/// 밝은 메뉴바에서는 검정, 어두운 메뉴바에서는 흰색, 눌리면 반전. 그래서 여기서
/// 정할 수 있는 것은 **실루엣 하나뿐**이고 색·그라디언트는 들어가지 않는다.
///
/// 모양은 `Mark`(`core/swift/Design/WhenlyMark.swift`) 하나에서 온다.
/// 앱 아이콘 · 잠금화면 위젯 · 홈 화면 위젯 · 떠 있는 창이 전부 같은 것을 쓴다 —
/// 자리마다 다르게 그리면 같은 앱으로 보이지 않는다.
///
/// AppKit 으로 다시 그리는 이유는 **`NSImage` 가 필요해서**다. SwiftUI 뷰를
/// 메뉴바에 그대로 넣을 수 없고, 넣는다 해도 템플릿으로 표시할 방법이 없다.
/// 경로 계산 자체는 `Mark` 가 하므로 두 자리의 모양이 갈라지지는 않는다.
enum MenuBarIcon {

    /// 메뉴바 표준 높이.
    static let side: CGFloat = 18

    /// `NSImage(size:flipped:drawingHandler:)` 로 만든다.
    ///
    /// `lockFocus` 로 그리면 그 순간의 배율로 한 번 굳는다. 외장 모니터를 물리거나
    /// 배율이 다른 화면으로 창을 옮기면 흐려진다. 이 방식은 필요할 때마다
    /// 그 화면의 배율로 다시 그린다.
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            draw(in: rect)
            return true
        }
        // 시스템이 색을 칠하게 맡긴다. 이 줄이 없으면 메뉴바에서 늘 검정이라
        // 어두운 메뉴바에서 보이지 않는다.
        image.isTemplate = true
        return image
    }()

    /// 실루엣을 그린다. 색은 언제나 현재 색(`NSColor.black`)이고 시스템이 갈아 낀다.
    private static func draw(in rect: CGRect) {
        // 여백 8% — 메뉴바가 아이콘에 딱 붙지 않게 한다.
        let body = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08)
        // 18pt 에서는 선이 조금만 가늘어도 사라진다. 화면용보다 두껍게 잡는다.
        let line = max(body.width * 0.10, 1.5)

        NSColor.black.setStroke()
        NSColor.black.setFill()

        // 선의 절반이 바깥으로 나가지 않게 안쪽으로 밀어 그린다. 이 크기에서는
        // 그 절반이 잘리는 것만으로 두께가 눈에 띄게 달라 보인다.
        let outlineRect = body.insetBy(dx: line / 2, dy: line / 2)
        let outline = NSBezierPath(cgPath: flipped(Mark.outline(in: outlineRect).cgPath, in: rect))
        outline.lineWidth = line
        outline.stroke()

        NSBezierPath(cgPath: flipped(Mark.bars(in: body).cgPath, in: rect)).fill()
    }

    /// SwiftUI 좌표(y 아래로)를 AppKit 좌표(y 위로)로 뒤집는다.
    ///
    /// 뒤집지 않으면 **빗금의 기울기가 거울처럼 반대로** 그려진다. 사각형과 줄 수는
    /// 같아서 언뜻 맞아 보이는데, 앱 아이콘 옆에 나란히 두면 어긋난 것이 보인다.
    private static func flipped(_ path: CGPath, in rect: CGRect) -> CGPath {
        var transform = CGAffineTransform(translationX: 0, y: rect.height)
            .scaledBy(x: 1, y: -1)
        return path.copy(using: &transform) ?? path
    }
}
