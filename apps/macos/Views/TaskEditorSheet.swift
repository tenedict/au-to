import SwiftUI

/// 할 일 하나의 자세한 내용과 고치기.
///
/// **맥에서 무언가를 누르면 여기가 열린다** — 목록의 줄, 캘린더의 일정, 확인이
/// 필요한 초안 전부. 예전에는 캘린더에서 무엇을 눌러도 아무 일도 일어나지 않아서,
/// 사용자는 자기가 잘못 눌렀다고 생각했다.
///
/// 규칙은 이 화면이 갖지 않는다. 무엇이 저장 가능한지, 날짜를 끄면 무엇이 함께
/// 꺼지는지는 `TaskEdit` 이 정하고 테스트가 지킨다 — iOS 와 같은 값을 쓴다.
struct TaskEditorSheet: View {
    let item: EditableItem
    @ObservedObject var store: TaskStore

    @Environment(\.dismiss) private var dismiss
    @State private var edit: TaskEdit
    @State private var isSaving = false
    @State private var showsDeleteConfirmation = false

    init(item: EditableItem, store: TaskStore) {
        self.item = item
        self.store = store
        _edit = State(initialValue: item.makeEdit(now: .now))
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
            Image(systemName: item.isDraft ? "questionmark.circle" : "checklist")
                .font(.title2)
                .foregroundStyle(Palette.water)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.isDraft ? "언제인지 확인해 주세요" : "할 일 고치기")
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

    private var subtitle: String {
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

            evidenceSection
        }
        .formStyle(.grouped)
    }

    /// 분석이 무엇을 근거로 이 초안을 만들었는지.
    /// 사용자가 고칠지 말지를 판단하려면 근거가 함께 보여야 한다.
    @ViewBuilder
    private var evidenceSection: some View {
        if case .draft(let draft) = item {
            if !draft.ambiguities.isEmpty {
                Section("확인이 필요한 부분") {
                    ForEach(draft.ambiguities, id: \.self) { ambiguity in
                        Label(ambiguity, systemImage: "questionmark.circle")
                            .font(.callout)
                    }
                }
            }
            if !draft.evidence.isEmpty {
                Section("분석이 찾은 근거") {
                    ForEach(draft.evidence, id: \.self) { evidence in
                        Label(evidence, systemImage: "quote.opening")
                            .font(.callout)
                            .foregroundStyle(Palette.ink2)
                    }
                }
            }
        }
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

    private func previewTask() -> AssistantTask {
        switch item {
        case .task(let task): return edit.apply(to: task)
        case .draft(let draft): return edit.makeTask(from: draft)
        }
    }

    // MARK: - 바닥

    private var footer: some View {
        HStack(spacing: Space.gap3) {
            if case .task(let task) = item {
                Button("삭제", role: .destructive) { showsDeleteConfirmation = true }
                    .help("할 일과 캘린더 일정을 함께 지워요")
                    .confirmationDialog(
                        "이 할 일을 지울까요?",
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
            if case .draft(let draft) = item {
                Button("버리기", role: .destructive) {
                    store.discard(draft)
                    dismiss()
                }
                .help("할 일로 만들지 않고 담아 둔 스크린샷도 함께 지워요")
            }

            Spacer(minLength: 0)

            Button("닫기") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(item.isDraft ? "등록" : "저장") { save() }
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
            await store.commit(edit, to: item)
            dismiss()
        }
    }
}
