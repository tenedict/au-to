import AppKit

/// 메뉴바 아이콘 — 맺힌 물방울의 윤곽과 광점 하나.
///
/// **메뉴바 아이콘은 템플릿 이미지다.** 시스템이 알파 채널만 보고 색을 스스로 칠한다 —
/// 밝은 메뉴바에서는 검정, 어두운 메뉴바에서는 흰색, 눌리면 반전. 그래서 여기서
/// 정할 수 있는 것은 **실루엣 하나뿐**이고 색·그라디언트·굴절은 들어가지 않는다.
///
/// 그 제약 안에서 물방울로 읽히게 하는 것은 두 가지다.
///   · 정원이 아닌 윤곽 (`Bead`) — 아래가 눌리고 위가 둥글다
///   · 광점 하나 — 이것이 "젖은 것"을 만든다. 없으면 그냥 원이다
///
/// 광점을 **파내지 않고 채우는** 이유는 크기 때문이다. 18pt 에서 윤곽 안을 파내면
/// 선과 구멍 사이가 1pt 아래로 내려가 뭉갠다. 채운 점은 작아져도 살아남는다.
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
        // 여백 10% — 메뉴바가 아이콘에 딱 붙지 않게 한다.
        let body = rect.insetBy(dx: rect.width * 0.10, dy: rect.height * 0.10)
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let outline = NSBezierPath(cgPath: Bead.cgPath(in: body))
        outline.lineWidth = rect.width * 0.085
        outline.stroke()

        // 물방울의 하이라이트 자리를 쓰되 **안쪽으로 조금 당긴다.**
        // 물방울에서는 흐릿한 덩어리라 가장자리에 걸쳐도 되지만, 18pt 에서는
        // 또렷한 점이라 윤곽선과 붙어 하나로 뭉친다.
        let pull: CGFloat = 0.82
        let radius = body.width * Bead.highlightRadius * pull
        let center = CGPoint(
            x: body.midX + body.width * Bead.highlightOffset.x * pull,
            y: body.midY - body.height * Bead.highlightOffset.y * pull  // AppKit 은 y 가 위로
        )
        NSBezierPath(ovalIn: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )).fill()
    }
}
