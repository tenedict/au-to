import Foundation

protocol ContextUnderstandingService: Sendable {
    func makeDraft(from text: String, captureID: UUID?) async throws -> TaskDraft
}

/// API 연결 전에도 전체 제품 흐름을 검증할 수 있는 결정적 분석기입니다.
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
        let detectedDate = detectDate(in: normalized)

        return TaskDraft(
            title: title,
            notes: normalized,
            dueDate: detectedDate?.date,
            hasExplicitTime: detectedDate?.hasExplicitTime ?? false,
            confidence: detectedDate == nil ? 0.55 : 0.82,
            sourceCaptureID: captureID
        )
    }

    private func detectDate(in text: String) -> (date: Date, hasExplicitTime: Bool)? {
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
        return (date, timeMarkers.contains { matchedText.lowercased().contains($0) })
    }
}

enum ContextUnderstandingError: LocalizedError {
    case noTextFound

    var errorDescription: String? {
        "스크린샷에서 할 일로 만들 텍스트를 찾지 못했어요."
    }
}

