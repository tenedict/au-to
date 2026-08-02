import Foundation
import XCTest
@testable import Whenly

final class BackendContextUnderstandingServiceTests: XCTestCase {

    // MARK: - 클라이언트 인증

    /// 배포한 서버는 이 헤더가 없으면 401 을 줍니다.
    func testSendsClientKeyHeaderWhenConfigured() async throws {
        let httpClient = MockHTTPClient { request in
            XCTAssertEqual(
                request.value(
                    forHTTPHeaderField: BackendContextUnderstandingService.clientKeyHeader
                ),
                "비밀키-충분히-긴-값"
            )
            return try response(status: 200, body: Self.validBody)
        }

        _ = try await makeService(clientKey: "비밀키-충분히-긴-값", httpClient: httpClient)
            .makeDrafts(from: "치과", captureID: nil)
    }

    /// 로컬 백엔드는 키 없이 돕니다. 빈 값을 헤더로 보내면 401 이 됩니다.
    func testOmitsClientKeyHeaderWhenNotConfigured() async throws {
        for key in [String?.none, ""] {
            let httpClient = MockHTTPClient { request in
                XCTAssertNil(
                    request.value(
                        forHTTPHeaderField: BackendContextUnderstandingService.clientKeyHeader
                    )
                )
                return try response(status: 200, body: Self.validBody)
            }

            _ = try await makeService(clientKey: key, httpClient: httpClient)
                .makeDrafts(from: "치과", captureID: nil)
        }
    }

    /// 401 은 사용자가 고칠 수 있는 것이 아닙니다. 서버 메시지를 그대로 보여주지 않고,
    /// "다시 시도하세요" 로 오해하게 만들지도 않습니다.
    func testUnauthorizedIsItsOwnErrorWithASafeMessage() async throws {
        let httpClient = MockHTTPClient { _ in
            try response(
                status: 401,
                body: ["error": ["code": "unauthorized", "message": "이 서버를 쓸 수 없어요."]]
            )
        }
        let service = makeService(clientKey: "틀린키", httpClient: httpClient)

        do {
            _ = try await service.makeDrafts(from: "치과", captureID: nil)
            XCTFail("401 은 던져야 합니다")
        } catch let error as BackendAnalysisError {
            guard case .unauthorized = error else {
                return XCTFail("unauthorized 여야 합니다: \(error)")
            }
            let message = try XCTUnwrap(error.errorDescription)
            XCTAssertTrue(message.contains("업데이트"), message)
            XCTAssertFalse(message.contains("다시 시도"), "재시도를 권하면 안 됩니다: \(message)")
        }
    }

    private static let validBody: [String: Any] = [
        "tasks": [
            [
                "title": "치과 방문",
                "notes": "",
                "due_at": NSNull(),
                "has_explicit_time": false,
                "confidence": 0.5,
                "evidence": [],
                "ambiguities": [],
            ]
        ]
    ]

    private func makeService(
        clientKey: String?,
        httpClient: MockHTTPClient
    ) -> BackendContextUnderstandingService {
        BackendContextUnderstandingService(
            baseURL: URL(string: "https://example.test")!,
            clientKey: clientKey,
            httpClient: httpClient,
            localeIdentifier: { "ko-KR" },
            timezoneIdentifier: { "Asia/Seoul" },
            now: { Date(timeIntervalSince1970: 0) }
        )
    }

    func testMapsBackendResponseToTaskDraft() async throws {
        let captureID = UUID()
        let httpClient = MockHTTPClient { request in
            XCTAssertEqual(request.url?.path, "/v1/analyze-capture")
            XCTAssertEqual(request.httpMethod, "POST")

            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: body) as? [String: String]
            )
            XCTAssertEqual(json["recognized_text"], "8월 5일 오후 2시 치과")
            XCTAssertEqual(json["locale"], "ko-KR")
            XCTAssertEqual(json["timezone"], "Asia/Seoul")

            return try response(
                status: 200,
                body: [
                    "tasks": [
                        [
                            "title": "치과 방문",
                            "notes": "예약 시간에 방문",
                            "due_at": "2026-08-05T14:00:00+09:00",
                            "has_explicit_time": true,
                            "confidence": 0.94,
                            "evidence": ["8월 5일 오후 2시", "치과"],
                            "ambiguities": [],
                        ]
                    ]
                ]
            )
        }
        let service = BackendContextUnderstandingService(
            baseURL: URL(string: "https://example.test")!,
            httpClient: httpClient,
            localeIdentifier: { "ko-KR" },
            timezoneIdentifier: { "Asia/Seoul" },
            now: { Date(timeIntervalSince1970: 0) }
        )

        let drafts = try await service.makeDrafts(
            from: "  8월 5일 오후 2시 치과  ",
            captureID: captureID
        )

        XCTAssertEqual(drafts.count, 1)
        let draft = try XCTUnwrap(drafts.first)
        XCTAssertEqual(draft.title, "치과 방문")
        XCTAssertEqual(draft.sourceCaptureID, captureID)
        XCTAssertTrue(draft.hasExplicitTime)
        XCTAssertEqual(draft.evidence, ["8월 5일 오후 2시", "치과"])
        XCTAssertFalse(draft.needsDateConfirmation)
    }

    func testRateLimitReturnsRecoverableMessage() async {
        let httpClient = MockHTTPClient { _ in
            try response(
                status: 429,
                body: [
                    "error": [
                        "code": "rate_limited",
                        "message": "잠시 후 다시 시도해 주세요.",
                    ],
                ]
            )
        }
        let service = BackendContextUnderstandingService(
            baseURL: URL(string: "https://example.test")!,
            httpClient: httpClient
        )

        do {
            _ = try await service.makeDrafts(from: "테스트", captureID: nil)
            XCTFail("오류가 발생해야 합니다.")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "잠시 후 다시 시도해 주세요."
            )
        }
    }

    func testRejectsExplicitTimeWithoutDate() async {
        let httpClient = MockHTTPClient { _ in
            try response(
                status: 200,
                body: [
                    "title": "예약",
                    "notes": "",
                    "due_at": NSNull(),
                    "has_explicit_time": true,
                    "confidence": 0.5,
                    "evidence": [],
                    "ambiguities": ["날짜 없음"],
                ]
            )
        }
        let service = BackendContextUnderstandingService(
            baseURL: URL(string: "https://example.test")!,
            httpClient: httpClient
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await service.makeDrafts(from: "예약", captureID: nil)
        }
    }
}

private struct MockHTTPClient: HTTPClient {
    let handler: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try handler(request)
    }
}

private func response(
    status: Int,
    body: [String: Any]
) throws -> (Data, HTTPURLResponse) {
    let data = try JSONSerialization.data(withJSONObject: body)
    let response = try XCTUnwrap(
        HTTPURLResponse(
            url: URL(string: "https://example.test/v1/analyze-capture")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
    )
    return (data, response)
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("오류가 발생해야 합니다.", file: file, line: line)
    } catch {}
}
