import SwiftUI

/// 왼쪽 사이드바. 마감 묶음을 급한 순으로 세워 둔다.
///
/// 개수가 0 인 묶음도 감추지 않는다. 홈 화면은 빈 묶음을 감추지만 여기서는 감추면
/// 안 된다 — 일하는 동안 항목이 나타났다 사라지면 누르려던 자리가 움직인다.
struct DashboardSidebar: View {
    let counts: [TaskScope: Int]
    @Binding var selection: DashboardSelection

    var body: some View {
        List(selection: $selection) {
            Section("할 일") {
                ForEach(TaskScope.allCases) { scope in
                    SidebarRow(
                        title: scope.title,
                        symbolName: scope.symbolName,
                        taskCount: counts[scope] ?? 0
                    )
                    .tag(DashboardSelection.scope(scope))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("CaptureTask")
    }
}

/// 사이드바 한 줄. 이름 · 기호 · 개수.
///
/// 개수는 0 이면 적지 않는다. "오늘 0" 은 아무것도 알려 주지 않으면서 눈만 끈다.
/// 대신 줄은 남는다 — 자리가 움직이지 않는 것이 숫자보다 중요하다.
private struct SidebarRow: View {
    let title: String
    let symbolName: String
    /// 컬렉션이 아니라 개수다. 이름을 `count` 로 두면 린터가 `isEmpty` 를 쓰라고 한다.
    let taskCount: Int

    var body: some View {
        Label(title, systemImage: symbolName)
            .badge(taskCount)
            .accessibilityLabel(taskCount > 0 ? "\(title), \(taskCount)건" : title)
    }
}
