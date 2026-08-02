import SwiftUI

/// 왼쪽 사이드바. 마감 묶음을 급한 순으로 세워 둔다.
///
/// 개수가 0 인 묶음도 감추지 않는다. 홈 화면은 빈 묶음을 감추지만 여기서는 감추면
/// 안 된다 — 일하는 동안 항목이 나타났다 사라지면 누르려던 자리가 움직인다.
struct DashboardSidebar: View {
    let counts: [TaskScope: Int]
    let summary: TaskScoping.Summary
    let reviewCount: Int
    @Binding var selection: DashboardSelection

    var body: some View {
        List(selection: $selection) {
            SummaryTile(summary: summary)
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
            if reviewCount > 0 {
                Section("확인") {
                    SidebarRow(
                        title: "확인할 할 일",
                        symbolName: "questionmark.circle",
                        taskCount: reviewCount
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
/// ## 이 타일만 색을 갖는 이유
///
/// 나머지 화면은 무채색 + 물색 두 가지다 (CLAUDE 규칙 16). 이 타일은 **화면에서
/// 유일하게 정보를 담지 않은 표면**이라 예외를 둔다 — 여기 칠한 색은 어떤 마감
/// 묶음도 뜻하지 않으므로, 색이 뜻을 갖는다는 규칙을 깨지 않는다.
/// 물방울이 유리에 맺힌 제품이니 표면도 유리여야 한다.
///
/// macOS 26 부터는 시스템의 유리(`glassEffect`)를 그대로 쓴다. 그 아래에서는
/// 같은 인상을 파스텔 그라디언트로 만든다 — 유리가 없다고 밋밋한 회색으로
/// 떨어지면 두 OS 에서 같은 제품으로 보이지 않는다.
///
/// 숫자는 `TaskScoping.summary` 가 센다. 화면이 따로 세면 같은 사이드바 안에서
/// 위와 아래의 숫자가 달라진다.
private struct SummaryTile: View {
    let summary: TaskScoping.Summary

    var body: some View {
        HStack(spacing: Space.gap4) {
            if summary.isClear {
                // 0 을 둘 나열하면 "아무 일도 없다" 가 숫자로만 전달된다. 말로 한다.
                Label("지금은 급한 게 없어요", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            } else {
                Figure(value: summary.overdue, label: "지난 마감")
                Figure(value: summary.today, label: "오늘")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.gap4)
        .padding(.vertical, Space.gap4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
        // 그림자는 얕게. 사이드바 안의 타일이 떠 보이면 사이드바가 두 겹으로 읽힌다.
        .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            summary.isClear
                ? "지금은 급한 게 없어요"
                : "지난 마감 \(summary.overdue)건, 오늘 \(summary.today)건")
    }

    /// 파스텔 그라디언트. 흰 글씨가 어디서든 읽혀야 하므로 **밝은 쪽을 너무 밝히지
    /// 않는다** — 파스텔의 인상은 채도를 낮춰서 만들고, 명도로 만들지 않는다.
    private var surface: some View {
        LinearGradient(
            colors: [
                Color(.sRGB, red: 0.38, green: 0.60, blue: 0.86, opacity: 1),
                Color(.sRGB, red: 0.55, green: 0.52, blue: 0.85, opacity: 1),
                Color(.sRGB, red: 0.36, green: 0.68, blue: 0.78, opacity: 1),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            // 유리에 얹힌 빛. 위쪽만 살짝 밝혀 평평한 색면이 되지 않게 한다.
            LinearGradient(
                colors: [.white.opacity(0.28), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .glassIfAvailable()
    }

    /// 큰 숫자 하나와 그 이름.
    ///
    /// 여기서는 지난 마감에도 붉은색을 쓰지 않는다. 색 있는 표면 위의 붉은 글씨는
    /// 명암비가 무너지고, 급함은 **왼쪽이라는 자리**가 이미 말하고 있다.
    private struct Figure: View {
        /// 컬렉션이 아니라 개수다. 이름을 `count` 로 두면 린터가 `isEmpty` 를 쓰라고 한다.
        let value: Int
        let label: String

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
            }
        }
    }
}

private extension View {
    /// macOS 26 의 유리를 쓸 수 있으면 그 위에 얹는다.
    ///
    /// 물방울(`DropletView`)은 `.clear` 를 쓴다 — 뒤가 보여야 물방울이다.
    /// 여기서는 글씨를 얹는 표면이라 `.regular` 다. 뒤가 그대로 비치면
    /// 흰 글씨가 읽히는지가 뒤에 있는 창에 따라 달라진다.
    @ViewBuilder
    func glassIfAvailable() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: Radius.surface))
        } else {
            self
        }
    }
}
