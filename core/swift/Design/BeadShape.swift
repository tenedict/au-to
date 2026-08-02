import CoreGraphics
import SwiftUI

/// 유리에 맺힌 물방울의 윤곽. **완벽한 원이 아니다.**
///
/// 실제 물방울은 표면장력과 중력이 함께 만든 모양이라
///
/// | 아래가 조금 넓고 평평하다 | 중력에 눌린다 |
/// | 위가 더 둥글다 | 눌린 만큼 위로 선다 |
/// | 좌우가 완전히 대칭이 아니다 | 유리에 닿은 자리가 한쪽으로 미세하게 치우친다 |
///
/// 그 어긋남이 **"그려진 원"과 "맺힌 물"을 가른다.** 정원으로 그리면 아무리
/// 빛을 얹어도 도형으로 읽힌다.
///
/// **이 제품의 표식은 이 윤곽 하나다.** 맥의 메뉴바 아이콘, 아이폰 잠금화면 위젯,
/// 앱 아이콘이 전부 같은 곡선을 쓴다 — 자리마다 다르게 그리면 같은 물건으로 보이지 않는다.
/// 그래서 화면 폴더가 아니라 `core/swift/Design` 에 있다.
///
/// (앱 아이콘만 예외로 값을 옮겨 적었다. `scripts/icon/MakeIcon.swift` 는 앱 밖에서
/// 도는 독립 스크립트라 이 파일을 가져다 쓸 수 없다.)
struct BeadShape: Shape, InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        Path(Bead.cgPath(in: rect.insetBy(dx: inset, dy: inset)))
    }

    func inset(by amount: CGFloat) -> BeadShape {
        BeadShape(inset: inset + amount)
    }
}

/// 윤곽의 실제 계산. SwiftUI 와 AppKit 이 함께 쓴다.
enum Bead {

    /// 좌표계는 **y 가 아래로 자란다** (SwiftUI · CoreGraphics 기본).
    ///
    /// 원을 네 조각으로 나누고 조각마다 부풀기를 달리 준다. 베지어 상수 `k` 는
    /// 정원을 만드는 값이고, 여기에 곱하는 계수가 물방울다움을 만든다 —
    /// 아래쪽 조각의 계수가 1보다 크면 그만큼 평평해진다.
    static func cgPath(in rect: CGRect) -> CGPath {
        let cx = rect.midX, cy = rect.midY
        let radiusLeft = rect.width * 0.500
        let radiusRight = rect.width * 0.487      // 좌우 살짝 비대칭
        let radiusTop = rect.height * 0.512       // 위가 높고
        let radiusBottom = rect.height * 0.470    // 아래가 눌림
        let k: CGFloat = 0.5523

        let path = CGMutablePath()
        path.move(to: CGPoint(x: cx, y: cy - radiusTop))                       // 꼭대기
        path.addCurve(                                                          // → 오른쪽
            to: CGPoint(x: cx + radiusRight, y: cy),
            control1: CGPoint(x: cx + radiusRight * k * 1.02, y: cy - radiusTop),
            control2: CGPoint(x: cx + radiusRight, y: cy - radiusTop * k * 1.02))
        path.addCurve(                                                          // → 바닥 (평평)
            to: CGPoint(x: cx, y: cy + radiusBottom),
            control1: CGPoint(x: cx + radiusRight, y: cy + radiusBottom * k * 1.20),
            control2: CGPoint(x: cx + radiusRight * k * 1.18, y: cy + radiusBottom))
        path.addCurve(                                                          // → 왼쪽
            to: CGPoint(x: cx - radiusLeft, y: cy),
            control1: CGPoint(x: cx - radiusLeft * k * 1.18, y: cy + radiusBottom),
            control2: CGPoint(x: cx - radiusLeft, y: cy + radiusBottom * k * 1.20))
        path.addCurve(                                                          // → 꼭대기
            to: CGPoint(x: cx, y: cy - radiusTop),
            control1: CGPoint(x: cx - radiusLeft, y: cy - radiusTop * k * 0.98),
            control2: CGPoint(x: cx - radiusLeft * k * 0.98, y: cy - radiusTop))
        path.closeSubpath()
        return path
    }

    /// 주광이 맺히는 자리 — 왼쪽 위. 비율로 준다 (크기가 바뀌어도 같은 자리).
    static let highlightOffset = CGPoint(x: -0.26, y: -0.24)
    /// 주광의 반지름 (지름 대비).
    static let highlightRadius: CGFloat = 0.115
}
