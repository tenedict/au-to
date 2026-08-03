import SwiftUI

/// 맥의 대시보드. 물방울을 누르거나 메뉴바·Dock 에서 연다.
///
/// iOS 의 지갑 스택을 그대로 옮기지 않았다. 맥은 화면이 넓고 포인터가 정확해서,
/// 겹쳐 쌓는 것보다 왼쪽에서 묶음을 고르고 오른쪽에서 목록을 보는 쪽이 낫다.
/// **화면은 플랫폼마다 다른 것이 맞다.**
///
/// 무엇을 어떤 순서로 보여줄지는 여기서 정하지 않는다 — `TaskScoping` 이 정한다.
/// 화면이 세면 사이드바의 숫자와 목록의 길이가 언젠가 어긋난다.
///
/// **무엇을 누르든 `TaskEditorSheet` 하나로 간다.** 목록의 줄이든 캘린더의 일정이든
/// 확인이 필요한 초안이든 사용자에게는 같은 "고치는 화면" 이어야 한다.
struct DashboardView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var queue: CaptureQueue
    /// 알림이 가리킨 일정. 창이 뜬 뒤 여기서 집어 간다.
    @ObservedObject var pendingEdit: PendingEditRequest
    let onPickFiles: () -> Void

    @State private var selection: DashboardSelection = .scope(.all)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var editing: AssistantTask?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            DashboardSidebar(counts: counts, summary: summary, selection: $selection)
            .navigationSplitViewColumnWidth(min: 210, ideal: 226, max: 280)
        } detail: {
            detail
                .navigationTitle(selection.title)
                .toolbar {
                    // 가장 중요한 동작 하나는 그룹에서 뗀다 (디자인 언어 §10.7).
                    // 지갑이 추가(+)만 별도 캡슐로 두는 것과 같다.
                    ToolbarItem(placement: .primaryAction) {
                        Button { editing = .blank(now: .now) } label: {
                            Label("새 일정", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("n")
                        .help("스크린샷 없이 직접 적어요")
                    }
                    ToolbarItem {
                        Button(action: onPickFiles) {
                            Label("파일에서 고르기", systemImage: "photo.on.rectangle")
                        }
                        .help("스크린샷을 골라 일정으로 만들어요")
                    }
                }
        }
        .frame(minWidth: 720, minHeight: 480)
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .sheet(item: $editing) { task in
            TaskEditorSheet(task: task, store: store)
        }
        .task { await store.refresh() }
        // 알림을 눌러 이 창이 열렸다면 그 일정을 곧바로 연다.
        .task { openRequestedEdit() }
        .onChange(of: pendingEdit.taskID) { _, _ in openRequestedEdit() }
    }

    /// 알림이 가리킨 일정을 연다. 그 사이 지워졌으면 조용히 넘어간다 —
    /// 없는 것을 열려고 빈 시트를 띄우는 것보다 낫다.
    private func openRequestedEdit() {
        guard let taskID = pendingEdit.take(),
              let task = store.tasks.first(where: { $0.id == taskID }) else { return }
        editing = task
    }

    // MARK: - 본문

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .scope(let scope):
            TaskListPane(
                store: store, scope: scope, onPickFiles: onPickFiles,
                onOpen: { editing = $0 })
        case .review:
            ReviewPane(store: store, onOpen: { editing = $0 })
        case .calendar:
            MonthCalendarPane(store: store, onOpen: { editing = $0 })
        }
    }

    private var counts: [TaskScope: Int] {
        TaskScoping.counts(for: store.tasks, now: .now)
    }

    private var summary: TaskScoping.Summary {
        TaskScoping.summary(for: store.tasks, now: .now)
    }

    // MARK: - 아래 상태 줄

    /// 분석 엔진과 담기 상태. 창 어디에 있든 같은 자리에서 보이게 아래에 붙인다.
    ///
    /// 읽는 중이라는 표시는 **여기에만** 둔다. 물방울에는 두지 않는다 — 읽기는
    /// 뒤에서 돌고 끝나면 알림이 오므로, 사용자가 지켜볼 필요가 없어야 한다.
    private var statusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                if let explanation = store.inboxAvailability.explanation {
                    Label(explanation, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.past)
                        .lineLimit(1)
                        .help(explanation)
                }
                if queue.waiting > 0 || store.isImporting {
                    ProgressView().controlSize(.small)
                    Text(queueDescription)
                }
                if let error = store.lastErrorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(Palette.past)
                        .lineLimit(1)
                        .help(error)
                }
                Spacer(minLength: 8)
                Label(store.engine.title, systemImage: "cpu")
                    .foregroundStyle(.secondary)
                    .help(store.engine.detail)
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .background(.bar)
    }

    private var queueDescription: String {
        queue.waiting > 0 ? "읽는 중이에요 · \(queue.waiting)장 남음" : "읽는 중이에요"
    }
}

/// 사이드바에서 고른 것.
///
/// 묶음과 캘린더는 성격이 다르다 — 묶음은 목록이고 캘린더는 같은 원장을 날짜로
/// 본 것이다. `TaskScope` 를 그대로 선택 타입으로 쓰면 캘린더를 넣을 자리가 없다.
enum DashboardSelection: Hashable {
    case scope(TaskScope)
    /// 등록은 됐지만 사람이 한 번 봐야 하는 것들.
    case review
    case calendar

    var title: String {
        switch self {
        case .scope(let scope): return scope.title
        case .review: return "확인할 일정"
        case .calendar: return "캘린더"
        }
    }
}
