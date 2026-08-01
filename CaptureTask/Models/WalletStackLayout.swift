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

    static let `default` = WalletStackLayout(
        collapsedHeight: 92,
        peekHeight: 64,
        expandedHeight: 248
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
}
