import SwiftUI

/// AI 제안을 사람이 확인하는 화면.
///
/// **여기를 지나지 않고 저장되는 경로는 없다** (AGENTS 규칙 1).
/// 신뢰도가 낮거나 모호한 점이 있으면 캘린더 토글을 미리 켜 주지 않는다 — 규칙 2.
struct TaskReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let draft: TaskDraft
    let reminderAuthorization: ReminderAuthorizationState
    let onSave: (AssistantTask) -> Void
    let onDiscard: () -> Void
    let onDefer: () -> Void
    let onCalendarSaved: (String, UUID) -> Void

    @State private var title: String
    @State private var notes: String
    @State private var dueDate: Date
    @State private var hasDate: Bool
    @State private var hasExplicitTime: Bool
    @State private var addToCalendar: Bool
    @State private var wantsReminders: Bool
    @State private var calendarError: String?
    @State private var isSaving = false
    @State private var showsDiscardConfirmation = false

    private let calendarService = CalendarService()

    init(
        draft: TaskDraft,
        reminderAuthorization: ReminderAuthorizationState,
        onSave: @escaping (AssistantTask) -> Void,
        onDiscard: @escaping () -> Void,
        onDefer: @escaping () -> Void,
        onCalendarSaved: @escaping (String, UUID) -> Void
    ) {
        self.draft = draft
        self.reminderAuthorization = reminderAuthorization
        self.onSave = onSave
        self.onDiscard = onDiscard
        self.onDefer = onDefer
        self.onCalendarSaved = onCalendarSaved
        _title = State(initialValue: draft.title)
        _notes = State(initialValue: draft.notes)
        _dueDate = State(initialValue: draft.dueDate ?? .now)
        _hasDate = State(initialValue: draft.dueDate != nil)
        _hasExplicitTime = State(initialValue: draft.hasExplicitTime)
        _addToCalendar = State(initialValue: draft.mayPrefillCalendar)
        _wantsReminders = State(initialValue: true)
    }

    var body: some View {
        NavigationStack {
            Form {
                if draft.needsDateConfirmation {
                    Section {
                        Label(
                            "AI가 날짜를 확실히 판단하지 못했어요. 저장 전에 확인해 주세요.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }

                Section("할 일") {
                    TextField("무엇을 해야 하나요?", text: $title)
                    TextField("메모", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("날짜") {
                    Toggle("날짜 있음", isOn: $hasDate)
                    if hasDate {
                        Toggle("시간까지 지정", isOn: $hasExplicitTime)
                        DatePicker(
                            "언제",
                            selection: $dueDate,
                            displayedComponents: hasExplicitTime ? [.date, .hourAndMinute] : [.date]
                        )
                    }
                }

                remindersSection
                calendarSection
                evidenceSections
            }
            .navigationTitle("할 일 확인")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save)
                        .disabled(trimmedTitle.isEmpty || isSaving)
                }
            }
            .confirmationDialog(
                "이 제안을 버릴까요?",
                isPresented: $showsDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("버리기", role: .destructive) {
                    onDiscard()
                    dismiss()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("담아 둔 스크린샷도 함께 지워요. 할 일은 만들지 않아요.")
            }
            .alert(
                "캘린더에는 추가하지 못했어요",
                isPresented: Binding(
                    get: { calendarError != nil },
                    set: { if !$0 { calendarError = nil } }
                )
            ) {
                Button("확인", role: .cancel) { dismiss() }
            } message: {
                Text("\(calendarError ?? "")\n할 일은 CaptureTask에 저장했어요.")
            }
        }
    }

    // MARK: - 구역

    private var remindersSection: some View {
        Section("알림") {
            Toggle("마감 알림 받기", isOn: $wantsReminders)
                .disabled(!hasDate)
            // 비활성 컨트롤에는 언제나 이유를 함께 보여준다 (AGENTS 규칙 9).
            if !hasDate {
                Text("알림을 받으려면 날짜를 먼저 정해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if wantsReminders {
                Text(reminderScheduleDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let explanation = reminderAuthorization.explanation,
               reminderAuthorization == .denied, wantsReminders, hasDate {
                Label(explanation, systemImage: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var calendarSection: some View {
        Section("저장 위치") {
            Label("CaptureTask 할 일에는 항상 저장해요", systemImage: "checklist")
            Toggle("Apple 캘린더에도 추가", isOn: $addToCalendar)
                .disabled(!hasDate)
            if !hasDate {
                Text("캘린더에 추가하려면 날짜를 먼저 정해 주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var evidenceSections: some View {
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

    // MARK: - 문구

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 사용자가 언제 알림을 받게 되는지 그대로 적는다. "알림을 보내드려요" 는 약속이 아니다.
    private var reminderScheduleDescription: String {
        let plans = ReminderSchedule.plans(for: makeTask(), now: .now)
        guard !plans.isEmpty else {
            return "알림을 걸 시각이 이미 지났어요. 이번에는 알림이 오지 않아요."
        }
        return plans
            .map { $0.fireAt.formatted(date: .abbreviated, time: .shortened) }
            .joined(separator: " · ") + "에 알려드려요."
    }

    // MARK: - 저장

    private func makeTask() -> AssistantTask {
        AssistantTask(
            id: draft.id,
            title: trimmedTitle.isEmpty ? draft.title : trimmedTitle,
            notes: notes,
            dueDate: hasDate ? dueDate : nil,
            hasExplicitTime: hasDate && hasExplicitTime,
            origin: draft.sourceCaptureID == nil ? .manual : .screenshot,
            confidence: draft.confidence,
            sourceCaptureID: draft.sourceCaptureID,
            remindersEnabled: hasDate && wantsReminders
        )
    }

    private func save() {
        isSaving = true
        let task = makeTask()
        // 할 일 저장이 먼저다. 캘린더가 실패해도 사용자는 확인한 것을 잃지 않는다.
        onSave(task)

        guard addToCalendar, hasDate else {
            dismiss()
            return
        }

        Task {
            do {
                let identifier = try await calendarService.addToCalendar(task)
                onCalendarSaved(identifier, task.id)
                dismiss()
            } catch {
                calendarError = error.localizedDescription
                isSaving = false
            }
        }
    }
}
