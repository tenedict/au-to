import Foundation

struct PendingCapture: Codable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let imageFilename: String
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

enum SharedInbox {
    static let appGroupIdentifier = "group.com.example.capturetask"

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
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(PendingCapture.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func imageData(for capture: PendingCapture) throws -> Data {
        try Data(contentsOf: try inboxDirectory().appendingPathComponent(capture.imageFilename))
    }

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

    private static func write(_ capture: PendingCapture, to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(capture)
        try data.write(
            to: directory.appendingPathComponent("\(capture.id.uuidString).json"),
            options: .atomic
        )
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
        "App Group을 사용할 수 없어요. 서명 설정과 그룹 식별자를 확인해 주세요."
    }
}

