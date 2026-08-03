import Foundation

enum TaskOrigin: String, Codable, Sendable {
    case screenshot
    case manual
}

enum TaskState: String, Codable, Sendable {
    case pending
    case completed
}

/// AI 가 제안한 결과를 사용자 확인 없이 캘린더에 쓰지 않기 위한 문턱값.
///
/// 이 숫자를 여러 곳에 흩어 놓으면 한 곳만 고쳐지고 나머지는 그대로 남는다.
/// 그러면 "확인 없이 캘린더에 쓰지 않는다"는 약속이 경로마다 달라진다.
/// 프로젝트 규칙 4 가 이 상수 밖의 `0.8` 리터럴을 막는다.
enum Confidence {
    /// 이 값 미만이면 자동 캘린더 저장을 제안하지 않는다.
    static let autoCalendarThreshold = 0.80
}

struct AssistantTask: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var hasExplicitTime: Bool
    var state: TaskState
    var origin: TaskOrigin
    var confidence: Double
    var sourceCaptureID: UUID?
    var calendarEventIdentifier: String?
    /// 마감 알림을 보낼지. 저장 시점에 사용자가 정한다.
    ///
    /// 저장 모델에 더하는 새 필드는 옵셔널로 둔다. 기본값이 있어도 이 필드가 없던
    /// 예전 파일은 `keyNotFound` 로 열리지 않고, 사용자는 할 일을 통째로 잃는다.
    /// 읽을 때는 `wantsReminders` 를 쓴다.
    var remindersEnabled: Bool?
    /// 사람이 한 번 봐야 하는 이유. 없으면(`nil`) 볼 것이 없다.
    ///
    /// **등록을 막는 값이 아니다.** 분석이 애매해도 할 일은 언제나 등록된다 —
    /// 막아 두면 사용자는 아무 일도 일어나지 않은 것을 보게 되고, 그게 이 제품이
    /// 없애려던 상태다. 대신 등록한 뒤 "여기를 봐 주세요" 를 이 값으로 들고 있는다.
    ///
    /// 사용자가 확인하면 `nil` 이 된다 (`markReviewed()` · 편집기 저장).
    /// 새 필드이므로 옵셔널이다 — 이유는 위 `remindersEnabled` 와 같다.
    var reviewReason: String?
    let createdAt: Date

    var wantsReminders: Bool { remindersEnabled ?? true }

    /// 아직 사람이 확인하지 않았는가.
    var needsReview: Bool { reviewReason != nil }

    /// 사용자가 확인했다. 되돌릴 일이 없으므로 이유를 지운다.
    mutating func markReviewed() { reviewReason = nil }

    var isCompleted: Bool { state == .completed }

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        hasExplicitTime: Bool = false,
        state: TaskState = .pending,
        origin: TaskOrigin = .manual,
        confidence: Double = 1,
        sourceCaptureID: UUID? = nil,
        calendarEventIdentifier: String? = nil,
        remindersEnabled: Bool? = nil,
        reviewReason: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.hasExplicitTime = dueDate != nil && hasExplicitTime
        self.state = state
        self.origin = origin
        self.confidence = confidence
        self.sourceCaptureID = sourceCaptureID
        self.calendarEventIdentifier = calendarEventIdentifier
        self.remindersEnabled = remindersEnabled
        self.reviewReason = reviewReason
        self.createdAt = createdAt
    }
}

/// 분석기가 돌려주는 한 건.
///
/// **디스크에 남지 않는다.** 예전에는 확인을 기다리는 동안 저장했지만, 지금은
/// 만들어지자마자 `AssistantTask` 가 되므로 기다리는 상태 자체가 없다.
/// `Codable` 은 백엔드 응답을 그대로 받기 위해 남는다.
struct TaskDraft: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var hasExplicitTime: Bool
    var confidence: Double
    var evidence: [String]
    var ambiguities: [String]
    var sourceCaptureID: UUID?
    var createdAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        hasExplicitTime: Bool = false,
        confidence: Double,
        evidence: [String] = [],
        ambiguities: [String] = [],
        sourceCaptureID: UUID? = nil,
        createdAt: Date? = .now
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.hasExplicitTime = dueDate != nil && hasExplicitTime
        self.confidence = confidence
        self.evidence = evidence
        self.ambiguities = ambiguities
        self.sourceCaptureID = sourceCaptureID
        self.createdAt = createdAt
    }

    /// 초안을 할 일로 만든다.
    ///
    /// **애매해도 만든다.** 확인이 필요한 이유는 막는 값이 아니라 붙이는 값이다
    /// (`AssistantTask.reviewReason`). 판정은 `AutoFilePolicy` 가 한다.
    func makeTask(now: Date) -> AssistantTask {
        AssistantTask(
            id: id,
            title: title,
            // 날짜를 못 찾았으면 원문이 유일한 단서다. 메모가 비어 있으면
            // 사용자가 나중에 볼 것이 제목 한 줄뿐이라 고칠 근거가 없다.
            notes: notes,
            dueDate: dueDate,
            hasExplicitTime: hasExplicitTime,
            origin: sourceCaptureID == nil ? .manual : .screenshot,
            confidence: confidence,
            sourceCaptureID: sourceCaptureID,
            reviewReason: AutoFilePolicy.reviewReason(for: self),
            createdAt: now
        )
    }
}
