import Foundation

protocol ContextUnderstandingService: Sendable {
    func makeDraft(from text: String, captureID: UUID?) async throws -> TaskDraft
}

/// 문맥 분석기를 고르는 **유일한** 지점.
///
/// 구현을 여기 한 곳에서만 고르기 때문에 나중에 온디바이스 모델을 붙일 때
/// 화면·저장소·테스트를 건드리지 않는다. 교체 계획은
/// `docs/10-ARCHITECTURE-SPINE.md` 의 ADR-3 에 있다.
///
/// - `BackendContextUnderstandingService` — 기본. OpenAI 키는 백엔드에만 있다.
/// - `RuleBasedContextUnderstandingService` — 백엔드 없이 전체 흐름을 눌러 볼 때.
/// - (예정) 온디바이스 모델 — 같은 프로토콜을 구현해 여기에 한 줄로 끼운다.
enum ContextUnderstanding {

    /// 고른 엔진에 맞는 구현을 만든다.
    ///
    /// `onDevice` 는 아직 구현이 없다. **조용히 다른 것으로 떨어뜨리지 않고**
    /// 고를 수 없게 막는 쪽을 택했다 (`AnalysisEngine.isAvailable`).
    /// 그래도 여기까지 오면 기본값으로 되돌린다 — 앱이 분석기 없이 뜨는 것보다는 낫다.
    static func make(_ engine: AnalysisEngine) -> any ContextUnderstandingService {
        switch engine {
        case .backend:
            return BackendContextUnderstandingService()
        case .ruleBased:
            return RuleBasedContextUnderstandingService()
        case .onDevice:
            return BackendContextUnderstandingService()
        }
    }

    /// 앱이 처음 뜰 때 쓸 엔진.
    ///
    /// DEBUG 빌드에서 `CAPTURETASK_OFFLINE=1` 이면 규칙 기반으로 시작한다.
    /// 릴리스 빌드에서는 이 분기가 아예 없다.
    static func defaultEngine(
        stored: AnalysisEngine? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AnalysisEngine {
        #if DEBUG
        if environment["CAPTURETASK_OFFLINE"] == "1" {
            return .ruleBased
        }
        #endif
        // 저장된 값이 그 사이 못 쓰게 됐을 수 있다 (예: 온디바이스를 골라 뒀는데 아직 없음).
        guard let stored, stored.isAvailable else { return .default }
        return stored
    }
}

/// API 연결 전에도 전체 제품 흐름을 검증할 수 있는 결정적 분석기입니다.
///
/// 백엔드가 꺼졌을 때 **자동으로** 여기로 떨어지지 않는다. 조용히 품질이 낮은 결과를
/// 내주면 사용자는 AI가 나빠졌다고 생각하고, 우리는 백엔드가 죽은 줄 모른다.
/// 이 구현은 명시적으로 골랐을 때만 쓰인다.
struct RuleBasedContextUnderstandingService: ContextUnderstandingService {

    func makeDraft(from text: String, captureID: UUID?) async throws -> TaskDraft {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ContextUnderstandingError.noTextFound
        }

        let firstLine = normalized
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .first ?? "새 할 일"
        let title = String(firstLine.prefix(80))
        let detected = detectDate(in: normalized)

        return TaskDraft(
            title: title,
            notes: normalized,
            dueDate: detected?.date,
            hasExplicitTime: detected?.hasExplicitTime ?? false,
            // 규칙 기반은 문맥을 모른다. 임계값을 넘지 않게 두어 캘린더 자동 추가를 막는다.
            confidence: detected == nil ? 0.55 : 0.70,
            evidence: detected.map { [$0.matchedText] } ?? [],
            ambiguities: ["규칙 기반 분석 결과예요. 날짜와 제목을 확인해 주세요."],
            sourceCaptureID: captureID
        )
    }

    private func detectDate(
        in text: String
    ) -> (date: Date, hasExplicitTime: Bool, matchedText: String)? {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.date.rawValue
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range),
              let date = match.date,
              let swiftRange = Range(match.range, in: text) else {
            return nil
        }
        let matchedText = String(text[swiftRange])
        let timeMarkers = [":", "시", "am", "pm", "오전", "오후"]
        let lowered = matchedText.lowercased()
        return (date, timeMarkers.contains { lowered.contains($0) }, matchedText)
    }
}

enum ContextUnderstandingError: LocalizedError {
    case noTextFound

    var errorDescription: String? {
        "스크린샷에서 할 일로 만들 텍스트를 찾지 못했어요."
    }
}
