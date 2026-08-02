import CoreGraphics

/// 간격 눈금 — 4pt 격자.
///
/// 여덟 개로 충분하다. **그 사이 값은 쓰지 않는다.** 18 이나 5 같은 값이 하나 들어오면
/// 그 자리만 미묘하게 어긋나고, 다음 사람은 그 값을 근거로 또 다른 값을 만든다
/// (디자인 언어 §6).
enum Space {
    /// 4 — 아이콘과 붙는 글자 · 기호 사이
    static let gap1: CGFloat = 4
    /// 8 — 제목과 보조 텍스트 사이
    static let gap2: CGFloat = 8
    /// 12 — 행 안의 요소 사이 · 카드 내부 세로
    static let gap3: CGFloat = 12
    /// 16 — 카드 내부 여백 · 목록 좌우 여백
    static let gap4: CGFloat = 16
    /// 20 — 화면 좌우 여백 (iOS)
    static let gap5: CGFloat = 20
    /// 24 — 구획 사이
    static let gap6: CGFloat = 24
    /// 32 — 화면 제목 아래
    static let gap7: CGFloat = 32
    /// 40 — 빈 상태의 요소 사이
    static let gap8: CGFloat = 40

    /// 최소 조작 영역.
    ///
    /// 눈에 보이는 것이 이보다 작아도 받는 영역은 이 크기를 지킨다.
    enum Touch {
        static let iOS: CGFloat = 44
        static let mac: CGFloat = 28
    }
}

/// 모서리 반경.
///
/// 전부 `.continuous` 를 쓴다. iOS 의 표준 곡선이며 원형 모티프(물방울)와 이어진다.
enum Radius {
    /// 20 — 할 일 카드 · 시트 상단
    static let card: CGFloat = 20
    /// 12 — 일별 일정 행 · 배너 · 정보 타일
    static let surface: CGFloat = 12
    /// 8 — 작은 버튼 · 태그
    static let small: CGFloat = 8
}
