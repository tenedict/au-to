import Combine
import Foundation

/// 상태 · 영속화 · 유스케이스 조율.
///
/// 화면은 여기만 부른다. 모델은 여기를 모른다.
/// 캡처를 상자에서 지우는 지점(`SharedInbox.complete`)도 여기 하나뿐이다 — 확인이 끝난 뒤에만.
@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [AssistantTask] = []
    @Published private(set) var pendingDrafts: [TaskDraft] = []
    @Published var lastErrorMessage: String?
    @Published private(set) var isImporting = false
    @Published private(set) var inboxAvailability: SharedInbox.Availability = .ready
    @Published private(set) var reminderAuthorization: ReminderAuthorizationState = .notDetermined

    /// 지금 쓰는 분석 엔진. 바꾸면 곧바로 다음 분석부터 적용된다.
    @Published var engine: AnalysisEngine {
        didSet {
            guard engine != oldValue else { return }
            guard engine.isAvailable else {
                engine = oldValue
                return
            }
            understandingService = ContextUnderstanding.make(engine)
            Self.persist(engine, to: defaults)
        }
    }

    private let ocrService: any OCRService
    private var understandingService: any ContextUnderstandingService
    private let reminderScheduler: any TaskReminderScheduling
    private let storage: TaskStorage?
    private let defaults: UserDefaults
    private let now: () -> Date

    private static let engineDefaultsKey = "CaptureTask.analysisEngine"

    init(
        ocrService: any OCRService = VisionOCRService(),
        understandingService: (any ContextUnderstandingService)? = nil,
        reminderScheduler: any TaskReminderScheduling = LocalNotificationService(),
        storage: TaskStorage? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { .now }
    ) {
        let resolved = ContextUnderstanding.defaultEngine(
            stored: Self.storedEngine(in: defaults)
        )
        self.engine = resolved
        self.ocrService = ocrService
        self.understandingService = understandingService ?? ContextUnderstanding.make(resolved)
        self.reminderScheduler = reminderScheduler
        self.defaults = defaults
        self.now = now

        if let storage {
            self.storage = storage
        } else {
            // 저장 위치를 못 잡으면 그 사실을 화면에 말한다. 조용히 메모리 전용으로
            // 돌아가면 사용자는 앱을 껐다 켠 뒤에야 잃은 걸 안다.
            do {
                self.storage = try TaskStorage.makeDefault()
            } catch {
                self.storage = nil
                self.lastErrorMessage = error.localizedDescription
            }
        }
        loadFromDisk()
    }

    // MARK: - 시작과 재진입

    /// 앱이 켜지거나 다시 앞으로 나올 때마다 부른다.
    ///
    /// 공유 시트로 담는 동안 앱은 뒤에 있었을 수 있다. 켜질 때 한 번만 훑으면
    /// 담고 곧바로 돌아온 사용자는 아무것도 보지 못한다.
    func refresh() async {
        inboxAvailability = SharedInbox.availability
        reminderAuthorization = await reminderScheduler.authorizationState()
        // 사용자가 지금 여기 있다. 확인을 재촉하는 알림은 필요 없다.
        CaptureNotice.cancelUnconfirmedDrafts()
        await importPendingCaptures()
        // 알림이 없는 사이 마감이 지났거나 시스템이 예약을 잃었을 수 있다.
        await reminderScheduler.syncAll(tasks, now: now())
    }

    /// 앱을 나갈 때 부른다. 확인 안 한 초안이 남아 있으면 나중에 한 번 더 알린다.
    ///
    /// 담아 두기만 하고 확인하지 않으면 이 제품은 사진첩과 같아진다.
    func scheduleUnconfirmedDraftReminderIfNeeded() {
        CaptureNotice.scheduleUnconfirmedDrafts(count: pendingDrafts.count)
    }

    /// 사용자가 알림을 직접 켰다.
    ///
    /// 첫 저장까지 기다리면 **첫 공유의 확인 알림을 놓친다** — 권한이 없으면
    /// Share Extension 이 건 알림이 조용히 사라지기 때문이다.
    func enableReminders() async {
        _ = await reminderScheduler.requestAuthorizationIfNeeded()
        reminderAuthorization = await reminderScheduler.authorizationState()
        if reminderAuthorization == .authorized {
            await reminderScheduler.syncAll(tasks, now: now())
        }
    }

    // MARK: - 수집

    func importPendingCaptures() async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        let captures: [PendingCapture]
        do {
            captures = try SharedInbox.pendingCaptures()
        } catch SharedInboxError.appGroupUnavailable {
            inboxAvailability = .appGroupUnavailable
            return
        } catch {
            lastErrorMessage = error.localizedDescription
            return
        }

        for capture in captures {
            // 앱이 이 캡처를 손에 쥐었다. "확인해 주세요" 알림은 할 일을 다했다.
            // 전달된 것까지 지우지 않으면 알림 센터에 남아, 이미 처리한 스크린샷을
            // 확인하러 앱을 다시 열게 된다.
            CaptureNotice.clear(captureID: capture.id)

            // 이미 할 일이 된 캡처는 상자에서 치운다. 확인이 끝난 것이므로 안전하다.
            if tasks.contains(where: { $0.sourceCaptureID == capture.id }) {
                try? SharedInbox.complete(capture)
                continue
            }
            // 확인을 기다리는 초안이 이미 있으면 다시 분석하지 않는다.
            // 이 검사가 없으면 앱을 열 때마다 같은 캡처로 OpenAI 를 다시 부른다.
            if pendingDrafts.contains(where: { $0.sourceCaptureID == capture.id }) {
                continue
            }
            await analyze(capture)
        }
    }

    private func analyze(_ capture: PendingCapture) async {
        do {
            let text: String
            if let cached = capture.recognizedText, !cached.isEmpty {
                text = cached
            } else {
                text = try await ocrService.recognizeText(in: try SharedInbox.imageData(for: capture))
                // 분석이 실패해도 인식은 재사용한다.
                try? SharedInbox.cacheRecognizedText(text, for: capture)
            }

            let draft = try await understandingService.makeDraft(from: text, captureID: capture.id)
            appendDraft(draft)
        } catch {
            // 캡처는 상자에 그대로 둔다. 다음에 다시 시도할 수 있어야 한다.
            lastErrorMessage = error.localizedDescription
        }
    }

    /// 앱 안에서 고른 사진을 분석한다.
    ///
    /// 상자를 거치는 이유는 분석 도중 앱이 죽어도 원본이 남게 하기 위해서다.
    /// 상자를 못 쓰면 메모리에서 바로 분석한다 — 사진을 고른 사용자를
    /// App Group 설정 때문에 막아 세우지는 않는다. 대신 그 사실을 화면에 남긴다.
    func importImages(_ images: [Data]) async {
        guard !images.isEmpty, !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        for data in images {
            do {
                await analyze(try SharedInbox.enqueue(imageData: data))
            } catch SharedInboxError.appGroupUnavailable {
                inboxAvailability = .appGroupUnavailable
                await analyzeInMemory(data)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func analyzeInMemory(_ imageData: Data) async {
        do {
            let text = try await ocrService.recognizeText(in: imageData)
            appendDraft(try await understandingService.makeDraft(from: text, captureID: nil))
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func analyzeManualText(_ text: String) async {
        do {
            appendDraft(try await understandingService.makeDraft(from: text, captureID: nil))
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func appendDraft(_ draft: TaskDraft) {
        pendingDrafts.append(draft)
        persistDrafts()
    }

    // MARK: - 확인

    /// 사용자가 확인한 할 일을 저장한다.
    ///
    /// 저장 → 알림 예약 → 캡처 치우기 순서다. 캡처를 먼저 치우면 저장이 실패했을 때
    /// 원본이 사라진 채 할 일도 없는 상태가 된다.
    func save(_ task: AssistantTask) async {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        } else {
            tasks.insert(task, at: 0)
        }
        pendingDrafts.removeAll { $0.id == task.id }
        persistTasks()
        persistDrafts()

        if task.wantsReminders, task.dueDate != nil {
            _ = await reminderScheduler.requestAuthorizationIfNeeded()
            reminderAuthorization = await reminderScheduler.authorizationState()
        }
        await reminderScheduler.reschedule(task, now: now())

        completeCapture(task.sourceCaptureID)
    }

    /// 초안을 버린다. 할 일로 만들지 않고 캡처도 치운다.
    func discard(_ draft: TaskDraft) {
        pendingDrafts.removeAll { $0.id == draft.id }
        persistDrafts()
        completeCapture(draft.sourceCaptureID)
    }

    // MARK: - 목록 조작

    func updateCalendarIdentifier(_ identifier: String, for taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].calendarEventIdentifier = identifier
        persistTasks()
    }

    func toggleCompletion(for taskID: UUID) async {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].state = tasks[index].isCompleted ? .pending : .completed
        persistTasks()
        // 끝낸 일로 다시 울리지 않게, 되돌리면 다시 울리게.
        await reminderScheduler.reschedule(tasks[index], now: now())
    }

    func delete(_ taskID: UUID) async {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let removed = tasks.remove(at: index)
        persistTasks()
        await reminderScheduler.cancel(taskID: removed.id)

        if let eventIdentifier = removed.calendarEventIdentifier {
            await CalendarService().removeFromCalendar(eventIdentifier: eventIdentifier)
        }
    }

    // MARK: - 파생 값
    //
    // 저장하지 않고 매번 계산한다. 저장하면 할 일이 바뀔 때마다 두 곳을 맞춰야 하고,
    // 반드시 한 곳이 뒤처진다.

    func dueGroups(asOf reference: Date? = nil) -> [DueGroup] {
        DueGrouping.groups(for: tasks, now: reference ?? now())
    }

    func tasksByDay() -> [Date: [AssistantTask]] {
        MonthGridBuilder.tasksByDay(tasks)
    }

    // MARK: - 영속화

    private func loadFromDisk() {
        guard let storage else { return }
        do {
            tasks = try storage.loadTasks()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        do {
            pendingDrafts = try storage.loadDrafts()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func persistTasks() {
        guard let storage else { return }
        do {
            try storage.saveTasks(tasks)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func persistDrafts() {
        guard let storage else { return }
        do {
            try storage.saveDrafts(pendingDrafts)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - 엔진 기억

    private static func storedEngine(in defaults: UserDefaults) -> AnalysisEngine? {
        guard let raw = defaults.string(forKey: engineDefaultsKey) else { return nil }
        return AnalysisEngine(rawValue: raw)
    }

    private static func persist(_ engine: AnalysisEngine, to defaults: UserDefaults) {
        defaults.set(engine.rawValue, forKey: engineDefaultsKey)
    }

    private func completeCapture(_ captureID: UUID?) {
        guard let captureID else { return }
        CaptureNotice.clear(captureID: captureID)
        do {
            try SharedInbox.complete(captureID: captureID)
        } catch SharedInboxError.appGroupUnavailable {
            inboxAvailability = .appGroupUnavailable
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
