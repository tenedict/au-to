import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// 기기 안에서만 도는 분석기. Apple Foundation Models 를 쓴다.
///
/// **인식한 글자도 기기를 떠나지 않는다.** 백엔드는 OCR 텍스트를 서버로 보내지만
/// 이건 아무것도 보내지 않는다.
///
/// 비교 분석은 [`docs/17-ONDEVICE-LLM-RESEARCH.md`](../../docs/17-ONDEVICE-LLM-RESEARCH.md).
/// 결론이 이 구현이다 — 모델 다운로드 0MB, 한국어 공식 지원, guided generation 이
/// 우리 스키마를 그대로 강제한다.
///
/// 다만 **iPhone 15 Pro 이상에서만** 돈다. 그래서 "온디바이스로 전환" 이 아니라
/// "온디바이스를 추가" 다. 백엔드는 못 쓰는 기기를 위해 남는다.
struct OnDeviceContextUnderstandingService: ContextUnderstandingService {

    /// 기기가 이걸 쓸 수 있는가. 못 쓰면 **왜** 못 쓰는지 함께 돌려준다.
    ///
    /// 기종 문자열로 판정하지 않는다 — 새 기기가 나올 때마다 고쳐야 하고,
    /// 사용자가 Apple Intelligence 를 꺼 둔 경우를 못 잡는다.
    static var availability: OnDeviceAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable("이 기기에서는 온디바이스 모델을 쓸 수 없어요.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("설정에서 Apple Intelligence를 켜 주세요.")
            case .unavailable(.modelNotReady):
                return .unavailable("모델을 준비하는 중이에요. 잠시 뒤 다시 시도해 주세요.")
            case .unavailable:
                return .unavailable("지금은 온디바이스 모델을 쓸 수 없어요.")
            }
        }
        return .unavailable("iOS 26 이상에서 쓸 수 있어요.")
        #else
        return .unavailable("이 빌드에는 온디바이스 모델이 없어요.")
        #endif
    }

    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { .now }) {
        self.now = now
    }

    func makeDrafts(from text: String, captureID: UUID?) async throws -> [TaskDraft] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ContextUnderstandingError.noTextFound
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await analyze(normalized, captureID: captureID)
        }
        #endif
        throw OnDeviceAnalysisError.unavailable(Self.availability.reason ?? "쓸 수 없어요.")
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private func analyze(_ text: String, captureID: UUID?) async throws -> [TaskDraft] {
        guard case .available = Self.availability else {
            throw OnDeviceAnalysisError.unavailable(Self.availability.reason ?? "쓸 수 없어요.")
        }

        // 백엔드와 **같은 지시문**을 쓴다. 둘이 갈라지면 평가셋으로 비교한 것이
        // 무슨 의미인지 알 수 없게 된다.
        let session = LanguageModelSession(instructions: Self.instructions)

        let formatter = ISO8601DateFormatter()
        let prompt = """
            지금: \(formatter.string(from: now()))
            시간대: \(TimeZone.current.identifier)

            원문:
            \(text)
            """

        let response = try await session.respond(
            to: prompt,
            generating: OnDeviceTaskList.self
        )
        let drafts = response.content.tasks.compactMap { $0.makeDraft(captureID: captureID) }
        guard !drafts.isEmpty else { throw OnDeviceAnalysisError.emptyResult }
        return drafts
    }

    private static let instructions = """
        Role: 텍스트에서 사용자가 실행할 수 있는 할 일을 전부 찾아낸다.
        Goal: 할 일마다 제목, 메모, 마감 날짜/시간, 보수적인 신뢰도와 근거를 만든다.
        Constraints:
        - 원문에 없는 사실을 만들지 않는다.
        - 서로 다른 날짜나 서로 다른 일이면 따로 나눈다.
        - 같은 일을 다르게 표현한 것이면 하나로 합친다.
        - 날짜가 명확하지 않으면 dueDate 는 빈 문자열이다.
        - 연도나 오전/오후가 모호하면 ambiguities 에 적고 confidence 를 낮춘다.
        - ambiguities 는 사용자가 직접 고쳐야 하는 것만 적는다.
        - 날짜가 분명하면 시각이 없어도 ambiguities 에 넣지 않는다. 종일 할 일이다.
        - hasExplicitTime 은 원문에 구체적인 시간이 있을 때만 true 다.
        - 출력 언어는 한국어다.
        """
    #endif
}

