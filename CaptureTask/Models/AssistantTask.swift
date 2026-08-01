import Foundation

enum TaskOrigin: String, Codable, Sendable {
    case screenshot
    case manual
}

enum TaskState: String, Codable, Sendable {
    case pending
    case completed
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
    let createdAt: Date

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
        self.createdAt = createdAt
    }
}

struct TaskDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var hasExplicitTime: Bool
    var confidence: Double
    var evidence: [String]
    var ambiguities: [String]
    var sourceCaptureID: UUID?

    var needsDateConfirmation: Bool {
        dueDate == nil || confidence < 0.80 || !ambiguities.isEmpty
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
        sourceCaptureID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.hasExplicitTime = hasExplicitTime
        self.confidence = confidence
        self.evidence = evidence
        self.ambiguities = ambiguities
        self.sourceCaptureID = sourceCaptureID
    }

    func makeTask() -> AssistantTask {
        AssistantTask(
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
