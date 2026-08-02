import Foundation

/// 고칠 대상.
///
/// 저장된 할 일과 확인을 기다리는 초안이 **같은 화면**을 쓴다. 사용자에게는 둘 다
/// "고치는 화면" 하나이고, 나눠 만들면 한쪽에만 있는 항목이 반드시 생긴다.
enum EditableItem: Identifiable, Equatable, Sendable {
    case task(AssistantTask)
    case draft(TaskDraft)

    var id: UUID {
        switch self {
        case .task(let task): return task.id
        case .draft(let draft): return draft.id
        }
    }

    /// 아직 확인을 기다리는 것인가. 화면이 제목과 저장 문구를 여기서 고른다.
    var isDraft: Bool {
        if case .draft = self { return true }
        return false
    }

    func makeEdit(now: Date) -> TaskEdit {
        switch self {
        case .task(let task): return TaskEdit(task: task, now: now)
        case .draft(let draft): return TaskEdit(draft: draft, now: now)
        }
    }
}

/// 할 일 하나를 고치는 동안의 상태.
///
/// **규칙을 화면에 두지 않는다.** iOS 와 macOS 가 각자 "날짜를 끄면 알림도 꺼진다"
/// 같은 것을 따로 구현하면 반드시 한쪽만 고쳐진다. 둘이 같은 값을 쓰고, 이 파일의
/// 테스트가 그 규칙을 지킨다.
///
/// 초안(`TaskDraft`)과 이미 저장된 할 일(`AssistantTask`)이 같은 편집기를 쓴다 —
/// 사용자에게는 둘 다 "고치는 화면" 하나다.
struct TaskEdit: Equatable, Sendable {
    var title: String
    var notes: String
    /// 날짜를 껐다 켜도 사용자가 고르던 값이 남아 있어야 한다. 그래서 옵셔널이 아니다.
    var dueDate: Date
    var hasDate: Bool
    var hasExplicitTime: Bool
    var wantsReminders: Bool
    var addToCalendar: Bool

    /// 저장된 할 일을 연다.
    ///
    /// 캘린더 토글의 초기값은 **지금 실제로 들어가 있는지**다. 임의로 켜 두면
    /// 사용자가 저장 버튼을 누르는 것만으로 캘린더에 새 일정이 생긴다.
    init(task: AssistantTask, now: Date) {
        self.title = task.title
        self.notes = task.notes
        self.dueDate = task.dueDate ?? now
        self.hasDate = task.dueDate != nil
        self.hasExplicitTime = task.hasExplicitTime
        self.wantsReminders = task.wantsReminders
        self.addToCalendar = task.calendarEventIdentifier != nil
    }

    /// 확인이 필요한 초안을 연다.
    ///
    /// 확인이 필요하다고 판정된 초안은 캘린더 토글을 미리 켜지 않는다 (CLAUDE 규칙 1·2).
    init(draft: TaskDraft, now: Date) {
        self.title = draft.title
        self.notes = draft.notes
        self.dueDate = draft.dueDate ?? now
        self.hasDate = draft.dueDate != nil
        self.hasExplicitTime = draft.hasExplicitTime
        self.wantsReminders = true
        self.addToCalendar = draft.mayPrefillCalendar
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 제목이 없으면 저장할 수 없다. 제목 없는 할 일은 목록에서 아무것도 알려 주지 않는다.
    var canSave: Bool { !trimmedTitle.isEmpty }

    /// 날짜를 끄면 함께 꺼져야 하는 것들.
    ///
    /// 화면이 토글을 비활성으로 만드는 것만으로는 부족하다 — 켜 둔 채 날짜를 끄면
    /// 값은 `true` 로 남아, 나중에 날짜를 다시 켜는 순간 사용자가 정한 적 없는
    /// 캘린더 저장이 일어난다.
    var effectiveWantsReminders: Bool { hasDate && wantsReminders }
    var effectiveAddToCalendar: Bool { hasDate && addToCalendar }

    /// 고친 내용을 기존 할 일에 얹는다. 신원(`id` · 출처 · 캡처)은 건드리지 않는다.
    func apply(to task: AssistantTask) -> AssistantTask {
        var updated = task
        updated.title = trimmedTitle.isEmpty ? task.title : trimmedTitle
        updated.notes = notes
        updated.dueDate = hasDate ? dueDate : nil
        updated.hasExplicitTime = hasDate && hasExplicitTime
        updated.remindersEnabled = effectiveWantsReminders
        return updated
    }

    /// 초안을 할 일로 만든다. 초안의 신원을 그대로 물려받는다 —
    /// 새 `id` 를 만들면 상자에 담긴 캡처와 이어지지 않아 원본이 영영 남는다.
    func makeTask(from draft: TaskDraft) -> AssistantTask {
        AssistantTask(
            id: draft.id,
            title: trimmedTitle.isEmpty ? draft.title : trimmedTitle,
            notes: notes,
            dueDate: hasDate ? dueDate : nil,
            hasExplicitTime: hasDate && hasExplicitTime,
            origin: draft.sourceCaptureID == nil ? .manual : .screenshot,
            confidence: draft.confidence,
            sourceCaptureID: draft.sourceCaptureID,
            remindersEnabled: effectiveWantsReminders
        )
    }
}
