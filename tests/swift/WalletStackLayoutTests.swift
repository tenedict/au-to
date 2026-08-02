import XCTest
@testable import Whenly

/// 지갑 스택의 세로 배치.
///
/// "카드가 겹쳐 보인다" / "펼쳤는데 아래가 잘린다" 는 눈으로만 잡으면 매번 놓친다.
/// 겹침과 밀림을 숫자로 잡는다.
final class WalletStackLayoutTests: XCTestCase {

    private let layout = WalletStackLayout(
        collapsedHeight: 92,
        peekHeight: 64,
        expandedHeight: 248
    )

    /// 카드가 자기 높이보다 좁은 간격으로 내려가야 지갑처럼 겹친다.
    func testCollapsedCardsOverlap() {
        XCTAssertLessThan(layout.peekHeight, layout.collapsedHeight)
        XCTAssertEqual(layout.offset(forCardAt: 0, expandedIndex: nil), 0)
        XCTAssertEqual(layout.offset(forCardAt: 1, expandedIndex: nil), 64)
        XCTAssertEqual(layout.offset(forCardAt: 2, expandedIndex: nil), 128)
    }

    func testExpandedCardPushesEveryCardBelowIt() {
        // 0번을 펼치면 1번부터는 (펼침 높이 − 간격)만큼 통째로 밀린다.
        XCTAssertEqual(layout.offset(forCardAt: 0, expandedIndex: 0), 0)
        XCTAssertEqual(layout.offset(forCardAt: 1, expandedIndex: 0), 248)
        XCTAssertEqual(layout.offset(forCardAt: 2, expandedIndex: 0), 312)
    }

    func testCardsAboveTheExpandedOneDoNotMove() {
        XCTAssertEqual(
            layout.offset(forCardAt: 0, expandedIndex: 2),
            layout.offset(forCardAt: 0, expandedIndex: nil)
        )
        XCTAssertEqual(
            layout.offset(forCardAt: 1, expandedIndex: 2),
            layout.offset(forCardAt: 1, expandedIndex: nil)
        )
    }

    func testExpandedCardDoesNotOverlapTheNextOne() {
        let expandedIndex = 1
        let bottomOfExpanded = layout.offset(forCardAt: expandedIndex, expandedIndex: expandedIndex)
            + layout.height(forCardAt: expandedIndex, expandedIndex: expandedIndex)

        XCTAssertEqual(layout.offset(forCardAt: 2, expandedIndex: expandedIndex), bottomOfExpanded)
    }

    /// 마지막 카드가 잘리면 완료 버튼과 마감일이 화면 밖으로 나간다.
    func testTotalHeightIncludesTheWholeLastCard() {
        XCTAssertEqual(layout.totalHeight(cardCount: 1, expandedIndex: nil), 92)
        XCTAssertEqual(layout.totalHeight(cardCount: 3, expandedIndex: nil), 64 * 2 + 92)
        XCTAssertEqual(layout.totalHeight(cardCount: 3, expandedIndex: 2), 64 * 2 + 248)
        XCTAssertEqual(layout.totalHeight(cardCount: 3, expandedIndex: 0), 248 + 64 + 92)
    }

    func testEmptyStackHasNoHeight() {
        XCTAssertEqual(layout.totalHeight(cardCount: 0, expandedIndex: nil), 0)
    }

    func testDefaultLayoutOverlaps() {
        let standard = WalletStackLayout.default
        XCTAssertLessThan(standard.peekHeight, standard.collapsedHeight)
        XCTAssertGreaterThan(standard.expandedHeight, standard.collapsedHeight)
    }

    // MARK: - Dynamic Type

    /// 카드 높이가 고정값이면 글자를 키운 사용자에게 제목과 마감이 잘린다.
    /// 배율은 세 값에 **함께** 적용되어야 한다.
    func testScalingGrowsEveryDimension() {
        let scaled = layout.scaled(by: 2)

        XCTAssertEqual(scaled.collapsedHeight, 184)
        XCTAssertEqual(scaled.peekHeight, 128)
        XCTAssertEqual(scaled.expandedHeight, 496)
    }

    /// 겹침의 정의(`peek < collapsed`)가 배율과 무관하게 유지되어야 한다.
    /// 하나만 키우면 겹침이 사라지거나 카드가 서로를 덮는다.
    func testOverlapSurvivesEveryAccessibilityTextSize() {
        // 접근성 글자 크기는 3배가 넘게 올라간다.
        for factor in stride(from: 1.0, through: 3.5, by: 0.25) {
            let scaled = layout.scaled(by: CGFloat(factor))

            XCTAssertLessThan(scaled.peekHeight, scaled.collapsedHeight, "배율 \(factor)")
            XCTAssertGreaterThan(scaled.expandedHeight, scaled.collapsedHeight, "배율 \(factor)")
            // 펼친 카드와 다음 카드가 겹치면 안 된다.
            XCTAssertEqual(
                scaled.offset(forCardAt: 2, expandedIndex: 1),
                scaled.offset(forCardAt: 1, expandedIndex: 1) + scaled.expandedHeight,
                accuracy: 0.001,
                "배율 \(factor)"
            )
        }
    }

    /// 글자를 키우면 스택 전체도 그만큼 커져야 마지막 카드가 잘리지 않는다.
    func testTotalHeightGrowsWithTextSize() {
        let standard = layout.totalHeight(cardCount: 4, expandedIndex: 1)
        let large = layout.scaled(by: 2).totalHeight(cardCount: 4, expandedIndex: 1)

        XCTAssertEqual(large, standard * 2, accuracy: 0.001)
    }

    /// 1 보다 작은 배율이 들어오면 카드가 사라진다. 배율은 언제나 1 이상으로 본다.
    func testScalingNeverShrinksBelowTheBaseLayout() {
        XCTAssertEqual(layout.scaled(by: 0.5), layout)
        XCTAssertEqual(layout.scaled(by: 0), layout)
        XCTAssertEqual(layout.scaled(by: -3), layout)
    }
}
