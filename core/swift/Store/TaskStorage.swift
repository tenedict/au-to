import Foundation

/// 할 일과 확인 대기 초안의 디스크 저장.
///
/// `try?` 를 쓰지 않는다. 저장·복원 실패를 삼키면 사용자는 잃은 뒤에 알게 된다.
/// 읽지 못한 파일은 지우지 않고 격리한다 — 원본이 남아 있어야 복구를 시도할 수 있다.
struct TaskStorage: Sendable {
    let directory: URL

    static let defaultDirectoryName = "Whenly"

    init(directory: URL) {
        self.directory = directory
    }

    /// 앱이 실제로 쓰는 위치.
    ///
    /// **App Group 안에 둔다.** Share Extension 이 분석까지 끝내고 할 일을 저장하는데,
    /// 확장의 Application Support 는 앱의 것과 다른 상자다. 각자 저장하면 사용자는
    /// 공유로 만든 할 일이 앱에 없는 것을 보게 된다.
    ///
    /// App Group 을 못 쓰면(서명 미설정·시뮬레이터) 앱 전용 저장소로 떨어진다.
    /// 그 경우 확장이 만든 것은 앱에 보이지 않지만, 확장은 분석 전에 캡처를
    /// 상자에 담아 두므로 앱이 나중에 처리한다 — 잃지는 않는다.
    static func makeDefault() throws -> TaskStorage {
        if let shared = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedInbox.appGroupIdentifier
        ) {
            let directory = shared.appendingPathComponent(defaultDirectoryName)
            // `containerURL` 은 **권한이 없어도 경로를 돌려준다.** 서명에 App Group 이
            // 없는 macOS 앱에서도 `~/Library/Group Containers/…` 를 그대로 준다.
            //
            // 그 경로를 그대로 믿으면 샌드박스가 막아 `fileExists` 가 언제나 false 가
            // 되고, 앱은 매번 **첫 실행처럼 보인다** — 저장은 실패하는데 읽기는
            // "아직 아무것도 없네" 로 읽히니 어디에도 빨간불이 뜨지 않는다.
            // 사용자에게는 할 일이 통째로 사라진 것이다. 실제로 macOS 앱이 이 상태였다.
            //
            // 그래서 만들어 보고 정한다. SharedInbox 는 이미 이렇게 하고 있었다.
            if isUsable(directory) {
                // 이전은 여기서 하지 않는다. 실패를 삼킬 자리가 없어야 하기 때문이다 —
                // 부르는 쪽(TaskStore)이 do/catch 로 받아 화면까지 올린다.
                return TaskStorage(directory: directory)
            }
        }

        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw TaskStorageError.locationUnavailable
        }
        let fallback = base.appendingPathComponent(defaultDirectoryName)
        guard isUsable(fallback) else { throw TaskStorageError.locationUnavailable }
        return TaskStorage(directory: fallback)
    }

    /// 이 자리에 실제로 쓸 수 있는가.
    ///
    /// 경로가 그럴듯하게 생겼는지가 아니라 **만들어지는지**를 본다.
    /// 이미 있으면 만들기는 성공으로 끝나므로 한 번 더 확인하지 않아도 된다.
    static func isUsable(_ directory: URL, fileManager: FileManager = .default) -> Bool {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return true
        } catch {
            return false
        }
    }

    /// 앱 이름이 CaptureTask 였을 때 쓰던 폴더 이름.
    ///
    /// 이름을 Whenly 로 바꾸면서 저장 폴더 이름도 함께 바뀌었다. 이 줄이 없으면
    /// 그 빌드를 쓰던 사람은 **할 일이 통째로 사라진 것을 본다** — 파일은 그대로
    /// 있는데 아무도 그 자리를 보지 않을 뿐이다.
    ///
    /// 일괄 치환으로는 절대 지워지면 안 되는 문자열이다. 여기 적힌 "CaptureTask" 는
    /// 제품 이름이 아니라 **디스크에 이미 존재하는 폴더 이름**이다.
    static let legacyDirectoryNames = ["CaptureTask"]

    /// 예전 자리에 있던 것을 지금 자리로 옮긴다.
    ///
    /// 옮겨야 할 자리가 둘이다.
    ///   · 예전 **위치** — Application Support (App Group 으로 옮기기 전)
    ///   · 예전 **이름** — CaptureTask (Whenly 로 바꾸기 전)
    ///
    /// 새 자리에 이미 파일이 있으면 건드리지 않는다 — 옮기다 덮어쓰는 것이 더 나쁘다.
    /// 그래서 옛 후보를 훑되 먼저 찾은 것 하나만 가져온다.
    func adoptLegacyStoreIfNeeded() throws {
        for legacy in legacyCandidates() {
            guard legacy.path != directory.path,
                  FileManager.default.fileExists(atPath: legacy.path) else { continue }

            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            for name in ["tasks.json", "drafts.json"] {
                let from = legacy.appendingPathComponent(name)
                let to = directory.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: from.path),
                      !FileManager.default.fileExists(atPath: to.path) else { continue }
                try FileManager.default.moveItem(at: from, to: to)
            }
        }
    }

    /// 옛 이름과 옛 위치를 곱한 자리 전부. 가까운 것부터 본다.
    private func legacyCandidates() -> [URL] {
        var candidates: [URL] = []
        // 지금과 같은 컨테이너에서 이름만 옛것.
        let container = directory.deletingLastPathComponent()
        candidates += Self.legacyDirectoryNames.map(container.appendingPathComponent)
        // 옛 위치(Application Support) — 이름은 지금 것과 옛것 둘 다.
        if let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first {
            candidates.append(base.appendingPathComponent(Self.defaultDirectoryName))
            candidates += Self.legacyDirectoryNames.map(base.appendingPathComponent)
        }
        return candidates
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
            return try JSONDecoder.whenly.decode(type, from: Data("[]".utf8))
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TaskStorageError.unreadable(url.lastPathComponent, error)
        }

        do {
            return try JSONDecoder.whenly.decode(type, from: data)
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
        let data = try JSONEncoder.whenly.encode(value)
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
enum WhenlyDateFormat {
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
    static var whenly: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                guard let date = WhenlyDateFormat.date(from: text) else {
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
    static var whenly: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(WhenlyDateFormat.writing.string(from: date))
        }
        return encoder
    }
}
