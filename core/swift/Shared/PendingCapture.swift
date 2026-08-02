import Foundation

struct PendingCapture: Codable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let imageFilename: String
    /// OCR 결과. 한 번 읽은 스크린샷을 다시 읽지 않기 위해 캡처에 붙여 둔다.
    var recognizedText: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        imageFilename: String,
        recognizedText: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.imageFilename = imageFilename
        self.recognizedText = recognizedText
    }
}

/// Share Extension 과 메인 앱이 공유하는 파일 상자.
///
/// 두 프로세스는 메모리를 공유하지 않는다. 담는 쪽(Extension)과 꺼내는 쪽(앱)이
/// 만나는 자리는 App Group 컨테이너의 파일뿐이다.
///
/// **삭제는 사용자가 확인한 뒤에만 한다** (AGENTS 규칙 7). 분석이 실패했다고 지우면
/// 사용자는 공유한 스크린샷을 영영 잃는다. 지우는 지점은 `complete(_:)` 하나뿐이고,
/// 프로젝트 규칙 3 이 저장소 밖에서의 호출을 막는다.
enum SharedInbox {
    /// `Config/*.entitlements` 두 파일과 반드시 같은 값이어야 한다.
    /// 프로젝트 규칙 1 이 세 곳을 대조한다.
    static let appGroupIdentifier = "group.com.example.whenly"

    /// 상자를 쓸 수 있는지. 화면이 "왜 안 되는지" 말할 수 있어야 한다.
    enum Availability: Equatable, Sendable {
        case ready
        case appGroupUnavailable

        var explanation: String? {
            switch self {
            case .ready:
                return nil
            case .appGroupUnavailable:
                return "공유 상자를 열지 못했어요. App Group(\(SharedInbox.appGroupIdentifier)) "
                    + "서명 설정을 확인해 주세요. 텍스트 붙여넣기는 그대로 쓸 수 있어요."
            }
        }
    }

    static var availability: Availability {
        (try? inboxDirectory()) == nil ? .appGroupUnavailable : .ready
    }

    static func enqueue(imageData: Data) throws -> PendingCapture {
        let captureID = UUID()
        let imageFilename = "\(captureID.uuidString).capture"
        let capture = PendingCapture(id: captureID, imageFilename: imageFilename)
        let directory = try inboxDirectory()
        try imageData.write(to: directory.appendingPathComponent(imageFilename), options: .atomic)
        try write(capture, to: directory)
        return capture
    }

    static func pendingCaptures() throws -> [PendingCapture] {
        let directory = try inboxDirectory()
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        let decoder = makeDecoder()

        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(PendingCapture.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func imageData(for capture: PendingCapture) throws -> Data {
        try Data(contentsOf: try inboxDirectory().appendingPathComponent(capture.imageFilename))
    }

    /// OCR 결과를 캡처에 붙여 둔다.
    ///
    /// 초안 만들기가 네트워크에서 실패해도 다음 시도에서 인식을 다시 하지 않게 한다.
    /// OCR 은 수백 밀리초씩 걸리고, 결과는 같은 이미지에 대해 언제나 같다.
    static func cacheRecognizedText(_ text: String, for capture: PendingCapture) throws {
        var updated = capture
        updated.recognizedText = text
        try write(updated, to: try inboxDirectory())
    }

    /// 사용자가 확인(저장 또는 버리기)을 마친 캡처를 상자에서 치운다.
    static func complete(_ capture: PendingCapture) throws {
        let directory = try inboxDirectory()
        let imageURL = directory.appendingPathComponent(capture.imageFilename)
        let metadataURL = directory.appendingPathComponent("\(capture.id.uuidString).json")
        if FileManager.default.fileExists(atPath: imageURL.path) {
            try FileManager.default.removeItem(at: imageURL)
        }
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            try FileManager.default.removeItem(at: metadataURL)
        }
    }

    static func complete(captureID: UUID) throws {
        guard let capture = try pendingCaptures().first(where: { $0.id == captureID }) else {
            return
        }
        try complete(capture)
    }

    private static func write(_ capture: PendingCapture, to directory: URL) throws {
        let data = try makeEncoder().encode(capture)
        try data.write(
            to: directory.appendingPathComponent("\(capture.id.uuidString).json"),
            options: .atomic
        )
    }

    // Extension 타깃은 Store/ 를 포함하지 않으므로 인코더를 여기에 따로 둔다.
    // 두 곳의 날짜 전략이 갈라지면 Extension 이 쓴 파일을 앱이 못 연다.
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func inboxDirectory() throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw SharedInboxError.appGroupUnavailable
        }
        let directory = container.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

enum SharedInboxError: LocalizedError {
    case appGroupUnavailable

    var errorDescription: String? {
        SharedInbox.Availability.appGroupUnavailable.explanation
    }
}
