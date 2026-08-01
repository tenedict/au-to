import SwiftUI

struct TaskReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let draft: TaskDraft
    let onSave: (AssistantTask, UUID?) -> Void
    let onCalendarSaved: (String, UUID) -> Void

    @State private var title: String
    @State private var notes: String
    @State private var dueDate: Date
    @State private var hasDate: Bool
    @State private var hasExplicitTime: Bool
    @State private var addToCalendar: Bool
    @State private var calendarError: String?
    @State private var isSaving = false

    private let calendarService = CalendarService()

    init(
        draft: TaskDraft,
        onSave: @escaping (AssistantTask, UUID?) -> Void,
        onCalendarSaved: @escaping (String, UUID) -> Void
    ) {
        self.draft = draft
        self.onSave = onSave
        self.onCalendarSaved = onCalendarSaved
        _title = State(initialValue: draft.title)
        _notes = State(initialValue: draft.notes)
        _dueDate = State(initialValue: draft.dueDate ?? .now)
        _hasDate = State(initialValue: draft.dueDate != nil)
        _hasExplicitTime = State(initialValue: draft.hasExplicitTime)
        _addToCalendar = State(initialValue: draft.dueDate != nil && !draft.needsDateConfirmation)
    }

    var body: some View {
        NavigationStack {
            Form {
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

                if draft.needsDateConfirmation {
                    Section {
                        Label(
                            "AI가 날짜를 확실히 판단하지 못했어요. 저장 전에 확인해 주세요.",
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                }

                if !draft.evidence.isEmpty {
                    Section("OpenAI가 찾은 근거") {
                        ForEach(draft.evidence, id: \.self) { evidence in
                            Label(evidence, systemImage: "quote.opening")
                        }
                    }
                }

                if !draft.ambiguities.isEmpty {
                    Section("확인이 필요한 부분") {
                        ForEach(draft.ambiguities, id: \.self) { ambiguity in
                            Label(ambiguity, systemImage: "questionmark.circle")
                        }
                    }
                }
            }
            .navigationTitle("할 일 확인")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("나중에") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .alert(
                "캘린더에는 추가하지 못했어요",
                isPresented: Binding(
                    get: { calendarError != nil },
                    set: { if !$0 { calendarError = nil } }
                )
            ) {
                Button("확인", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("\(calendarError ?? "")\n할 일은 CaptureTask에 저장했어요.")
            }
        }
    }

    private func save() {
        isSaving = true
        var task = AssistantTask(
            id: draft.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes,
            dueDate: hasDate ? dueDate : nil,
            hasExplicitTime: hasDate && hasExplicitTime,
            origin: draft.sourceCaptureID == nil ? .manual : .screenshot,
            confidence: draft.confidence,
            sourceCaptureID: draft.sourceCaptureID
        )
        onSave(task, draft.sourceCaptureID)

        guard addToCalendar, hasDate else {
            dismiss()
            return
        }

        Task {
            do {
                let identifier = try await calendarService.addToCalendar(task)
                task.calendarEventIdentifier = identifier
                onCalendarSaved(identifier, task.id)
                dismiss()
            } catch {
                calendarError = error.localizedDescription
                isSaving = false
            }
        }
    }
}