/// 온디바이스 모델을 쓸 수 있는지.
enum OnDeviceAvailability: Equatable {
    case available
    case unavailable(String)

    var isAvailable: Bool { self == .available }

    /// 못 쓰면 **왜** 못 쓰는지. 이유 없는 비활성은 고장으로 읽힌다 (CLAUDE 규칙 12).
    var reason: String? {
        if case .unavailable(let why) = self { return why }
        return nil
    }
}

enum OnDeviceAnalysisError: LocalizedError, Equatable {
    case unavailable(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .unavailable(let why):
            return why
        case .emptyResult:
            return "기기에서 할 일을 찾지 못했어요. 백엔드로 바꿔 보세요."
        }
    }
}

#if canImport(FoundationModels)

/// 모델이 채워 주는 모양.
///
/// `@Generable` 이 guided generation 을 켠다 — 모델 출력이 이 타입에 맞도록
/// **제약 디코딩**으로 강제된다. 백엔드에서 `strict` JSON Schema 로 하는 일과 같다.
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct OnDeviceTaskList {
    @Guide(description: "원문에서 찾은 할 일 목록. 서로 다른 날짜면 따로 나눈다.", .count(1...8))
    var tasks: [OnDeviceTask]
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct OnDeviceTask {
    @Guide(description: "사용자가 실행할 수 있는 간결한 한국어 할 일 제목")
    var title: String

    @Guide(description: "판단에 필요한 원문 맥락")
    var notes: String

    /// 옵셔널 대신 빈 문자열을 쓴다 — 작은 모델은 null 을 자주 틀린다.
    @Guide(description: "ISO 8601 날짜와 시각. 모르면 빈 문자열")
    var dueDate: String

    @Guide(description: "원문에 구체적인 시간이 있을 때만 true")
    var hasExplicitTime: Bool

    @Guide(description: "0 부터 1 사이. 확실하지 않으면 낮춘다", .range(0...1))
    var confidence: Double

    @Guide(description: "판단을 뒷받침하는 짧은 원문 구절", .count(0...4))
    var evidence: [String]

    @Guide(description: "사용자가 직접 고쳐야 하는 모호한 점", .count(0...4))
    var ambiguities: [String]

    /// 모델 출력을 우리 계약으로 옮긴다.
    ///
    /// **여기서 한 번 더 검증한다.** guided generation 이 모양은 보장하지만
    /// 날짜가 **사실**이라는 뜻은 아니다 (ADR-6 과 같은 이유).
    func makeDraft(captureID: UUID?) -> TaskDraft? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }

        let parsed = OnDeviceTask.parseDate(dueDate)
        // 날짜 없이 시간만 명시된 것은 앱이 표현할 수 없다.
        let explicit = parsed == nil ? false : hasExplicitTime

        return TaskDraft(
            title: String(cleanTitle.prefix(120)),
            notes: String(notes.prefix(4000)),
            dueDate: parsed,
            hasExplicitTime: explicit,
            confidence: min(max(confidence, 0), 1),
            evidence: Array(evidence.prefix(8)),
            ambiguities: Array(ambiguities.prefix(8)),
            sourceCaptureID: captureID
        )
    }

    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: trimmed) { return date }
        if let date = ISO8601DateFormatter().date(from: trimmed) { return date }

        // 작은 모델은 오프셋을 자주 빠뜨린다. "2026-08-12T15:00:00" 도 받아 준다.
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            local.dateFormat = format
            if let date = local.date(from: trimmed) { return date }
        }
        return nil
    }
}

#endif
