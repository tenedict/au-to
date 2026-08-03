import Combine
import Foundation
import WidgetKit

/// 상태 · 영속화 · 유스케이스 조율.
///
/// 화면은 여기만 부른다. 모델은 여기를 모른다.
/// 캡처를 상자에서 지우는 지점(`SharedInbox.complete`)도 여기 하나뿐이다 — 확인이 끝난 뒤에만.
@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [AssistantTask] = []
    @Published var lastErrorMessage: String?
    @Published private(set) var isImporting = false
    @Published private(set) var inboxAvailability: SharedInbox.Availability = .ready
    @Published private(set) var reminderAuthorization: ReminderAuthorizationState = .notDetermined

    /// 지금 쓰는 분석 엔진. 바꾸면 곧바로 다음 분석부터 적용된다.
    @Published var engine: AnalysisEngine {
        didSet {
            guard engine != oldValue else { return }
            guard ContextUnderstanding.isAvailable(engine) else {
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
    /// 캘린더 어댑터. 주입받는 이유는 `CalendarWriting` 주석에 있다 —
    /// 직접 만들면 단위 테스트가 EventKit 권한 요청에서 몇 분씩 멈춘다.
    private let calendarService: any CalendarWriting
    private let storage: TaskStorage?
    private let defaults: UserDefaults
    private let now: () -> Date

    private static let engineDefaultsKey = "Whenly.analysisEngine"

    init(
        ocrService: any OCRService = VisionOCRService(),
        understandingService: (any ContextUnderstandingService)? = nil,
        reminderScheduler: any TaskReminderScheduling = LocalNotificationService(),
        calendarService: (any CalendarWriting)? = nil,
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
        self.calendarService = calendarService ?? CalendarService()
        self.defaults = defaults
        self.now = now

        if let storage {
            self.storage = storage
        } else {
            // 저장 위치를 못 잡으면 그 사실을 화면에 말한다. 조용히 메모리 전용으로
            // 돌아가면 사용자는 앱을 껐다 켠 뒤에야 잃은 걸 안다.
            do {
                let resolved = try TaskStorage.makeDefault()
                self.storage = resolved
                // 저장 위치를 App Group 으로 옮겼다. 예전 자리에 남은 것을 가져온다.
                // 실패를 삼키면 사용자는 할 일이 통째로 사라진 것으로 본다.
                do {
                    try resolved.adoptLegacyStoreIfNeeded()
                } catch {
                    self.lastErrorMessage =
                        "예전 위치의 할 일을 옮기지 못했어요. (\(error.localizedDescription))"
                }
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
        await importPendingCaptures()
        // 알림이 없는 사이 마감이 지났거나 시스템이 예약을 잃었을 수 있다.
        await reminderScheduler.syncAll(tasks, now: now())
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

            let drafts = try await understandingService.makeDrafts(from: text, captureID: capture.id)
            for draft in drafts { await file(draft) }
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
            let drafts = try await understandingService.makeDrafts(from: text, captureID: nil)
            for draft in drafts { await file(draft) }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// 이미지 한 장을 읽어 찾은 **모든** 일정을 처리한 결과.
    ///
    /// 알리는 쪽(`CaptureQueue`)이 "무엇을 등록했고 무엇이 남았는지"를 한 번에
    /// 말할 수 있어야 한다. 등록한 것만 돌려주면 확인이 필요한 것은 조용히 사라지고,
    /// 사용자에게는 담기가 통째로 실패한 것으로 보인다.
    struct IntakeResult: Sendable {
        /// 등록한 것 전부. 애매했던 것도 여기 들어온다 — 등록을 막지 않기 때문이다.
        var filed: [FiledCapture] = []
        var errorMessage: String?

        /// 그중 사람이 봐야 하는 것.
        var needingReview: [FiledCapture] { filed.filter(\.needsReview) }

        var isEmpty: Bool { filed.isEmpty }
    }

    /// 이미지 한 장을 받아 **확인 화면 없이** 할 일과 캘린더까지 넣는다.
    ///
    /// 맥 물방울과 iOS 공유 시트가 함께 쓰는 주 경로다.
    /// **애매해도 등록한다** — 막아 두면 사용자는 아무 일도 일어나지 않은 것을 본다.
    /// 봐야 할 것은 등록한 뒤 표식으로 남는다 (`AutoFilePolicy`).
    /// **화면을 띄우지 않는다.** 알리는 것은 부르는 쪽의 일이다.
    @discardableResult
    func intake(_ imageData: Data, captureID: UUID? = nil) async -> IntakeResult {
        isImporting = true
        defer { isImporting = false }

        var result = IntakeResult()
        do {
            let text = try await ocrService.recognizeText(in: imageData)
            let drafts = try await understandingService.makeDrafts(from: text, captureID: captureID)
            for draft in drafts {
                if let one = await file(draft) { result.filed.append(one) }
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            result.errorMessage = error.localizedDescription
        }
        return result
    }

    /// 초안 하나를 **언제나** 할 일로 만든다.
    ///
    /// 캘린더만은 확인이 필요 없을 때에 한한다 — 할 일은 우리 원장이라 되돌리기
    /// 쉽지만, 캘린더는 밖으로 나가는 출력이라 잘못 들어간 일정의 무게가 다르다.
    @discardableResult
    func file(_ draft: TaskDraft) async -> FiledCapture? {
        var task = draft.makeTask(now: now())
        var eventIdentifier: String?

        if AutoFilePolicy.mayAutoAddToCalendar(draft) {
            do {
                eventIdentifier = try await calendarService.addToCalendar(task)
                task.calendarEventIdentifier = eventIdentifier
            } catch {
                // 캘린더가 실패해도 할 일은 남긴다. 캘린더는 출력이지 원장이 아니다 (ADR-7).
                lastErrorMessage = error.localizedDescription
            }
        }

        await save(task)

        return FiledCapture(
            id: task.id,
            title: task.title,
            dueDate: task.dueDate,
            hasExplicitTime: task.hasExplicitTime,
            calendarEventIdentifier: eventIdentifier,
            reviewReason: task.reviewReason,
            filedAt: now()
        )
    }

    /// 붙여 넣은 텍스트도 같은 길을 지난다. 여기만 확인을 거치면
    /// "왜 이건 바로 등록되고 저건 안 되지" 를 사용자가 설명할 수 없다.
    @discardableResult
    func analyzeManualText(_ text: String) async -> [FiledCapture] {
        do {
            let drafts = try await understandingService.makeDrafts(from: text, captureID: nil)
            var filed: [FiledCapture] = []
            for draft in drafts {
                if let one = await file(draft) { filed.append(one) }
            }
            return filed
        } catch {
            lastErrorMessage = error.localizedDescription
            return []
        }
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
        persistTasks()

        if task.wantsReminders, task.dueDate != nil {
            _ = await reminderScheduler.requestAuthorizationIfNeeded()
            reminderAuthorization = await reminderScheduler.authorizationState()
        }
        await reminderScheduler.reschedule(task, now: now())

        completeCapture(task.sourceCaptureID)
    }

    /// 사용자가 "확인했어요" 를 눌렀다. 고치지 않고 그대로 승인하는 길이다.
    ///
    /// 대부분의 확인은 고칠 것이 없다 — 편집기를 열어 아무것도 안 바꾸고 저장하게
    /// 하면 그 대부분에 화면 하나를 더 지나게 하는 셈이다.
    func markReviewed(_ taskID: UUID) async {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].markReviewed()
        persistTasks()
    }

    // MARK: - 고치기

    /// 고친 내용을 반영한다. 저장 경로는 이 문 하나뿐이다.
    ///
    /// **고쳐서 저장하면 확인한 것으로 본다.** 사용자가 그 화면을 열어 값을 보고
    /// 저장을 눌렀으므로, 그보다 더 확실한 확인은 없다.
    func commit(_ edit: TaskEdit, to task: AssistantTask) async {
        var updated = edit.apply(to: task)
        updated.markReviewed()
        await update(updated, addToCalendar: edit.effectiveAddToCalendar)
    }

    /// 사용자가 고친 할 일을 반영한다. **캘린더 일정까지 함께 맞춘다.**
    ///
    /// 캘린더를 맞추지 않으면 앱에는 새 날짜가, 캘린더에는 옛 날짜가 남는다.
    /// 그러면 "어느 쪽이 진짜인가" 를 사용자가 매번 판단해야 한다 — 원장은 앱 하나다.
    ///
    /// 캘린더 실패는 화면에 올리되 저장을 막지 않는다 (ADR-7).
    func update(_ task: AssistantTask, addToCalendar: Bool) async {
        var updated = task
        switch (addToCalendar, task.calendarEventIdentifier) {
        case (true, let identifier?):
            do {
                try await calendarService.updateEvent(identifier: identifier, with: task)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        case (true, nil):
            do {
                updated.calendarEventIdentifier = try await calendarService.addToCalendar(task)
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        case (false, let identifier?):
            await calendarService.removeFromCalendar(eventIdentifier: identifier)
            updated.calendarEventIdentifier = nil
        case (false, nil):
            break
        }

        await save(updated)
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
            await calendarService.removeFromCalendar(eventIdentifier: eventIdentifier)
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
    }

    private func persistTasks() {
        guard let storage else { return }
        do {
            try storage.saveTasks(tasks)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        // 위젯은 같은 원장을 읽지만, 시스템이 하루에 몇 번만 깨워 준다.
        // 여기서 깨우지 않으면 방금 등록한 일정이 홈 화면에 몇 시간 뒤에야 나타난다.
        WidgetCenter.shared.reloadAllTimelines()
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
