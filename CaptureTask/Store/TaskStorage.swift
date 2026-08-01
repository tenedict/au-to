import Foundation

/// 할 일과 확인 대기 초안의 디스크 저장.
///
/// `try?` 를 쓰지 않는다. 저장·복원 실패를 삼키면 사용자는 잃은 뒤에 알게 된다.
/// 읽지 못한 파일은 지우지 않고 격리한다 — 원본이 남아 있어야 복구를 시도할 수 있다.
struct TaskStorage: Sendable {
    let directory: URL

    static let defaultDirectoryName = "CaptureTask"

    init(directory: URL) {
        self.directory = directory
    }

    /// 앱이 실제로 쓰는 위치. Application Support 를 못 찾는 일은 없지만,
    /// 없으면 임시 폴더로 떨어뜨리는 대신 실패를 알린다.
    static func makeDefault() throws -> TaskStorage {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw TaskStorageError.locationUnavailable
        }
        return TaskStorage(directory: base.appendingPathComponent(defaultDirectoryName))
    }

    // MARK: - 할 일

    func loadTasks() throws -> [AssistantTask] {
        try load([AssistantTask].self, from: tasksURL)
    }

    func saveTasks(_ tasks: [AssistantTask]) throws {
        try write(tasks, to: tasksURL)
    }

    // MARK: - 확인 대기 초안

    func loadDrafts() throws -> [TaskDraft] {
        try load([TaskDraft].self, from: draftsURL)
    }

    func saveDrafts(_ drafts: [TaskDraft]) throws {
        try write(drafts, to: draftsURL)
    }

    // MARK: - 내부

    private var tasksURL: URL { directory.appendingPathComponent("tasks.json") }
    private var draftsURL: URL { directory.appendingPathComponent("drafts.json") }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else {
            // 처음 실행이다. 빈 것과 깨진 것을 구분해야 하므로 여기서만 빈 값을 만든다.
            return try JSONDecoder.captureTask.decode(type, from: Data("[]".utf8))
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TaskStorageError.unreadable(url.lastPathComponent, error)
        }

        do {
            return try JSONDecoder.captureTask.decode(type, from: data)
        } catch {
            let quarantined = try quarantine(url)
            throw TaskStorageError.quarantined(url.lastPathComponent, quarantined.lastPathComponent)
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.captureTask.encode(value)
        // 원자적 쓰기. 중간에 죽어도 반쪽 파일이 남지 않는다.
        try data.write(to: url, options: .atomic)
    }

    /// 읽지 못한 파일을 옆으로 치운다. 지우지 않는 이유는 사용자의 데이터이기 때문이다.
    private func quarantine(_ url: URL) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: .now)
            .replacingOccurrences(of: ":", with: "-")
        let destination = url.deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp).json")
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}

enum TaskStorageError: LocalizedError {
    case locationUnavailable
    case unreadable(String, Error)
    case quarantined(String, String)

    var errorDescription: String? {
        switch self {
        case .locationUnavailable:
            return "저장 위치를 찾지 못했어요. 앱을 다시 설치해야 할 수 있어요."
        case .unreadable(let name, let underlying):
            return "\(name)을(를) 읽지 못했어요. (\(underlying.localizedDescription))"
        case .quarantined(let name, let backup):
            return "\(name)이(가) 손상되어 열지 못했어요. "
                + "원본은 \(backup)으로 옮겨 두었고, 목록은 빈 상태로 시작했어요."
        }
    }
}

/// 저장용 날짜 형식.
///
/// **초 미만까지 적는다.** `ISO8601DateFormatter` 의 기본값은 소수점을 버리는데,
/// 그러면 저장했다 읽은 할 일이 원본과 달라진다. 같은 초에 만든 두 할 일의 순서가
/// 재실행 뒤에 뒤집히고, "왜 순서가 바뀌었지"는 아무도 추적하지 못한다.
enum CaptureTaskDateFormat {
    static let writing: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let readingWithoutFraction = ISO8601DateFormatter()

    /// 읽기는 관대하다 — 소수점이 있든 없든 받는다.
    static func date(from text: String) -> Date? {
        writing.date(from: text) ?? readingWithoutFraction.date(from: text)
    }
}

extension JSONDecoder {
    /// 날짜 전략이 갈라지면 한쪽이 쓴 파일을 다른 쪽이 못 연다.
    ///
    /// 문자열과 숫자를 모두 받는 이유는 R0 초기 빌드가 `Date` 를 기본 전략(숫자)으로
    /// 저장했기 때문이다. 읽기만 관대하게 두면 그때 만든 할 일을 잃지 않는다.
    /// 쓰기는 언제나 소수점을 포함한 ISO 8601 한 가지다.
    static var captureTask: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                guard let date = CaptureTaskDateFormat.date(from: text) else {
                    throw DecodingError.dataCorruptedError(
                        in: container,
                        debugDescription: "ISO 8601 날짜가 아닙니다: \(text)"
                    )
                }
                return date
            }
            return Date(timeIntervalSinceReferenceDate: try container.decode(Double.self))
        }
        return decoder
    }
}

extension JSONEncoder {
    static var captureTask: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(CaptureTaskDateFormat.writing.string(from: date))
        }
        return encoder
    }
}
