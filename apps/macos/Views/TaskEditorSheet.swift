import SwiftUI

/// 할 일 하나의 자세한 내용과 고치기.
///
/// **맥에서 무언가를 누르면 여기가 열린다** — 목록의 줄, 캘린더의 일정, 확인이
/// 필요한 초안 전부. 예전에는 캘린더에서 무엇을 눌러도 아무 일도 일어나지 않아서,
/// 사용자는 자기가 잘못 눌렀다고 생각했다.
///
/// 규칙은 이 화면이 갖지 않는다. 무엇이 저장 가능한지, 날짜를 끄면 무엇이 함께
/// 꺼지는지는 `TaskEdit` 이 정하고 테스트가 지킨다 — iOS 와 같은 값을 쓴다.
///
/// **여기서 저장하면 "확인했다" 로 본다.** 사용자가 값을 눈으로 보고 저장을
/// 눌렀으므로 그보다 확실한 확인은 없다.
struct TaskEditorSheet: View {
    let task: AssistantTask
    @ObservedObject var store: TaskStore

    @Environment(\.dismiss) private var dismiss
    @State private var edit: TaskEdit
    @State private var isSaving = false
    @State private var showsDeleteConfirmation = false

    /// 아직 저장된 적 없는 일정인가. 플래그를 들고 다니지 않고 원장에 물어본다.
    private var isNew: Bool { !store.tasks.contains { $0.id == task.id } }

    init(task: AssistantTask, store: TaskStore) {
        self.task = task
        self.store = store
        _edit = State(initialValue: TaskEdit(task: task, now: .now))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: 460)
        .frame(minHeight: 460)
    }

    // MARK: - 머리글

    private var header: some View {
        HStack(spacing: Space.gap3) {
            Image(systemName: headerSymbol)
                .font(.title2)
                .foregroundStyle(Palette.water)
            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.gap5)
        .padding(.vertical, Space.gap4)
    }

    private var headerSymbol: String {
        if isNew { return "square.and.pencil" }
        return task.needsReview ? "questionmark.circle" : "checklist"
    }

    private var headerTitle: String {
        if isNew { return "새 일정" }
        return task.needsReview ? "한 번 확인해 주세요" : "일정 고치기"
    }

    private var subtitle: String {
        // 확인이 필요하면 그 이유를 먼저 말한다. 무엇을 봐야 하는지 모르면
        // 사용자는 이 화면에서 할 일이 없다.
        if let reason = task.reviewReason { return reason }
        guard edit.hasDate else { return "날짜를 정하면 알림과 캘린더를 쓸 수 있어요" }
        return DueDateText.string(
            for: edit.dueDate,
            hasExplicitTime: edit.hasExplicitTime,
            width: .full,
            now: .now)
    }

    // MARK: - 본문

    private var form: some View {
        Form {
            Section("할 일") {
                TextField("무엇을 해야 하나요?", text: $edit.title)
                TextField("메모", text: $edit.notes, axis: .vertical)
                    .lineLimit(2...5)
            }

            Section("날짜") {
                Toggle("날짜 있음", isOn: $edit.hasDate)
                if edit.hasDate {
                    Toggle("시간까지 지정", isOn: $edit.hasExplicitTime)
                    DatePicker(
                        "언제",
                        selection: $edit.dueDate,
                        displayedComponents: edit.hasExplicitTime
                            ? [.date, .hourAndMinute] : [.date])
                }
            }

            Section("알림과 캘린더") {
                Toggle("마감 알림 받기", isOn: $edit.wantsReminders)
                    .disabled(!edit.hasDate)
                Toggle("Apple 캘린더에도 넣기", isOn: $edit.addToCalendar)
                    .disabled(!edit.hasDate)
                // 비활성 컨트롤에는 언제나 이유를 함께 보여준다 (CLAUDE 규칙 12).
                if !edit.hasDate {
                    Text("날짜를 먼저 정해 주세요.")
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                } else if edit.wantsReminders {
                    Text(reminderDescription)
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                }
            }

        }
        .formStyle(.grouped)
    }

    /// 사용자가 **언제** 알림을 받게 되는지 그대로 적는다.
    /// "알림을 보내드려요" 는 약속이 아니다.
    private var reminderDescription: String {
        let preview = previewTask()
        let plans = ReminderSchedule.plans(for: preview, now: .now)
        guard !plans.isEmpty else {
            return "알림을 걸 시각이 이미 지났어요. 이번에는 알림이 오지 않아요."
        }
        return plans
            .map {
                DueDateText.string(
                    for: $0.fireAt, hasExplicitTime: true, width: .medium, now: .now)
            }
            .joined(separator: " · ") + "에 알려드려요."
    }

    private func previewTask() -> AssistantTask { edit.apply(to: task) }

    // MARK: - 바닥

    private var footer: some View {
        HStack(spacing: Space.gap3) {
            if !isNew {
                Button("삭제", role: .destructive) { showsDeleteConfirmation = true }
                    .help("일정과 캘린더 이벤트를 함께 지워요")
                .confirmationDialog(
                    "이 일정을 지울까요?",
                    isPresented: $showsDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("지우기", role: .destructive) {
                        Task {
                            await store.delete(task.id)
                            dismiss()
                        }
                    }
                    Button("그대로 두기", role: .cancel) {}
                } message: {
                    Text("캘린더에 넣은 일정도 함께 지워요.")
                }
            }

            // 고칠 것이 없을 때 빠져나가는 길. 대부분의 확인이 여기로 끝난다.
            if task.needsReview {
                Button("이대로 확인함") {
                    Task {
                        await store.markReviewed(task.id)
                        dismiss()
                    }
                }
            }

            Spacer(minLength: 0)

            Button("닫기") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isNew ? "추가" : "저장") { save() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!edit.canSave || isSaving)
            if !edit.canSave {
                Text("제목을 적어 주세요.")
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
            }
        }
        .padding(.horizontal, Space.gap5)
        .padding(.vertical, Space.gap3)
    }

    private func save() {
        isSaving = true
        Task {
            await store.commit(edit, to: task)
            dismiss()
        }
    }
}
