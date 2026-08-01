import Foundation

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendAnalysisError.invalidResponse
        }
        return (data, httpResponse)
    }
}

struct BackendContextUnderstandingService: ContextUnderstandingService {
    private let endpoint: URL
    private let httpClient: any HTTPClient
    private let localeIdentifier: @Sendable () -> String
    private let timezoneIdentifier: @Sendable () -> String
    private let now: @Sendable () -> Date

    init(
        baseURL: URL = BackendConfiguration.baseURL,
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        localeIdentifier: @escaping @Sendable () -> String = {
            Locale.current.identifier
        },
        timezoneIdentifier: @escaping @Sendable () -> String = {
            TimeZone.current.identifier
        },
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.endpoint = baseURL.appendingPathComponent("v1/analyze-capture")
        self.httpClient = httpClient
        self.localeIdentifier = localeIdentifier
        self.timezoneIdentifier = timezoneIdentifier
        self.now = now
    }

    func makeDraft(from text: String, captureID: UUID?) async throws -> TaskDraft {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ContextUnderstandingError.noTextFound
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            AnalyzeCaptureRequest(
                recognizedText: normalized,
                locale: localeIdentifier(),
                timezone: timezoneIdentifier(),
                now: ISO8601DateFormatter().string(from: now())
            )
        )

        let (data, response) = try await httpClient.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw decodeError(from: data, statusCode: response.statusCode)
        }

        let payload: AnalyzeCaptureResponse
        do {
            payload = try JSONDecoder().decode(AnalyzeCaptureResponse.self, from: data)
        } catch {
            throw BackendAnalysisError.invalidResponse
        }
        return try payload.makeDraft(captureID: captureID)
    }

    private func decodeError(from data: Data, statusCode: Int) -> BackendAnalysisError {
        let payload = try? JSONDecoder().decode(BackendErrorEnvelope.self, from: data)
        switch statusCode {
        case 429:
            return .rateLimited(payload?.error.message)
        case 400..<500:
            return .requestRejected(payload?.error.message)
        default:
            return .serverUnavailable(payload?.error.message)
        }
    }
}

enum BackendConfiguration {
    static var baseURL: URL {
        if let value = ProcessInfo.processInfo.environment["CAPTURETASK_API_BASE_URL"],
           let url = URL(string: value) {
            return url
        }
        if let value = Bundle.main.object(
            forInfoDictionaryKey: "CAPTURETASK_API_BASE_URL"
        ) as? String,
           !value.isEmpty,
           let url = URL(string: value) {
            return url
        }
        return URL(string: "http://127.0.0.1:8787")!
    }
}

private struct AnalyzeCaptureRequest: Encodable {
    let recognizedText: String
    let locale: String
    let timezone: String
    let now: String

    enum CodingKeys: String, CodingKey {
        case recognizedText = "recognized_text"
        case locale
        case timezone
        case now
    }
}

private struct AnalyzeCaptureResponse: Decodable {
    let title: String
    let notes: String
    let dueAt: String?
    let hasExplicitTime: Bool
    let confidence: Double
    let evidence: [String]
    let ambiguities: [String]

    enum CodingKeys: String, CodingKey {
        case title
        case notes
        case dueAt = "due_at"
        case hasExplicitTime = "has_explicit_time"
        case confidence
        case evidence
        case ambiguities
    }

    func makeDraft(captureID: UUID?) throws -> TaskDraft {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty, (0...1).contains(confidence) else {
            throw BackendAnalysisError.invalidResponse
        }

        let dueDate: Date?
        if let dueAt {
            guard let parsed = ISO8601DateParser.date(from: dueAt) else {
                throw BackendAnalysisError.invalidResponse
            }
            dueDate = parsed
        } else {
            dueDate = nil
        }
        guard dueDate != nil || !hasExplicitTime else {
            throw BackendAnalysisError.invalidResponse
        }

        return TaskDraft(
            title: normalizedTitle,
            notes: notes,
            dueDate: dueDate,
            hasExplicitTime: hasExplicitTime,
            confidence: confidence,
            evidence: evidence,
            ambiguities: ambiguities,
            sourceCaptureID: captureID
        )
    }
}

private enum ISO8601DateParser {
    static func date(from string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

private struct BackendErrorEnvelope: Decodable {
    let error: BackendErrorPayload
}

private struct BackendErrorPayload: Decodable {
    let code: String
    let message: String
}

enum BackendAnalysisError: LocalizedError, Equatable {
    case invalidResponse
    case rateLimited(String?)
    case requestRejected(String?)
    case serverUnavailable(String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenAI 분석 결과를 이해하지 못했어요. 캡처는 보관했으니 다시 시도해 주세요."
        case .rateLimited(let message):
            return message ?? "요청이 많아요. 잠시 후 다시 시도해 주세요."
        case .requestRejected(let message):
            return message ?? "스크린샷 내용을 분석 요청으로 보낼 수 없어요."
        case .serverUnavailable(let message):
            return message ?? "OpenAI 분석 서버에 연결하지 못했어요. 캡처는 보관했어요."
        }
    }
}
