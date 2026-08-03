import PhotosUI
import SwiftUI

/// 탭 두 개와 확인 흐름을 잇는 자리.
///
/// 확인 대기 초안을 언제 띄울지는 여기서만 정한다. 화면 여러 곳에서 각자 띄우면
/// 같은 초안이 두 번 뜨거나, "나중에" 를 눌러도 다시 튀어나온다.
struct RootView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var queue: CaptureQueue
    @ObservedObject var reminderTaps: ReminderTapRouter
    @Environment(\.scenePhase) private var scenePhase

    /// 지금 떠 있는 시트. **하나뿐이다.**
    ///
    /// 예전에는 `.sheet` 를 셋 겹쳐 달았다 (설정 · 텍스트 · 편집기). SwiftUI 는
    /// **뷰 하나에 표시 하나**만 지원해서, 겹쳐 달면 서로를 가린다 — 알림을 눌러
    /// 편집기를 열라고 해도 아무것도 뜨지 않았다. 앱은 열리는데 화면이 없으니
    /// 사용자에게는 "눌러도 안 들어가진다" 로 보인다.
    @State private var sheet: Sheet?
    /// 잠금화면 위젯으로 들어왔다. 카메라를 곧바로 연다.
    @State private var showsCamera = false
    /// 카메라를 못 쓰는 기기(시뮬레이터)라 사진 고르기로 돌렸다.
    @State private var cameraFallbackMessage: String?
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var isPickingPhotos = false
    @State private var selectedTab = Tab.initialFromEnvironment
    /// 펼친 카드. 알림을 눌러 들어온 경우 여기서 정한다.
    @State private var expandedTaskID: UUID?

    /// 탭 라우팅.
    ///
    /// DEBUG 빌드에서 `WHENLY_TAB=0|1` 로 시작 탭을 고를 수 있다.
    /// 시뮬레이터는 탭 입력을 자동화할 수 없어서, 이게 없으면 캘린더 화면을
    /// 사람이 손으로 눌러 보는 것 말고는 확인할 방법이 없다.
    /// (시뮬레이터에서는 `SIMCTL_CHILD_` 접두사를 붙인다)
    enum Tab: Int {
        case tasks = 0
        case calendar = 1

        static var initialFromEnvironment: Tab {
            #if DEBUG
            if let raw = ProcessInfo.processInfo.environment["WHENLY_TAB"],
               let value = Int(raw), let tab = Tab(rawValue: value) {
                return tab
            }
            #endif
            return .tasks
        }
    }

    /// 띄울 수 있는 시트 전부. **여기 없는 시트는 없다.**
    enum Sheet: Identifiable {
        case editor(AssistantTask)
        case settings
        case manualCapture

        var id: String {
            switch self {
            case .editor(let task): return "editor-\(task.id)"
            case .settings: return "settings"
            case .manualCapture: return "manual"
            }
        }
    }

    /// 시트 라우팅.
    ///
    /// DEBUG 빌드에서 `WHENLY_SHEET=settings|text` 로 시작하자마자 그 시트를 연다.
    /// 시뮬레이터는 메뉴를 눌러 열 수 없어서, 이게 없으면 설정 화면을 사람이
    /// 손으로 눌러 보는 것 말고는 확인할 방법이 없다.
    ///
    /// `WHENLY_OPEN_TASK=first` 는 **알림을 누른 것과 같은 길**을 탄다.
    /// 알림 탭은 자동화할 수 없어서, 이게 없으면 라우팅이 살아 있는지 확인할 방법이
    /// 사람 손밖에 없다 — 실제로 그래서 깨진 것을 한참 뒤에 알았다.
    private func openSheetFromEnvironment() {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["WHENLY_SHEET"] {
        case "settings": sheet = .settings
        case "text": sheet = .manualCapture
        default: break
        }
        if let requested = ProcessInfo.processInfo.environment["WHENLY_OPEN_TASK"] {
            let taskID = requested == "first" ? store.tasks.first?.id : UUID(uuidString: requested)
            if let taskID { openTask(taskID) }
        }
        #endif
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DueStackView(
                    store: store,
                    expandedTaskID: $expandedTaskID,
                    onOpenReview: { selectedTab = .tasks },
                    onEditTask: { sheet = .editor($0) },
                    onAddTask: { sheet = .editor(.blank(now: .now)) },
                    onAddText: { sheet = .manualCapture },
                    onPickPhotos: { isPickingPhotos = true },
                    onOpenSettings: { sheet = .settings }
                )
            }
            .tabItem { Label("할 일", systemImage: "checklist") }
            .tag(Tab.tasks)

            NavigationStack {
                MonthCalendarView(store: store, onOpen: { sheet = .editor($0) })
            }
            .tabItem { Label("캘린더", systemImage: "calendar") }
            .tag(Tab.calendar)
        }
        .task {
            // 알림을 눌러 들어온 **첫 실행**은 화면이 그려지기 전에 값이 도착해 있다.
            // `onChange` 만 두면 그 첫 번째를 통째로 놓친다.
            if let taskID = reminderTaps.requestedTaskID { openTask(taskID) }
            await store.refresh()
            openSheetFromEnvironment()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // 공유 시트로 담고 곧바로 앱으로 돌아오는 것이 이 제품의 기본 동선이다.
                // 켜질 때 한 번만 훑으면 그 사용자는 아무것도 보지 못한다.
                Task { await store.refresh() }
            default:
                break
            }
        }
        // 알림을 눌러 들어왔다. **그 일정의 화면을 연다.**
        //
        // 목록 맨 위에 세워 두기만 하면 사용자는 그것을 다시 찾아야 하고,
        // 그러면 알림을 누른 이유가 사라진다 — 실제로 그래서 "눌러도 안 들어가진다"
        // 는 말을 들었다.
        .onChange(of: reminderTaps.requestedTaskID) { _, taskID in
            guard let taskID else { return }
            openTask(taskID)
        }
        // 사진 고르기는 별도 프로세스(PHPicker)에서 돈다. 그래서 사진 접근 권한을
        // 묻지 않는다 — 사용자가 고른 것만 앱에 건네진다.
        .photosPicker(
            isPresented: $isPickingPhotos,
            selection: $pickedPhotos,
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: pickedPhotos) { _, items in
            guard !items.isEmpty else { return }
            pickedPhotos = []
            Task { await importPicked(items) }
        }
        // 위젯·바로가기가 들어오는 문. 모르는 주소는 무시한다 —
        // 아무 데나 열면 오타 난 링크가 고장 났다는 사실을 감춘다.
        .onOpenURL { url in
            switch DeepLink.destination(for: url) {
            case .capture: openCamera()
            case .tasks: selectedTab = .tasks
            case nil: break
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraCaptureSheet(
                onCapture: { data in
                    showsCamera = false
                    // 여기서 읽지 않는다. 줄에 세우면 알림으로 결과가 온다 —
                    // 찍은 사람을 분석이 끝날 때까지 화면 앞에 세워 두지 않는다.
                    queue.enqueue(imageData: data)
                },
                onCancel: { showsCamera = false }
            )
            .ignoresSafeArea()
        }
        .alert(
            "이 기기에서는 카메라를 쓸 수 없어요",
            isPresented: Binding(
                get: { cameraFallbackMessage != nil },
                set: { if !$0 { cameraFallbackMessage = nil } }
            )
        ) {
            Button("사진에서 고르기") {
                cameraFallbackMessage = nil
                isPickingPhotos = true
            }
            Button("취소", role: .cancel) { cameraFallbackMessage = nil }
        } message: {
            Text(cameraFallbackMessage ?? "")
        }
        // **시트는 하나뿐이다.** 겹쳐 달면 서로를 가린다 (`Sheet` 참고).
        .sheet(item: $sheet) { which in
            switch which {
            case .editor(let task):
                TaskEditorSheet(task: task, store: store)
            case .settings:
                SettingsSheet(store: store)
            case .manualCapture:
                ManualCaptureSheet { text in
                    Task { await store.analyzeManualText(text) }
                }
            }
        }
        .alert(
            "처리하지 못했어요",
            isPresented: Binding(
                get: { store.lastErrorMessage != nil },
                set: { if !$0 { store.lastErrorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(store.lastErrorMessage ?? "")
        }
    }

    /// 잠금화면 위젯을 눌러 들어왔다.
    ///
    /// **시뮬레이터에는 카메라가 없다.** 확인하지 않고 열면 빈 검은 화면이 뜨고
    /// 취소도 되지 않는다. 못 쓰는 기기에서는 이유를 말하고 사진 고르기로 돌린다.
    private func openCamera() {
        selectedTab = .tasks
        guard CameraCaptureSheet.isAvailable else {
            cameraFallbackMessage = "대신 사진에서 골라 담을 수 있어요."
            return
        }
        showsCamera = true
    }

    /// 고른 사진을 데이터로 바꿔 저장소에 넘긴다.
    ///
    /// 한 장이 실패해도 나머지는 진행한다 — 여러 장을 고른 사용자가
    /// 한 장 때문에 전부 잃으면 안 된다.
    private func importPicked(_ items: [PhotosPickerItem]) async {
        var images: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                images.append(data)
            }
        }
        guard !images.isEmpty else {
            store.lastErrorMessage = "고른 사진을 읽지 못했어요."
            return
        }
        // 고른 사진도 같은 줄을 지난다. 여기만 다른 길로 가면 속도 제한과
        // 알림이 이 경로에서만 빠지고, 그 차이는 아무도 눈치채지 못한다.
        images.forEach(queue.enqueue(imageData:))
    }

    /// 알림이 가리킨 일정을 연다. **알림 탭이 도착하는 유일한 착지점이다.**
    ///
    /// 그 사이 사용자가 지웠을 수 있다. 그때도 **할 일 탭까지는 간다** — 눌렀는데
    /// 아무 일도 안 일어나는 것이 이 화면에서 가장 나쁜 결과이기 때문이다.
    private func openTask(_ taskID: UUID) {
        reminderTaps.requestedTaskID = nil
        selectedTab = .tasks
        expandedTaskID = taskID
        guard let task = store.tasks.first(where: { $0.id == taskID }) else { return }
        sheet = .editor(task)
    }
}
