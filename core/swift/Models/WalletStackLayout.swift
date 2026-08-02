import Foundation

/// 지갑처럼 겹쳐 쌓인 카드의 세로 위치 계산.
///
/// 카드는 자기 높이보다 좁은 간격(`peekHeight`)만큼만 내려가며 쌓인다. 그래서 아래 카드가
/// 위 카드의 아랫부분을 덮고, 사용자에게는 카드 뭉치로 보인다.
/// 하나를 펼치면 그 아래 카드들이 펼쳐진 만큼 통째로 밀린다.
///
/// 계산을 뷰 안에 두면 "카드가 겹쳐 보인다"는 결함을 눈으로만 잡아야 한다.
/// 여기 두면 숫자로 잡는다.
struct WalletStackLayout: Equatable, Sendable {
    /// 접힌 카드가 실제로 차지하는 높이.
    let collapsedHeight: CGFloat
    /// 다음 카드가 내려앉는 간격. `collapsedHeight` 보다 작아야 겹친다.
    let peekHeight: CGFloat
    /// 펼친 카드의 높이.
    let expandedHeight: CGFloat

    /// 값은 `CardMetrics` 에서 온다. 여기 다시 적으면 두 곳이 갈라지고,
    /// 갈라지면 겹침이 어긋난 채로 테스트는 초록을 낸다.
    static let `default` = WalletStackLayout(
        collapsedHeight: CardMetrics.collapsedHeight,
        peekHeight: CardMetrics.peekHeight,
        expandedHeight: CardMetrics.expandedHeight
    )

    /// `index` 번째 카드의 위쪽 좌표.
    func offset(forCardAt index: Int, expandedIndex: Int?) -> CGFloat {
        let base = CGFloat(index) * peekHeight
        guard let expandedIndex, index > expandedIndex else { return base }
        return base + (expandedHeight - peekHeight)
    }

    func height(forCardAt index: Int, expandedIndex: Int?) -> CGFloat {
        index == expandedIndex ? expandedHeight : collapsedHeight
    }

    /// 쌓인 전체가 차지하는 높이. 마지막 카드가 잘리지 않도록 그 카드의 높이까지 더한다.
    func totalHeight(cardCount: Int, expandedIndex: Int?) -> CGFloat {
        guard cardCount > 0 else { return 0 }
        let last = cardCount - 1
        return offset(forCardAt: last, expandedIndex: expandedIndex)
            + height(forCardAt: last, expandedIndex: expandedIndex)
    }

    /// Dynamic Type 배율을 적용한 사본.
    ///
    /// 카드 높이가 고정값이면 글자를 키운 사용자에게는 제목과 마감이 잘린다.
    /// 세 값을 **함께** 키우기 때문에 `peekHeight < collapsedHeight` 라는 겹침의
    /// 정의가 배율과 무관하게 유지된다 — 하나만 키우면 겹침이 사라지거나 카드가 서로를 덮는다.
    ///
    /// 배율은 뷰가 `@ScaledMetric` 으로 읽어 넘긴다. 여기서 환경을 읽지 않는 이유는
    /// 그 순간 이 타입이 순수하지 않게 되고 테스트가 기기 설정에 흔들리기 때문이다.
    func scaled(by factor: CGFloat) -> WalletStackLayout {
        // 0 이하가 들어오면 카드가 사라진다. 배율은 언제나 1 이상으로 본다.
        let safe = max(1, factor)
        return WalletStackLayout(
            collapsedHeight: collapsedHeight * safe,
            peekHeight: peekHeight * safe,
            expandedHeight: expandedHeight * safe
        )
    }
}
