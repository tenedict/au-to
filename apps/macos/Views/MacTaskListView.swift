import SwiftUI

/// 맥의 할 일 창. 물방울을 누르거나 메뉴바에서 연다.
///
/// iOS 의 지갑 스택을 그대로 옮기지 않았다. 맥은 화면이 넓고 포인터가 정확해서,
/// 겹쳐 쌓는 것보다 한눈에 보이는 목록이 낫다. **화면은 플랫폼마다 다른 것이 맞다.**
struct MacTaskListView: View {
    @ObservedObject var store: TaskStore
    let onPickFiles: () -> Void

    @State private var selection: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if store.tasks.isEmpty {
                empty
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(minWidth: 460, minHeight: 420)
        .task { await store.refresh() }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(store.dueGroups()) { group in
                Section {
                    ForEach(group.tasks) { task in
                        MacTaskRow(task: task, bucket: group.bucket) {
                            Task { await store.toggleCompletion(for: task.id) }
                        }
                        .tag(task.id)
                        .contextMenu {
                            Button("완료로 표시") {
                                Task { await store.toggleCompletion(for: task.id) }
                            }
                            Button("삭제", role: .destructive) {
                                Task { await store.delete(task.id) }
                            }
                        }
                    }
                } header: {
                    Label(
                        "\(group.bucket.title)  \(group.count)",
                        systemImage: group.bucket.symbolName
                    )
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .listStyle(.inset)
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Image(systemName: "drop.fill")
                .font(.system(size: 46))
                .foregroundStyle(.tertiary)
            Text("아직 할 일이 없어요")
                .font(.title3.weight(.semibold))
            Text("화면에 떠 있는 물방울에 스크린샷을 끌어다 놓으면\n날짜를 읽어 캘린더까지 넣어요.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("파일에서 고르기", action: onPickFiles)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: onPickFiles) {
                Label("파일에서 고르기", systemImage: "photo.on.rectangle")
            }
            Spacer()
            if let explanation = store.inboxAvailability.explanation {
                Label(explanation, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .help(explanation)
            }
            Text(store.engine.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(store.engine.detail)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct MacTaskRow: View {
    let task: AssistantTask
    let bucket: DueBucket
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "완료 취소" : "완료로 표시")

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                    .lineLimit(1)
                if let dueDate = task.dueDate {
                    Text(
                        dueDate.formatted(
                            date: .abbreviated,
                            time: task.hasExplicitTime ? .shortened : .omitted
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(bucket == .overdue ? Color.red : .secondary)
                } else {
                    Text("날짜 확인 필요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            if task.calendarEventIdentifier != nil {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Apple 캘린더에 들어가 있어요")
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
