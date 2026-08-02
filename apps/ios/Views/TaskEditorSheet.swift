import SwiftUI

/// 할 일 하나를 자세히 보고 고치는 화면.
///
/// **저장된 할 일과 확인이 필요한 초안이 같은 화면을 쓴다.** 사용자에게는 둘 다
/// "고치는 화면" 하나이고, 나눠 만들면 한쪽에만 있는 항목이 반드시 생긴다 —
/// 실제로 예전에는 초안만 고칠 수 있었고, 한 번 저장한 할 일은 지웠다가
/// 다시 만드는 수밖에 없었다.
///
/// 규칙은 이 화면이 갖지 않는다. 무엇이 저장 가능한지, 날짜를 끄면 무엇이 함께
/// 꺼지는지는 `TaskEdit` 이 정하고 테스트가 지킨다 — macOS 와 같은 값을 쓴다.
struct TaskEditorSheet: View {
    let item: EditableItem
    @ObservedObject var store: TaskStore
    /// 초안을 나중에 보기로 했다. 이번 실행에서는 다시 띄우지 않는다.
    let onDefer: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var edit: TaskEdit
    @State private var isSaving = false
    @State private var showsDiscardConfirmation = false

    init(item: EditableItem, store: TaskStore, onDefer: @escaping () -> Void = {}) {
        self.item = item
        self.store = store
        self.onDefer = onDefer
        _edit = State(initialValue: item.makeEdit(now: .now))
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
                evidenceSections
                deleteSection
            }
            .navigationTitle(item.isDraft ? "할 일 확인" : "할 일 고치기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .confirmationDialog(
                "이 제안을 버릴까요?",
                isPresented: $showsDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("버리기", role: .destructive) {
                    if case .draft(let draft) = item { store.discard(draft) }
                    dismiss()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("담아 둔 스크린샷도 함께 지워요. 할 일은 만들지 않아요.")
            }
        }
    }

    // MARK: - 구역

    /// 왜 확인을 요청받았는지. 이유 없이 "확인해 주세요" 만 있으면
    /// 무엇을 고쳐야 하는지 알 수 없다.
    @ViewBuilder
    private var warningSection: some View {
        if case .draft(let draft) = item,
           case .askFirst(let reason) = AutoFilePolicy.decide(for: draft) {
            Section {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.past)
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
            Label("CaptureTask 할 일에는 항상 저장해요", systemImage: "checklist")
            Toggle("Apple 캘린더에도 추가", isOn: $edit.addToCalendar)
                .disabled(!edit.hasDate)
            if !edit.hasDate {
                Text("캘린더에 추가하려면 날짜를 먼저 정해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var evidenceSections: some View {
        if case .draft(let draft) = item {
            if !draft.evidence.isEmpty {
                Section("분석이 찾은 근거") {
                    ForEach(draft.evidence, id: \.self) { evidence in
                        Label(evidence, systemImage: "quote.opening")
                            .font(.callout)
                    }
                }
            }
            if !draft.ambiguities.isEmpty {
                Section("확인이 필요한 부분") {
                    ForEach(draft.ambiguities, id: \.self) { ambiguity in
                        Label(ambiguity, systemImage: "questionmark.circle")
                            .font(.callout)
                    }
                }
            }
        }
    }

    /// 저장된 할 일만 지울 수 있다. 초안은 "버리기" 가 그 자리를 대신한다 —
    /// 초안을 지우는 것은 담아 둔 스크린샷까지 지우는 다른 일이다.
    @ViewBuilder
    private var deleteSection: some View {
        if case .task(let task) = item {
            Section {
                Button("이 할 일 지우기", role: .destructive) {
                    Task {
                        await store.delete(task.id)
                        dismiss()
                    }
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
            if item.isDraft {
                Menu {
                    Button("나중에 확인") {
                        onDefer()
                        dismiss()
                    }
                    Button("이 제안 버리기", role: .destructive) {
                        showsDiscardConfirmation = true
                    }
                } label: {
                    Text("나중에")
                }
            } else {
                Button("닫기") { dismiss() }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(item.isDraft ? "등록" : "저장", action: save)
                .disabled(!edit.canSave || isSaving)
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

    private func previewTask() -> AssistantTask {
        switch item {
        case .task(let task): return edit.apply(to: task)
        case .draft(let draft): return edit.makeTask(from: draft)
        }
    }

    // MARK: - 저장

    /// 저장 경로는 `TaskStore.commit` 하나다. 화면이 캘린더를 직접 부르지 않는다 —
    /// 그러면 iOS 와 macOS 의 연동 규칙이 갈라진다.
    private func save() {
        isSaving = true
        Task {
            await store.commit(edit, to: item)
            dismiss()
        }
    }
}
