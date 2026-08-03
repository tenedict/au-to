import SwiftUI

/// 일정 하나를 자세히 보고 고치는 화면.
///
/// **알림을 눌러 들어오면 여기가 열린다.** 등록은 이미 끝났고, 여기서 하는 일은
/// 확인과 수정이다 — 사람이 최종 판단을 하는 자리는 저장 앞이 아니라 뒤다 (ADR-4).
///
/// 규칙은 이 화면이 갖지 않는다. 무엇이 저장 가능한지, 날짜를 끄면 무엇이 함께
/// 꺼지는지는 `TaskEdit` 이 정하고 테스트가 지킨다 — macOS 와 같은 값을 쓴다.
struct TaskEditorSheet: View {
    let task: AssistantTask
    @ObservedObject var store: TaskStore

    @Environment(\.dismiss) private var dismiss
    @State private var edit: TaskEdit
    @State private var isSaving = false
    @State private var showsDeleteConfirmation = false

    /// 아직 저장된 적 없는 일정인가.
    ///
    /// **따로 넘겨받지 않고 원장에 물어본다.** 화면이 플래그를 들고 다니면
    /// 부르는 자리마다 그 값을 맞춰야 하고, 한 곳이 틀리면 새 일정에 "삭제" 가 뜬다.
    private var isNew: Bool { !store.tasks.contains { $0.id == task.id } }

    init(task: AssistantTask, store: TaskStore) {
        self.task = task
        self.store = store
        _edit = State(initialValue: TaskEdit(task: task, now: .now))
    }

    var body: some View {
        NavigationStack {
            Form {
                warningSection

                Section("할 일") {
                    TextField("무엇을 해야 하나요?", text: $edit.title)
                    TextField("메모", text: $edit.notes, axis: .vertical)
                        .lineLimit(2...6)
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

                remindersSection
                calendarSection
                deleteSection
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
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
                Button("취소", role: .cancel) {}
            } message: {
                Text("캘린더에 넣은 일정도 함께 지워요.")
            }
        }
    }

    private var navigationTitle: String {
        if isNew { return "새 일정" }
        return task.needsReview ? "일정 확인" : "일정 고치기"
    }

    // MARK: - 구역

    /// 왜 확인을 요청받았는지.
    ///
    /// **"등록은 됐다" 를 먼저 말한다.** 경고만 있으면 사용자는 등록이 안 된 줄 알고
    /// 다시 담는다 — 실제로 예전 흐름이 그랬다.
    @ViewBuilder
    private var warningSection: some View {
        if let reason = task.reviewReason {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label("등록은 됐어요", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.water)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(Palette.ink2)
                }
            }
        }
    }

    private var remindersSection: some View {
        Section("알림") {
            Toggle("마감 알림 받기", isOn: $edit.wantsReminders)
                .disabled(!edit.hasDate)
            // 비활성 컨트롤에는 언제나 이유를 함께 보여준다 (CLAUDE 규칙 12).
            if !edit.hasDate {
                Text("알림을 받으려면 날짜를 먼저 정해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if edit.wantsReminders {
                Text(reminderDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let explanation = store.reminderAuthorization.explanation,
               store.reminderAuthorization == .denied, edit.effectiveWantsReminders {
                Label(explanation, systemImage: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(Palette.past)
            }
        }
    }

    private var calendarSection: some View {
        Section("저장 위치") {
            Label(isNew ? "Whenly 할 일에 저장해요" : "Whenly 에는 이미 저장했어요",
                  systemImage: "checklist")
            Toggle("Apple 캘린더에도 추가", isOn: $edit.addToCalendar)
                .disabled(!edit.hasDate)
            if !edit.hasDate {
                Text("캘린더에 추가하려면 날짜를 먼저 정해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 아직 저장되지 않은 일정에는 삭제가 없다. 지울 것이 없기 때문이다 —
    /// 닫기를 누르면 그대로 사라진다.
    @ViewBuilder
    private var deleteSection: some View {
        if !isNew {
            Section {
                Button("이 일정 지우기", role: .destructive) {
                    showsDeleteConfirmation = true
                }
            } footer: {
                Text("캘린더에 넣은 일정도 함께 지워요.")
            }
        }
    }

    // MARK: - 도구 모음

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("닫기") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if isNew {
                Button("추가", action: save)
                    .disabled(!edit.canSave || isSaving)
            } else if task.needsReview, edit == TaskEdit(task: task, now: .now) {
                // 고칠 것이 없으면 저장할 것도 없다. 그 대부분에 "저장" 을 누르게 하면
                // 아무것도 안 바꾸고 저장하는 이상한 동작이 된다.
                Button("확인함") {
                    Task {
                        await store.markReviewed(task.id)
                        dismiss()
                    }
                }
            } else {
                Button("저장", action: save)
                    .disabled(!edit.canSave || isSaving)
            }
        }
    }

    // MARK: - 문구

    /// 사용자가 **언제** 알림을 받게 되는지 그대로 적는다.
    /// "알림을 보내드려요" 는 약속이 아니다.
    private var reminderDescription: String {
        let plans = ReminderSchedule.plans(for: previewTask(), now: .now)
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

    // MARK: - 저장

    /// 저장 경로는 `TaskStore.commit` 하나다. 화면이 캘린더를 직접 부르지 않는다 —
    /// 그러면 iOS 와 macOS 의 연동 규칙이 갈라진다.
    private func save() {
        isSaving = true
        Task {
            await store.commit(edit, to: task)
            dismiss()
        }
    }
}
