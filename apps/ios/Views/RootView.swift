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

    /// 지금 열려 있는 편집기. 저장된 할 일과 초안이 같은 화면을 쓴다.
    @State private var editing: EditableItem?
    @State private var showsManualCapture = false
    @State private var showsSettings = false
    /// 잠금화면 위젯으로 들어왔다. 카메라를 곧바로 연다.
    @State private var showsCamera = false
    /// 카메라를 못 쓰는 기기(시뮬레이터)라 사진 고르기로 돌렸다.
    @State private var cameraFallbackMessage: String?
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var isPickingPhotos = false
    /// 이번 실행에서 "나중에" 를 누른 초안. 자동으로 다시 띄우지 않는다.
    @State private var deferredDraftIDs: Set<UUID> = []
    @State private var selectedTab = Tab.initialFromEnvironment
    /// 펼친 카드. 알림을 눌러 들어온 경우 여기서 정한다.
    @State private var expandedTaskID: UUID?

    /// 탭 라우팅.
    ///
    /// DEBUG 빌드에서 `CAPTURETASK_TAB=0|1` 로 시작 탭을 고를 수 있다.
    /// 시뮬레이터는 탭 입력을 자동화할 수 없어서, 이게 없으면 캘린더 화면을
    /// 사람이 손으로 눌러 보는 것 말고는 확인할 방법이 없다.
    /// (시뮬레이터에서는 `SIMCTL_CHILD_` 접두사를 붙인다)
    enum Tab: Int {
        case tasks = 0
        case calendar = 1

        static var initialFromEnvironment: Tab {
            #if DEBUG
            if let raw = ProcessInfo.processInfo.environment["CAPTURETASK_TAB"],
               let value = Int(raw), let tab = Tab(rawValue: value) {
                return tab
            }
            #endif
            return .tasks
        }
    }

    /// 시트 라우팅.
    ///
    /// DEBUG 빌드에서 `CAPTURETASK_SHEET=settings|text` 로 시작하자마자 그 시트를 연다.
    /// 시뮬레이터는 메뉴를 눌러 열 수 없어서, 이게 없으면 설정 화면을 사람이
    /// 손으로 눌러 보는 것 말고는 확인할 방법이 없다.
    private func openSheetFromEnvironment() {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["CAPTURETASK_SHEET"] {
        case "settings": showsSettings = true
        case "text": showsManualCapture = true
        default: break
        }
        #endif
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DueStackView(
                    store: store,
                    expandedTaskID: $expandedTaskID,
                    onReviewDrafts: presentNextDraft,
                    onEditTask: { editing = .task($0) },
                    onAddText: { showsManualCapture = true },
                    onPickPhotos: { isPickingPhotos = true },
                    onOpenSettings: { showsSettings = true }
                )
            }
            .tabItem { Label("할 일", systemImage: "checklist") }
            .tag(Tab.tasks)

            NavigationStack {
                MonthCalendarView(store: store, onOpen: { editing = .task($0) })
            }
            .tabItem { Label("캘린더", systemImage: "calendar") }
            .tag(Tab.calendar)
        }
        .task {
            await store.refresh()
            openSheetFromEnvironment()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // 공유 시트로 담고 곧바로 앱으로 돌아오는 것이 이 제품의 기본 동선이다.
                // 켜질 때 한 번만 훑으면 그 사용자는 아무것도 보지 못한다.
                Task { await store.refresh() }
            case .background:
                // 확인 안 한 초안을 남기고 나갔다. 나중에 한 번 더 알린다 —
                // 담아 두기만 하고 확인하지 않으면 이 제품은 사진첩과 같아진다.
                store.scheduleUnconfirmedDraftReminderIfNeeded()
            default:
                break
            }
        }
        .onChange(of: store.pendingDrafts) { _, drafts in
            guard editing == nil else { return }
            guard let next = drafts.first(where: { !deferredDraftIDs.contains($0.id) })
            else { return }
            editing = .draft(next)
        }
        .onChange(of: reminderTaps.requestedCaptureReview) { _, requested in
            guard requested else { return }
            // 확인 요청 알림을 눌러 들어왔다. 할 일 탭으로 옮기고 미뤄 둔 초안까지
            // 다시 보여준다 — 확인하러 온 사람에게 "나중에 확인" 상태를 남기면 안 된다.
            selectedTab = .tasks
            reminderTaps.requestedCaptureReview = false
            deferredDraftIDs.removeAll()
        }
        .onChange(of: reminderTaps.requestedTaskID) { _, taskID in
            guard let taskID else { return }
            // 알림을 눌러 들어왔다. 그 할 일을 펼쳐서 보여준다 — 목록 맨 위에서
            // 다시 찾게 하면 알림의 목적이 사라진다.
            selectedTab = .tasks
            expandedTaskID = taskID
            reminderTaps.requestedTaskID = nil
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
        .sheet(isPresented: $showsSettings) {
            SettingsSheet(store: store)
        }
        .sheet(isPresented: $showsManualCapture) {
            ManualCaptureSheet { text in
                Task { await store.analyzeManualText(text) }
            }
        }
        .sheet(item: $editing, onDismiss: presentNextDraftIfAny) { item in
            TaskEditorSheet(
                item: item,
                store: store,
                onDefer: { deferredDraftIDs.insert(item.id) }
            )
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

    /// 사용자가 직접 "확인할 할 일" 을 눌렀을 때는 미뤄 둔 것까지 다시 보여준다.
    private func presentNextDraft() {
        deferredDraftIDs.removeAll()
        guard let first = store.pendingDrafts.first else { return }
        editing = .draft(first)
    }

    /// 한 건을 처리하면 다음 **초안**을 이어서 띄운다. 여러 장을 한 번에 담은
    /// 사용자가 매번 목록으로 돌아갔다 들어오지 않도록.
    ///
    /// 저장된 할 일을 고치고 닫았을 때는 이어 붙이지 않는다 — 고치러 들어온
    /// 사용자에게 확인 화면을 밀어 넣으면 자기가 무엇을 열었는지 잃는다.
    private func presentNextDraftIfAny() {
        guard let next = store.pendingDrafts.first(where: { !deferredDraftIDs.contains($0.id) })
        else { return }
        // 시트 전환이 겹치면 두 번째가 뜨지 않는다. 한 프레임 뒤로 미룬다.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            if editing == nil {
                editing = .draft(next)
            }
        }
    }
}
