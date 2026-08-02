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
            SummaryTile(summary: summary)
                // 요약은 고르는 것이 아니라 읽는 것이다. 선택 대상에서 뺀다.
                .selectionDisabled()
                .listRowInsets(EdgeInsets(
                    top: Space.gap2, leading: Space.gap1,
                    bottom: Space.gap3, trailing: Space.gap1))

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

            // 캘린더는 묶음이 아니다. 같은 원장을 날짜로 본 것이고 여기서는
            // 고치지 않는다 — 구역을 나눠 그 차이를 눈에 보이게 한다.
            Section("보기") {
                Label("캘린더", systemImage: "calendar")
                    .tag(DashboardSelection.calendar)
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

/// 사이드바 최상단의 요약 타일.
///
/// **목록에 들어가기 전에 "지금 상태" 를 먼저 말한다.** 일기 앱이 저널 목록 위에
/// 큰 숫자를 두는 것과 같은 구성이다 (디자인 연구 §6.3 · 디자인 언어 §10.6).
///
/// 숫자는 `TaskScoping.summary` 가 센다. 화면이 따로 세면 같은 사이드바 안에서
/// 위와 아래의 숫자가 달라진다.
private struct SummaryTile: View {
    let summary: TaskScoping.Summary

    var body: some View {
        HStack(spacing: Space.gap3) {
            if summary.isClear {
                // 0 을 둘 나열하면 "아무 일도 없다" 가 숫자로만 전달된다. 말로 한다.
                Label("지금은 급한 게 없어요", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(2)
            } else {
                Figure(value: summary.overdue, label: "지난 마감", isUrgent: true)
                Figure(value: summary.today, label: "오늘", isUrgent: false)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.gap3)
        .padding(.vertical, Space.gap3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.surface, style: .continuous)
                .fill(Palette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.surface, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            summary.isClear
                ? "지금은 급한 게 없어요"
                : "지난 마감 \(summary.overdue)건, 오늘 \(summary.today)건")
    }

    /// 큰 숫자 하나와 그 이름.
    private struct Figure: View {
        /// 컬렉션이 아니라 개수다. 이름을 `count` 로 두면 린터가 `isEmpty` 를 쓰라고 한다.
        let value: Int
        let label: String
        let isUrgent: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                    // 색은 지난 마감에만. 0 이면 그것도 쓰지 않는다.
                    .foregroundStyle(isUrgent && value > 0 ? Palette.past : Palette.ink1)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
            }
        }
    }
}
