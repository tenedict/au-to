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
    /// 서버가 이 앱에서 온 요청인지 보는 헤더.
    static let clientKeyHeader = "X-Whenly-Key"

    // 한때 옛 이름(`X-CaptureTask-Key`)도 함께 보냈다. 배포된 서버가 아직 옛
    // 빌드였기 때문이다 — 앱만 새 이름을 보내는 순간 401 이 오고, 사용자는 방금
    // 업데이트한 앱에서 "앱을 업데이트해 주세요" 를 본다.
    //
    // 2026-08-03 서버(리비전 00005)가 새 이름을 받는 것을 확인하고 지웠다.
    //
    // **서버 쪽은 지우지 않는다** (`server/src/auth.mjs`). 방향이 반대이기 때문이다 —
    // 기기에 깔린 옛 앱은 우리가 바꿀 수 없지만, 서버는 우리가 언제든 배포한다.
    //   앱이 옛 이름을 보냄    → 서버가 받아 준다 (아직 필요)
    //   서버가 옛 이름을 요구  → 앱은 이미 새 이름을 보낸다 (필요 없음)

    private let endpoint: URL
    private let clientKey: String?
    private let httpClient: any HTTPClient
    private let localeIdentifier: @Sendable () -> String
    private let timezoneIdentifier: @Sendable () -> String
    private let now: @Sendable () -> Date

    init(
        baseURL: URL = BackendConfiguration.baseURL,
        clientKey: String? = BackendConfiguration.clientKey,
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
        self.clientKey = clientKey
        self.httpClient = httpClient
        self.localeIdentifier = localeIdentifier
        self.timezoneIdentifier = timezoneIdentifier
        self.now = now
    }

    func makeDrafts(from text: String, captureID: UUID?) async throws -> [TaskDraft] {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ContextUnderstandingError.noTextFound
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 로컬 백엔드는 키 없이 돕니다. 배포된 서버는 이 헤더가 없으면 401 을 줍니다.
        if let clientKey, !clientKey.isEmpty {
            request.setValue(clientKey, forHTTPHeaderField: Self.clientKeyHeader)
        }
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

        // 하나가 이상하다고 나머지를 버리지 않는다. 서버도 같은 규칙으로 다듬는다.
        let drafts = payload.tasks.compactMap { try? $0.makeDraft(captureID: captureID) }
        guard !drafts.isEmpty else { throw BackendAnalysisError.invalidResponse }
        return drafts
    }

    private func decodeError(from data: Data, statusCode: Int) -> BackendAnalysisError {
        let payload = try? JSONDecoder().decode(BackendErrorEnvelope.self, from: data)
        switch statusCode {
        case 401:
            return .unauthorized(payload?.error.message)
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
    /// 배포된 서버가 요구하는 공유 비밀.
    ///
    /// **이 값은 앱 번들에 들어갑니다.** 뜯으면 나옵니다. 그걸 알고 쓰는 방식이고,
    /// 새는 것이 OpenAI 키가 아니라 이 값이라는 데 의미가 있습니다 — 교체하면 끝입니다.
    /// 진짜로 앱만 통과시키려면 App Attest 가 필요합니다 (SPEC H-3).
    ///
    /// 실제 값은 `Config/Secrets.xcconfig` 에 있고 그 파일은 커밋되지 않습니다.
    /// 비어 있으면 헤더를 붙이지 않습니다 — 로컬 백엔드는 키 없이 돕니다.
    static var clientKey: String? {
        if let value = ProcessInfo.processInfo.environment["WHENLY_CLIENT_KEY"],
           !value.isEmpty {
            return value
        }
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "WHENLY_CLIENT_KEY"
        ) as? String, !value.isEmpty else {
            return nil
        }
        return value
    }

    static var baseURL: URL {
        if let value = ProcessInfo.processInfo.environment["WHENLY_API_BASE_URL"],
           let url = URL(string: value) {
            return url
        }
        if let value = Bundle.main.object(
            forInfoDictionaryKey: "WHENLY_API_BASE_URL"
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
    let tasks: [AnalyzedTask]
}

private struct AnalyzedTask: Decodable {
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
    case unauthorized(String?)
    case rateLimited(String?)
    case requestRejected(String?)
    case serverUnavailable(String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenAI 분석 결과를 이해하지 못했어요. 캡처는 보관했으니 다시 시도해 주세요."
        case .unauthorized:
            // 서버 메시지를 그대로 보여주지 않습니다. 사용자가 고칠 수 있는 것이 아니고,
            // 인증 실패의 세부를 밖으로 흘릴 이유도 없습니다.
            return "이 앱이 분석 서버를 쓸 수 없어요. 앱을 업데이트해 주세요."
        case .rateLimited(let message):
            return message ?? "요청이 많아요. 잠시 후 다시 시도해 주세요."
        case .requestRejected(let message):
            return message ?? "스크린샷 내용을 분석 요청으로 보낼 수 없어요."
        case .serverUnavailable(let message):
            return message ?? "OpenAI 분석 서버에 연결하지 못했어요. 캡처는 보관했어요."
        }
    }
}
