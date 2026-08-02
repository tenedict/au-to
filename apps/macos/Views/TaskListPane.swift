import SwiftUI

/// 한 묶음의 할 일 목록. 사이드바에서 고른 것이 여기 나온다.
///
/// 무엇이 이 묶음에 들어가고 어떤 순서인지는 `TaskScoping` 이 정한다.
/// 화면이 다시 거르거나 정렬하면 사이드바의 숫자와 여기 길이가 어긋난다.
struct TaskListPane: View {
    @ObservedObject var store: TaskStore
    let scope: TaskScope
    let onPickFiles: () -> Void

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
                        .contextMenu {
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
                    .foregroundStyle(task.isCompleted ? Color.green : Color.secondary)
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
            .foregroundStyle(isOverdue && !task.isCompleted ? Color.red : .secondary)
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
