import WidgetKit

/// 위젯 타임라인 — **언제 다시 그릴지**를 시스템에 말하는 자리.
///
/// 무엇을 그릴지는 여기서 정하지 않는다. 원장을 읽고 묶는 것은
/// `WidgetSnapshot`(`core/swift/Models`)이 하고, 그래야 테스트가 닿는다 —
/// 위젯 확장 타깃의 코드는 테스트 번들에 들어가지 않는다.

/// 홈 화면 위젯과 잠금화면 위젯이 함께 쓰는 타임라인 공급자.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .placeholder(now: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let now = Date.now
        // 갤러리 미리보기에서는 예시를 보여준다. 실제 배치된 위젯은 원장을 읽는다.
        let snapshot = context.isPreview
            ? WidgetSnapshot.placeholder(now: now)
            : WidgetSnapshot.read(now: now)
        completion(SnapshotEntry(date: now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetSnapshot.read(now: now)
        completion(
            Timeline(
                entries: [SnapshotEntry(date: now, snapshot: snapshot)],
                policy: .after(WidgetRefresh.next(after: now, snapshot: snapshot))))
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}
