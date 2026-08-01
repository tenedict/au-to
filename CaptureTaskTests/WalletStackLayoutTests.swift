import XCTest
@testable import CaptureTask

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
}
