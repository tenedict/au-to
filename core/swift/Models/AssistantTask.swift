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
    let createdAt: Date

    var wantsReminders: Bool { remindersEnabled ?? true }

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
        self.createdAt = createdAt
    }
}

/// 사용자 확인을 기다리는 AI 제안.
///
/// `Codable` 인 이유는 확인하지 않은 초안이 앱을 껐다 켜도 남아야 하기 때문이다.
/// 메모리에만 두면 재실행마다 같은 캡처를 다시 OCR 하고 OpenAI 를 다시 부른다 —
/// 사용자에게는 같은 할 일이 두 번 뜨고, 요금은 두 번 나간다.
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

    /// 저장 전에 사람이 날짜를 반드시 짚어야 하는가.
    var needsDateConfirmation: Bool {
        dueDate == nil || confidence < Confidence.autoCalendarThreshold || !ambiguities.isEmpty
    }

    /// 캘린더 자동 추가 토글을 미리 켜 둬도 되는가.
    /// 확인이 필요한 초안은 사용자가 직접 켜야 한다 (AGENTS 규칙 2).
    var mayPrefillCalendar: Bool {
        dueDate != nil && !needsDateConfirmation
    }

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

    func makeTask() -> AssistantTask {
        AssistantTask(
            id: id,
            title: title,
            notes: notes,
            dueDate: dueDate,
            hasExplicitTime: hasExplicitTime,
            origin: sourceCaptureID == nil ? .manual : .screenshot,
            confidence: confidence,
            sourceCaptureID: sourceCaptureID
        )
    }
}
