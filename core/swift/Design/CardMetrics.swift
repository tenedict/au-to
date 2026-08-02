import CoreGraphics

/// 접힌 카드와 노출 영역의 치수.
///
/// **적층은 "접힌 카드는 상단 일부만 보인다" 를 전제한다.** 노출 높이는 고정이고
/// 그 안에 들어가야 하는 내용은 가변이라, 전제가 깨지면 넘친 줄이 다음 카드에 가려진다.
/// 실제로 마감이 두 줄이 되어 `14:00` 이 가려졌다 (개발 보고서 §9.1).
///
/// 그래서 값을 화면이 아니라 여기 두고 **테스트가 관계를 지킨다** (디자인 언어 §10.4).
enum CardMetrics {

    /// 접힌 카드의 전체 높이.
    static let collapsedHeight: CGFloat = 92

    /// 그중 실제로 보이는 높이. 나머지는 다음 카드가 덮는다.
    static let peekHeight: CGFloat = 64

    /// 카드 안쪽 여백.
    static let insetTop: CGFloat = Space.gap4        // 16
    static let insetHorizontal: CGFloat = Space.gap4 // 16
    static let insetBottom: CGFloat = Space.gap3     // 12

    /// 제목과 마감 사이.
    static let titleToDue: CGFloat = Space.gap2      // 8

    /// 기본 글자 크기에서 제목 한 줄이 차지하는 높이 (headline).
    static let titleLineHeight: CGFloat = 22

    /// 기본 글자 크기에서 마감 한 줄이 차지하는 높이 (subheadline).
    static let dueLineHeight: CGFloat = 18

    /// 노출 영역이 담아야 하는 내용의 높이.
    ///
    /// 이 값이 `peekHeight` 를 넘으면 마감이 가려진다. 여백을 늘리거나 줄을
    /// 하나 더하면 테스트가 먼저 실패한다 — 화면에서 잘린 것을 눈으로 발견하기 전에.
    static var peekContentHeight: CGFloat {
        insetTop + titleLineHeight + titleToDue + dueLineHeight
    }

    /// 펼쳤을 때의 높이.
    static let expandedHeight: CGFloat = 248
}
