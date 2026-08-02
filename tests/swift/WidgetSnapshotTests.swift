import XCTest

@testable import Whenly

/// 위젯이 무엇을 보여주고 언제 다시 그리는가.
///
/// 위젯은 눈으로 확인하기가 가장 어려운 화면이다 — 홈 화면에 올려 두고 몇 시간을
/// 기다려야 잘못을 안다. 그래서 계산을 전부 순수 함수로 빼고 여기서 지킨다.
final class WidgetSnapshotTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - 다시 그릴 시각

    /// 가장 가까운 마감이 지나는 순간이 곧 화면이 바뀌는 순간이다.
    /// "1시간 뒤" 가 "지난 마감" 으로 바뀌는 그때 다시 그려야 한다.
    func testRedrawsWhenTheNearestDeadlinePasses() {
        let soon = now.addingTimeInterval(60 * 30)
        let snapshot = WidgetSnapshot(
            upcoming: [
                AssistantTask(title: "나중", dueDate: now.addingTimeInterval(60 * 90)),
                AssistantTask(title: "곧", dueDate: soon),
            ],
            overdueCount: 0, todayCount: 1, unavailableReason: nil)

        XCTAssertEqual(WidgetRefresh.next(after: now, snapshot: snapshot), soon)
    }

    /// 마감이 하나도 없어도 자정에는 다시 그린다. 오늘이 어제가 되기 때문이다.
    func testRedrawsAtMidnightWhenNothingIsDue() {
        let snapshot = WidgetSnapshot(
            upcoming: [], overdueCount: 0, todayCount: 0, unavailableReason: nil)
        let next = WidgetRefresh.next(after: now, snapshot: snapshot)

        XCTAssertGreaterThan(next, now)
        XCTAssertEqual(next, Calendar.current.startOfDay(for: now.addingTimeInterval(86_400)))
    }

    /// **이미 지난 마감으로 다시 그리라고 하지 않는다.**
    ///
    /// 과거 시각을 주면 시스템이 곧바로 다시 깨우고, 깨어나 보면 여전히 과거라
    /// 또 깨운다. 위젯이 배터리를 먹는 흔한 방식이다.
    func testNeverAsksToRedrawInThePast() {
        let snapshot = WidgetSnapshot(
            upcoming: [AssistantTask(title: "지남", dueDate: now.addingTimeInterval(-60))],
            overdueCount: 1, todayCount: 0, unavailableReason: nil)

        XCTAssertGreaterThan(WidgetRefresh.next(after: now, snapshot: snapshot), now)
    }

    // MARK: - 빈 것과 못 읽은 것

    /// 둘을 구별해야 한다. 같은 화면을 보여주면 App Group 설정이 잘못된 사용자가
    /// "아직 할 일이 없구나" 로 읽고 영영 그 사실을 모른다.
    func testEmptyAndUnavailableAreDifferentStates() {
        let empty = WidgetSnapshot(
            upcoming: [], overdueCount: 0, todayCount: 0, unavailableReason: nil)
        let broken = WidgetSnapshot.unavailable("저장 위치를 찾지 못했어요.")

        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(empty.isUnavailable)
        XCTAssertTrue(broken.isUnavailable)
        XCTAssertEqual(broken.unavailableReason, "저장 위치를 찾지 못했어요.")
    }

    /// 지난 마감만 있어도 "비어 있다" 가 아니다.
    /// 비었다고 그리면 급한 것이 있는데 아무것도 보여주지 않게 된다.
    func testOverdueAloneIsNotEmpty() {
        let snapshot = WidgetSnapshot(
            upcoming: [AssistantTask(title: "지남", dueDate: now.addingTimeInterval(-3600))],
            overdueCount: 1, todayCount: 0, unavailableReason: nil)

        XCTAssertFalse(snapshot.isEmpty)
    }

    /// 갤러리 예시는 비어 있으면 안 된다. 빈 위젯을 본 사용자는 그것이 고장인지
    /// 아직 할 일이 없어서인지 구별하지 못하고, 대개 담지 않는다.
    func testGalleryPlaceholderIsNeverEmpty() {
        XCTAssertFalse(WidgetSnapshot.placeholder(now: now).isEmpty)
    }
}

/// 위젯·바로가기가 앱으로 들어오는 주소.
///
/// 오타는 **아무 오류 없이** 앱을 그냥 열어 버린다. 사용자에게는 눌렀는데
/// 아무 일도 일어나지 않은 것으로 보이고, 실행해 보기 전까지 아무도 못 잡는다.
final class DeepLinkTests: XCTestCase {

    func testCaptureLinkOpensTheCamera() {
        XCTAssertEqual(DeepLink.destination(for: DeepLink.capture), .capture)
    }

    func testTaskLinkOpensTheList() {
        XCTAssertEqual(DeepLink.destination(for: DeepLink.tasks), .tasks)
    }

    /// 모르는 주소는 nil 이다. 아무 데나 열면 링크가 깨진 것을 알 방법이 없다.
    func testUnknownHostGoesNowhere() {
        let url = URL(string: "\(DeepLink.scheme)://somewhere-else")
        XCTAssertNil(url.flatMap(DeepLink.destination(for:)))
    }

    /// 남의 스킴은 받지 않는다.
    func testOtherSchemesAreIgnored() {
        let url = URL(string: "https://capture")
        XCTAssertNil(url.flatMap(DeepLink.destination(for:)))
    }

    /// **`project.yml` 의 `CFBundleURLTypes` 와 같아야 한다.**
    /// 어긋나면 위젯을 눌러도 앱이 열리지 않는다.
    func testSchemeMatchesTheOneRegisteredInTheBundle() throws {
        let types = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }

        XCTAssertTrue(
            schemes.contains(DeepLink.scheme),
            "번들에 등록된 스킴 \(schemes) 에 \(DeepLink.scheme) 이 없습니다")
    }
}
