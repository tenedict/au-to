import Foundation
import XCTest
@testable import CaptureTask

final class BackendContextUnderstandingServiceTests: XCTestCase {
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
                    "title": "치과 방문",
                    "notes": "예약 시간에 방문",
                    "due_at": "2026-08-05T14:00:00+09:00",
                    "has_explicit_time": true,
                    "confidence": 0.94,
                    "evidence": ["8월 5일 오후 2시", "치과"],
                    "ambiguities": [],
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

        let draft = try await service.makeDraft(
            from: "  8월 5일 오후 2시 치과  ",
            captureID: captureID
        )

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
            _ = try await service.makeDraft(from: "테스트", captureID: nil)
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
            _ = try await service.makeDraft(from: "예약", captureID: nil)
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
