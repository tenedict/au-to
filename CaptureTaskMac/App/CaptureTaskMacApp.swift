import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct CaptureTaskMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // 메뉴바가 이 앱의 유일한 상시 진입점이다 (Dock 아이콘은 LSUIElement 로 껐다).
        MenuBarExtra("CaptureTask", systemImage: "drop.fill") {
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
}

/// 창을 만들고 관리한다.
///
/// SwiftUI 의 `Window`/`WindowGroup` 으로는 "떠 있고, 눌러도 다른 앱을 뒤로 보내지 않고,
/// 배경이 투명한" 창을 만들 수 없다. 그래서 물방울과 배너는 AppKit 으로 직접 만든다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private let store = TaskStore()
    private var droplet: DropletPanel?
    private var banner: NSPanel?
    private var listWindow: NSWindow?
    private var bannerDismissTask: Task<Void, Never>?

    @Published private(set) var isDropletVisible = true

    /// 파인더에서 "다른 앱으로 열기" 하거나 아이콘에 끌어다 놓았을 때.
    ///
    /// 이 경로로 온 파일에는 샌드박스 확장이 함께 오므로 그대로 읽을 수 있다.
    /// 물방울에 떨어뜨린 것과 **똑같이** 처리한다 — 들어온 길이 달라도
    /// 그 다음은 하나여야 한다.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { [store] in
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { continue }
                await store.fileImage(data)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showDroplet()
        observeStore()
        reportOnDeviceAvailability()
        fileImageFromEnvironment()
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
                let filed = await store.fileImage(data)
                let what = filed.isEmpty ? "확인 필요" : filed.map(\.summary).joined(separator: " / ")
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
        let panel = DropletPanel {
            DropletView(store: self.store, onOpenList: { [weak self] in self?.openList() })
        }
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

    // MARK: - 결과 배너

    /// 바로 넣었을 때와 확인이 필요할 때를 나눠 처리한다.
    private func observeStore() {
        Task { [weak self] in
            guard let self else { return }
            for await filed in store.$lastFiled.values {
                guard let filed else { continue }
                showBanner(for: filed)
            }
        }
        Task { [weak self] in
            guard let self else { return }
            for await draft in store.$needsConfirmation.values {
                guard draft != nil else { continue }
                // 모호하면 창을 열어 사람이 보게 한다. 조용히 넘어가지 않는다.
                openList()
            }
        }
    }

    private func showBanner(for filed: FiledCapture) {
        bannerDismissTask?.cancel()
        banner?.orderOut(nil)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 96),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = NSHostingView(
            rootView: FiledBanner(
                filed: filed,
                onUndo: { [weak self] in
                    Task { await self?.store.undoLastFiled(); self?.hideBanner() }
                },
                onEdit: { [weak self] in
                    self?.openList()
                    self?.hideBanner()
                },
                onDismiss: { [weak self] in self?.hideBanner() }
            )
        )

        // 물방울 바로 위에 띄운다. 눈이 이미 그쪽에 있다.
        if let dropletFrame = droplet?.frame {
            panel.setFrameOrigin(
                NSPoint(x: dropletFrame.maxX - 380, y: dropletFrame.maxY + 12)
            )
        }
        panel.orderFrontRegardless()
        banner = panel

        bannerDismissTask = Task { [weak self] in
            try? await Task.sleep(for: FiledBanner.lifetime)
            guard !Task.isCancelled else { return }
            self?.hideBanner()
        }
    }

    private func hideBanner() {
        bannerDismissTask?.cancel()
        banner?.orderOut(nil)
        banner = nil
    }

    // MARK: - 목록 창

    func openList() {
        if let listWindow {
            listWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CaptureTask"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: MacTaskListView(store: store, onPickFiles: { [weak self] in
                self?.pickFiles()
            })
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

        let urls = dialog.urls
        Task { [store] in
            for url in urls {
                guard let data = try? Data(contentsOf: url) else { continue }
                await store.fileImage(data)
            }
        }
    }
}
