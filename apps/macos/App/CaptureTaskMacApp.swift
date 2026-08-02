import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct CaptureTaskMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // 메뉴바는 이 앱의 상시 진입점이다.
        //
        // SF Symbol 대신 직접 그린 물방울을 쓴다. `drop.fill` 은 떨어지는 물방울이라
        // 꼬리가 있는데, 이 제품의 물방울은 **유리에 맺힌** 것이라 꼬리가 없다.
        // 떠 있는 물방울과 같은 윤곽(`Bead`)을 써서 같은 물건으로 보이게 한다.
        MenuBarExtra {
            menu
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("할 일 열기") { delegate.openList() }
            .keyboardShortcut("o")
        Button("파일에서 고르기…") { delegate.pickFiles() }
            .keyboardShortcut("i")
        Divider()
        Toggle("물방울 보이기", isOn: Binding(
            get: { delegate.isDropletVisible },
            set: { _ in delegate.toggleDroplet() }
        ))
        Divider()
        Button("종료") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// 창을 만들고 관리한다.
///
/// SwiftUI 의 `Window`/`WindowGroup` 으로는 "떠 있고, 눌러도 다른 앱을 뒤로 보내지 않고,
/// 배경이 투명한" 창을 만들 수 없다. 그래서 물방울은 AppKit 으로 직접 만든다.
///
/// **읽기는 여기가 아니라 `CaptureQueue` 가 들고 있다.** 이 델리게이트도 앱과 함께
/// 사는 객체지만, 들어오는 길이 넷(물방울·Dock·파인더·파일 고르기)이라 한 곳으로
/// 모아 두지 않으면 속도 제한과 알림이 길마다 달라진다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private let store = TaskStore()
    private lazy var queue = CaptureQueue(store: store)
    private let reminderTaps = ReminderTapRouter()
    private let dropletMotion = DropletMotion()
    private var droplet: DropletPanel?
    private var listWindow: NSWindow?

    @Published private(set) var isDropletVisible = true

    /// 파인더에서 "다른 앱으로 열기" 하거나 **Dock 아이콘에 끌어다 놓았을 때.**
    ///
    /// 이 경로로 온 파일에는 샌드박스 확장이 함께 오므로 그대로 읽을 수 있다.
    /// 물방울에 떨어뜨린 것과 **똑같이** 처리한다 — 들어온 길이 달라도
    /// 그 다음은 하나여야 한다.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // 바이트를 지금 복사한다. 이 함수가 끝나면 접근권이 사라진다.
            guard let data = try? Data(contentsOf: url) else { continue }
            queue.enqueue(imageData: data)
        }
    }

    /// Dock 아이콘을 눌렀을 때. 창이 하나도 없으면 대시보드를 연다.
    ///
    /// Dock 에 두려고 `LSUIElement` 를 껐으므로(18장 §Dock), 아이콘을 눌렀는데
    /// 아무 일도 안 일어나면 앱이 죽은 것으로 보인다.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        if !hasVisibleWindows { openList() }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        reminderTaps.install()
        showDroplet()
        observeNotificationTaps()
        Task { await store.enableReminders() }
        reportOnDeviceAvailability()
        fileImageFromEnvironment()
        openListFromEnvironment()
    }

    /// DEBUG 빌드에서 `CAPTURETASK_OPEN_LIST=1` 로 시작하면 대시보드를 바로 연다.
    ///
    /// 창을 여는 길은 메뉴바·Dock·물방울 클릭뿐이고 셋 다 사람 손이 필요해서,
    /// 이게 없으면 화면을 눈으로 확인하는 일을 자동화할 수 없다.
    /// iOS 의 `CAPTURETASK_TAB` · `CAPTURETASK_SHEET` 와 같은 갈고리다.
    private func openListFromEnvironment() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["CAPTURETASK_OPEN_LIST"] == "1" else { return }
        openList()
        #endif
    }

    /// 온디바이스 모델을 이 기기에서 쓸 수 있는지 로그로 남긴다.
    /// 화면에서는 설정에 보이지만, 자동 확인에는 이 줄이 필요하다.
    private func reportOnDeviceAvailability() {
        #if DEBUG
        let availability = OnDeviceContextUnderstandingService.availability
        log("온디바이스: \(availability.isAvailable ? "쓸 수 있음" : availability.reason ?? "?")")
        #endif
    }

    /// DEBUG 빌드에서 `CAPTURETASK_FILE=<경로>` 로 시작하면 그 이미지를 곧바로 처리한다.
    ///
    /// 끌어다 놓기는 자동화할 수 없다. 이게 없으면 물방울의 주 경로를
    /// 사람이 손으로 끌어 보는 것 말고는 확인할 방법이 없다.
    ///
    /// **경로는 샌드박스가 읽을 수 있는 곳이어야 한다.** 실제 드롭과 파일 고르기는
    /// 샌드박스 확장을 함께 받지만, 여기서 주는 경로는 그냥 문자열이다.
    /// 컨테이너 안(`~/Library/Containers/com.example.capturetask.mac/Data/Documents`)에 두면 된다.
    private func fileImageFromEnvironment() {
        #if DEBUG
        guard let path = ProcessInfo.processInfo.environment["CAPTURETASK_FILE"] else { return }
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            Task { [store] in
                let result = await store.intake(data)
                let what = result.filed.isEmpty
                    ? "확인 필요" : result.filed.map(\.summary).joined(separator: " / ")
                log("filed=\(what) error=\(store.lastErrorMessage ?? "없음")")
            }
        } catch {
            log("읽기 실패: \(error.localizedDescription)")
        }
        #endif
    }

    #if DEBUG
    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[CaptureTask] \(message)\n".utf8))
    }
    #endif

    // MARK: - 물방울

    private func showDroplet() {
        let motion = dropletMotion
        let panel = DropletPanel {
            DropletView(
                motion: motion,
                onOpenList: { [weak self] in self?.openList() },
                onReceive: { [weak self] data in self?.queue.enqueue(imageData: data) }
            )
        }
        // 옮길 창을 알려 준다. 창이 만들어진 뒤에야 알 수 있어서 여기서 꽂는다.
        motion.panel = panel
        panel.showDroplet()
        droplet = panel
        isDropletVisible = true
    }

    func toggleDroplet() {
        if isDropletVisible {
            droplet?.orderOut(nil)
            isDropletVisible = false
        } else {
            droplet?.orderFrontRegardless()
            isDropletVisible = true
        }
    }

    // MARK: - 알림을 눌렀을 때

    /// 등록 알림이나 확인 요청 알림을 누르면 대시보드를 연다.
    ///
    /// **알림 없이 창을 먼저 여는 일은 하지 않는다.** 예전에는 날짜가 모호하면
    /// 맥이 스스로 창을 띄웠는데, 사용자는 다른 일을 하는 중이었고 창이 튀어나온
    /// 그 자리에 담긴 것이 보이지도 않아 등록이 취소된 것처럼 보였다.
    private func observeNotificationTaps() {
        Task { [weak self] in
            guard let self else { return }
            for await requested in reminderTaps.$requestedCaptureReview.values where requested {
                reminderTaps.requestedCaptureReview = false
                openList()
            }
        }
        Task { [weak self] in
            guard let self else { return }
            for await taskID in reminderTaps.$requestedTaskID.values {
                guard taskID != nil else { continue }
                reminderTaps.requestedTaskID = nil
                openList()
            }
        }
    }

    // MARK: - 목록 창

    func openList() {
        if let listWindow {
            listWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "CaptureTask"
        window.titlebarAppearsTransparent = true
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: DashboardView(
                store: store,
                queue: queue,
                onPickFiles: { [weak self] in self?.pickFiles() }
            )
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        listWindow = window
    }

    // MARK: - 파일에서 고르기

    /// 끌어다 놓기를 모르는 사용자에게 다른 길이 있어야 한다.
    func pickFiles() {
        let dialog = NSOpenPanel()
        dialog.allowedContentTypes = [.image]
        dialog.allowsMultipleSelection = true
        dialog.canChooseDirectories = false
        dialog.prompt = "할 일로 만들기"

        NSApp.activate(ignoringOtherApps: true)
        guard dialog.runModal() == .OK else { return }

        for url in dialog.urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            queue.enqueue(imageData: data)
        }
    }
}
