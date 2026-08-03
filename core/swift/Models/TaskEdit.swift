import Foundation

// 한때 여기에 `EditableItem`(할 일 | 초안) 이 있었다. 지웠다 —
// **초안이라는 상태가 사라졌기 때문**이다. 애매한 분석 결과도 곧바로 할 일이 되고,
// 봐야 할 것은 `AssistantTask.reviewReason` 으로 그 할 일에 붙어 다닌다.
// 고칠 수 있는 것은 이제 한 종류뿐이라 감싸는 타입이 필요 없다.

/// 할 일 하나를 고치는 동안의 상태.
///
/// **규칙을 화면에 두지 않는다.** iOS 와 macOS 가 각자 "날짜를 끄면 알림도 꺼진다"
/// 같은 것을 따로 구현하면 반드시 한쪽만 고쳐진다. 둘이 같은 값을 쓰고, 이 파일의
/// 테스트가 그 규칙을 지킨다.
///
/// 고칠 수 있는 것은 `AssistantTask` 한 종류다. 확인이 필요한 것도 이미 할 일이다.
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
}

extension AssistantTask {
    /// 사용자가 **직접** 만들기 시작하는 빈 일정.
    ///
    /// 분석을 거치지 않으므로 확인 표식이 없다 — 사람이 적은 것을 사람에게
    /// 다시 확인시킬 이유가 없다.
    ///
    /// 날짜는 **켜진 채로** 시작한다. 직접 적는 일정은 대부분 날짜가 있고,
    /// 꺼진 채로 시작하면 매번 토글을 먼저 눌러야 한다. 필요 없으면 끄면 된다.
    static func blank(now: Date) -> AssistantTask {
        AssistantTask(title: "", dueDate: now, origin: .manual, createdAt: now)
    }
}
