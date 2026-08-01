import Combine
import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [AssistantTask] = []
    @Published var pendingDrafts: [TaskDraft] = []
    @Published var lastErrorMessage: String?
    @Published var isImporting = false

    private let ocrService: any OCRService
    private let understandingService: any ContextUnderstandingService

    init(
        ocrService: any OCRService = VisionOCRService(),
        understandingService: any ContextUnderstandingService = RuleBasedContextUnderstandingService()
    ) {
        self.ocrService = ocrService
        self.understandingService = understandingService
        load()
    }

    func importPendingCaptures() async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        do {
            for capture in try SharedInbox.pendingCaptures() {
                if tasks.contains(where: { $0.sourceCaptureID == capture.id }) {
                    try? SharedInbox.complete(capture)
                    continue
                }
                let imageData = try SharedInbox.imageData(for: capture)
                let text = try await ocrService.recognizeText(in: imageData)
                let draft = try await understandingService.makeDraft(
                    from: text,
                    captureID: capture.id
                )
                if !pendingDrafts.contains(where: { $0.sourceCaptureID == capture.id }) {
                    pendingDrafts.append(draft)
                }
            }
        } catch SharedInboxError.appGroupUnavailable {
#if !targetEnvironment(simulator)
            lastErrorMessage = SharedInboxError.appGroupUnavailable.localizedDescription
#endif
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func analyzeManualText(_ text: String) async {
        do {
            pendingDrafts.append(
                try await understandingService.makeDraft(from: text, captureID: nil)
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func save(_ task: AssistantTask, sourceCaptureID: UUID?) {
        tasks.insert(task, at: 0)
        pendingDrafts.removeAll { $0.id == task.id }
        save()

        guard let sourceCaptureID,
              let capture = try? SharedInbox.pendingCaptures().first(
                where: { $0.id == sourceCaptureID }
              ) else {
            return
        }
        do {
            try SharedInbox.complete(capture)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func updateCalendarIdentifier(_ identifier: String, for taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].calendarEventIdentifier = identifier
        save()
    }

    func toggleCompletion(for taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].state = tasks[index].state == .pending ? .completed : .pending
        save()
    }

    func delete(at offsets: IndexSet) {
        tasks.remove(atOffsets: offsets)
        save()
    }

    private var persistenceURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("CaptureTask/tasks.json")
    }

    private func load() {
        guard let url = persistenceURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([AssistantTask].self, from: data) else {
            return
        }
        tasks = decoded
    }

    private func save() {
        guard let url = persistenceURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(tasks).write(to: url, options: .atomic)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
