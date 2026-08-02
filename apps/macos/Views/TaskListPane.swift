import SwiftUI

/// 한 묶음의 할 일 목록. 사이드바에서 고른 것이 여기 나온다.
///
/// 무엇이 이 묶음에 들어가고 어떤 순서인지는 `TaskScoping` 이 정한다.
/// 화면이 다시 거르거나 정렬하면 사이드바의 숫자와 여기 길이가 어긋난다.
struct TaskListPane: View {
    @ObservedObject var store: TaskStore
    let scope: TaskScope
    let onPickFiles: () -> Void
    /// 줄을 눌렀을 때 열 것. 자세히 보기와 고치기는 한 화면이다.
    let onOpen: (AssistantTask) -> Void

    @State private var selection: UUID?

    private var tasks: [AssistantTask] {
        TaskScoping.tasks(store.tasks, in: scope, now: .now)
    }

    var body: some View {
        Group {
            if tasks.isEmpty {
                EmptyPane(scope: scope, onPickFiles: onPickFiles)
            } else {
                List(selection: $selection) {
                    ForEach(tasks) { task in
                        MacTaskRow(task: task) {
                            Task { await store.toggleCompletion(for: task.id) }
                        }
                        .tag(task.id)
                        // 한 번 눌러 고른 것과 두 번 눌러 여는 것을 나눈다.
                        // 한 번에 열면 화살표로 목록을 훑는 것만으로 창이 계속 뜬다.
                        .onTapGesture(count: 2) { onOpen(task) }
                        .contextMenu {
                            Button("자세히 보기·고치기") { onOpen(task) }
                            Button(task.isCompleted ? "완료 취소" : "완료로 표시") {
                                Task { await store.toggleCompletion(for: task.id) }
                            }
                            Button("삭제", role: .destructive) {
                                Task { await store.delete(task.id) }
                            }
                        }
                    }
                }
                // 줄무늬(alternatingRowBackgrounds)는 쓰지 않는다. 내용이 짧으면
                // 아래로 빈 줄이 계속 그려져서 없는 할 일이 있는 것처럼 보인다.
                .listStyle(.inset)
                // 고른 줄을 Return 으로도 열 수 있어야 한다. 포인터만 쓸 수 있는
                // 조작은 키보드 사용자에게 없는 기능과 같다.
                .onKeyPress(.return) {
                    guard let selected = tasks.first(where: { $0.id == selection })
                    else { return .ignored }
                    onOpen(selected)
                    return .handled
                }
            }
        }
        .frame(minWidth: 380)
    }
}

/// 확인이 필요한 초안 목록.
///
/// 날짜가 모호해 바로 등록하지 못한 것들이다. **여기 쌓이는 것을 사용자가 볼 수
/// 있어야 한다** — 예전에는 이 목록을 보여주는 화면이 없어서, 모호한 캡처는
/// 등록도 안 되고 어디에도 보이지 않은 채 사라진 것처럼 보였다.
struct ReviewPane: View {
    @ObservedObject var store: TaskStore
    let onOpen: (TaskDraft) -> Void

    var body: some View {
        Group {
            if store.pendingDrafts.isEmpty {
                VStack(spacing: Space.gap3) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 42))
                        .foregroundStyle(.tertiary)
                    Text("확인할 게 없어요")
                        .font(.title3.weight(.semibold))
                    Text("담은 스크린샷은 전부 등록됐어요.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.pendingDrafts) { draft in
                        DraftRow(draft: draft)
                            .contentShape(.rect)
                            .onTapGesture { onOpen(draft) }
                            .contextMenu {
                                Button("확인하고 등록") { onOpen(draft) }
                                Button("버리기", role: .destructive) { store.discard(draft) }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 380)
    }
}

/// 확인을 기다리는 초안 한 줄. **왜 확인이 필요한지를 함께 적는다** —
/// 이유 없이 "확인해 주세요" 만 있으면 무엇을 고쳐야 할지 알 수 없다.
private struct DraftRow: View {
    let draft: TaskDraft

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(Palette.water)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 3) {
                Text(draft.title).lineLimit(1)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("눌러서 고치고 등록해요")
    }

    /// 판정은 화면이 다시 하지 않는다. `AutoFilePolicy` 가 등록을 막은 그 이유를 그대로 쓴다.
    private var reason: String {
        if case .askFirst(let reason) = AutoFilePolicy.decide(for: draft) { return reason }
        return "확인해 주세요."
    }
}

/// 할 일 한 줄.
///
/// 마감이 지났는지는 여기서 다시 계산하지 않고 `DueGrouping` 에 묻는다.
/// 색으로만 알리지 않도록 지난 마감에는 기호를 함께 붙인다 (CLAUDE 규칙 13).
struct MacTaskRow: View {
    let task: AssistantTask
    let onToggle: () -> Void

    private var isOverdue: Bool {
        DueGrouping.bucket(for: task, now: .now) == .overdue
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? Palette.water : Palette.ink3)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "완료 취소" : "완료로 표시")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .lineLimit(1)
                dueLine
            }

            Spacer(minLength: 6)

            if task.calendarEventIdentifier != nil {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Apple 캘린더에 들어가 있어요")
                    .accessibilityLabel("캘린더에 등록됨")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var dueLine: some View {
        if let dueDate = task.dueDate {
            HStack(spacing: 4) {
                if isOverdue && !task.isCompleted {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                Text(
                    DueDateText.string(
                        for: dueDate,
                        hasExplicitTime: task.hasExplicitTime,
                        width: .narrow,
                        now: .now
                    )
                )
            }
            .font(.caption)
            .foregroundStyle(isOverdue && !task.isCompleted ? Palette.past : Palette.ink3)
        } else {
            Text("날짜 확인 필요")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// 비어 있을 때. 무엇이 없는지와 **다음에 무엇을 하면 되는지**를 함께 말한다.
private struct EmptyPane: View {
    let scope: TaskScope
    let onPickFiles: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: scope.symbolName)
                .font(.system(size: 42))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.title3.weight(.semibold))
            if isFirstRun {
                Text("화면에 떠 있는 물방울에 스크린샷을 끌어다 놓으면\n날짜를 읽어 캘린더까지 넣어요.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("파일에서 고르기", action: onPickFiles)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var isFirstRun: Bool { scope == .all }

    private var message: String {
        switch scope {
        case .all: return "아직 할 일이 없어요"
        case .due(.overdue): return "지난 마감이 없어요"
        case .due(.today): return "오늘 할 일이 없어요"
        case .due(.done): return "아직 끝낸 일이 없어요"
        case .due(let bucket): return "\(bucket.title)에 아무것도 없어요"
        }
    }
}
