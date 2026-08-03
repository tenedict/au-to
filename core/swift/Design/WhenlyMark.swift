import CoreGraphics
import SwiftUI

/// 이 제품의 표식 — **둥근 정사각형 안의 빗금 세 줄.**
///
/// 앱 아이콘을 아주 단순하게 줄인 것이다. 메뉴바 아이콘, 잠금화면 위젯, 홈 화면
/// 위젯, 떠 있는 물방울 자리가 **전부 이 하나**를 쓴다.
///
/// ## 왜 한 곳에서 그리는가
///
/// 예전에는 자리마다 다른 그림이었다 — 아이콘은 색 막대, 메뉴바는 물방울,
/// 위젯은 또 물방울. 세 자리를 나란히 보면 같은 앱으로 보이지 않았다.
/// 표식은 **하나여야 한다.**
///
/// ## 왜 이 모양인가
///
/// 작은 크기에서 살아남아야 한다. 메뉴바는 18pt, 잠금화면 원형은 그보다 작다.
/// 그 크기에서 남는 것은 **바깥 윤곽과 안쪽 줄무늬의 리듬**뿐이라, 색이나
/// 그라디언트가 아니라 이 둘로만 만들었다.
///
/// 빗금은 **오른쪽으로 기운다.** 수평선 셋은 목록 · 메뉴 · 햄버거로 읽히는데,
/// 기울이면 "지나가는 시간" 쪽으로 읽힌다. 이 제품은 목록 앱이 아니라 일정 앱이다.
enum Mark {

    /// 바깥 둥근 사각형의 모서리 반경. 한 변에 대한 비율이다.
    ///
    /// iOS 아이콘의 곡률(약 0.22)보다 조금 작다 — 아이콘 안에 다시 그려지는
    /// 도형이라, 같은 곡률로 그리면 아이콘 모서리와 겹쳐 보인다.
    static let cornerRatio: CGFloat = 0.20

    /// 빗금 셋이 차지하는 영역의 안쪽 여백.
    static let inset: CGFloat = 0.25

    /// 빗금 하나의 두께. 한 변에 대한 비율이다.
    static let barHeight: CGFloat = 0.098

    /// 빗금 사이 간격.
    ///
    /// 두께보다 **조금 작게** 잡는다. 같거나 크면 줄이 흩어져 보이고, 훨씬 작으면
    /// 18pt 메뉴바에서 셋이 한 덩어리로 뭉친다. 실제로 눈으로 맞춘 값이다.
    static let barGap: CGFloat = 0.090

    /// 기울기 — 한 빗금의 위아래 x 차이. 이 값이 0 이면 그냥 목록이 된다.
    static let slant: CGFloat = 0.085

    /// 빗금 세 줄의 경로. `rect` 안에 꽉 맞춰 그린다.
    ///
    /// 세 줄의 길이를 다르게 하지 않는다. 길이가 다르면 "정렬" 이나 "신호 세기" 로
    /// 읽히는데, 여기서 뜻하는 것은 **차곡차곡 쌓인 일정**이다.
    static func bars(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let left = rect.minX + side * inset
        let right = rect.maxX - side * inset
        let height = side * barHeight
        let gap = side * barGap
        let slantWidth = side * slant

        // 셋을 세로 가운데에 모은다.
        let total = height * 3 + gap * 2
        var top = rect.midY - total / 2

        var path = Path()
        for _ in 0..<3 {
            // 평행사변형 — 위쪽 변이 오른쪽으로 밀려 있다.
            path.move(to: CGPoint(x: left + slantWidth, y: top))
            path.addLine(to: CGPoint(x: right, y: top))
            path.addLine(to: CGPoint(x: right - slantWidth, y: top + height))
            path.addLine(to: CGPoint(x: left, y: top + height))
            path.closeSubpath()
            top += height + gap
        }
        return path
    }

    /// 바깥 윤곽의 경로.
    static func outline(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let square = CGRect(
            x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        return Path(roundedRect: square, cornerRadius: side * cornerRatio, style: .continuous)
    }
}

/// 표식을 그리는 뷰.
///
/// 색을 정하지 않는다 — 부르는 쪽이 `foregroundStyle` 로 준다. 메뉴바와 잠금화면은
/// 시스템이 색을 스스로 칠하기 때문에, 여기서 색을 박으면 그 자리에서 무시되거나
/// 어긋난다.
struct MarkView: View {
    /// 윤곽선 두께. 한 변에 대한 비율이다.
    var lineRatio: CGFloat = 0.075

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let line = max(side * lineRatio, 1)
            let rect = CGRect(origin: .zero, size: size)
            // **선의 절반이 도형 바깥으로 나가지 않게** 안쪽으로 밀어 그린다.
            // 그냥 그리면 작은 크기에서 윤곽의 바깥쪽 절반이 잘려 두께가 달라 보인다.
            let inner = rect.insetBy(dx: (rect.width - side + line) / 2,
                                     dy: (rect.height - side + line) / 2)
            context.stroke(Mark.outline(in: inner), with: .foreground, lineWidth: line)
            context.fill(Mark.bars(in: rect), with: .foreground)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
