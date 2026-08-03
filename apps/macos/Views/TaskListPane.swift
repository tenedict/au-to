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

            // **등록은 이미 됐다.** 이 표식은 "안 됐다" 가 아니라 "한 번 봐 달라" 다.
            if task.needsReview {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(Palette.water)
                    .help(task.reviewReason ?? "확인해 주세요")
                    .accessibilityLabel("확인 필요")
            }
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

/// 확인이 필요한 일정 목록.
///
/// **여기 있는 것도 이미 등록된 할 일이다.** 예전에는 등록되지 않은 초안이 쌓이는
/// 자리였는데, 그때는 사용자가 여기 오지 않으면 아무 일도 일어나지 않았다.
/// 지금은 전부 등록돼 있고, 이 화면은 "한 번 봐 주세요" 가 붙은 것만 모아 보여준다.
struct ReviewPane: View {
    @ObservedObject var store: TaskStore
    let onOpen: (AssistantTask) -> Void

    private var tasks: [AssistantTask] {
        TaskScoping.needingReview(store.tasks, now: .now)
    }

    var body: some View {
        Group {
            if tasks.isEmpty {
                VStack(spacing: Space.gap3) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 42))
                        .foregroundStyle(.tertiary)
                    Text("확인할 게 없어요")
                        .font(.title3.weight(.semibold))
                    Text("등록된 일정을 전부 확인했어요.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(tasks) { task in
                        ReviewRow(task: task) {
                            Task { await store.markReviewed(task.id) }
                        }
                        .contentShape(.rect)
                        .onTapGesture { onOpen(task) }
                        .contextMenu {
                            Button("고치기") { onOpen(task) }
                            Button("이대로 확인함") {
                                Task { await store.markReviewed(task.id) }
                            }
                            Button("삭제", role: .destructive) {
                                Task { await store.delete(task.id) }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 380)
    }
}

/// 확인이 필요한 한 줄.
///
/// **왜 확인이 필요한지를 함께 적는다** — 이유 없이 "확인해 주세요" 만 있으면
/// 무엇을 고쳐야 할지 알 수 없다. 그리고 **고치지 않고 넘어가는 길**을 같은 줄에 둔다:
/// 대부분의 확인은 고칠 것이 없고, 그때마다 편집기를 열게 하면 화면 하나가 더 는다.
private struct ReviewRow: View {
    let task: AssistantTask
    let onApprove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "questionmark.circle")
                .foregroundStyle(Palette.water)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).lineLimit(1)
                Text(task.reviewReason ?? "확인해 주세요.")
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(2)
                Text(
                    DueDateText.string(
                        for: task.dueDate,
                        hasExplicitTime: task.hasExplicitTime,
                        width: .narrow,
                        now: .now)
                )
                .font(.caption)
                .foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 6)
            Button("확인함", action: onApprove)
                .controlSize(.small)
                .help("고칠 것이 없어요. 표식만 지웁니다")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("눌러서 고치거나, 확인함을 눌러 표식을 지워요")
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
