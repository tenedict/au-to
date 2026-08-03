import SwiftUI

/// 왼쪽 사이드바. 마감 묶음을 급한 순으로 세워 둔다.
///
/// 개수가 0 인 묶음도 감추지 않는다. 홈 화면은 빈 묶음을 감추지만 여기서는 감추면
/// 안 된다 — 일하는 동안 항목이 나타났다 사라지면 누르려던 자리가 움직인다.
struct DashboardSidebar: View {
    let counts: [TaskScope: Int]
    let summary: TaskScoping.Summary
    @Binding var selection: DashboardSelection

    var body: some View {
        List(selection: $selection) {
            // 생김새는 core/swift/Design 의 하나를 쓴다. iOS 홈 상단과 같은 물건이다.
            SummaryTile(summary: summary, onTapReview: { selection = .review })
                // 요약은 고르는 것이 아니라 읽는 것이다. 선택 대상에서 뺀다.
                .selectionDisabled()
                // 좌우 여백을 **0 으로** 준다.
                //
                // 리스트 행은 자기 좌우 여백을 이미 갖고 있다. 타일에 또 여백을 주면
                // 아래 메뉴 글자보다 안쪽에서 시작해, 왼쪽 모서리가 두 줄로 어긋나
                // 보인다. 위아래만 띄우고 좌우는 리스트에 맡긴다.
                .listRowInsets(EdgeInsets(
                    top: Space.gap1, leading: 0, bottom: Space.gap3, trailing: 0))
                .listRowBackground(Color.clear)

            // 확인이 필요한 것은 **맨 위**에 둔다. 아래에 두면 스크롤에 묻히고,
            // 그러면 등록되지 않은 캡처가 조용히 쌓인다.
            if summary.needsReview > 0 {
                Section("확인") {
                    SidebarRow(
                        title: "확인할 일정",
                        symbolName: "questionmark.circle",
                        taskCount: summary.needsReview
                    )
                    .tag(DashboardSelection.review)
                }
            }

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

            // 캘린더는 묶음이 아니다. 같은 원장을 날짜로 본 것이다 —
            // 구역을 나눠 그 차이를 눈에 보이게 한다.
            Section("보기") {
                Label("캘린더", systemImage: "calendar")
                    .tag(DashboardSelection.calendar)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Whenly")
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
