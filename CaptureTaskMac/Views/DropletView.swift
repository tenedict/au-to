import SwiftUI
import UniformTypeIdentifiers

/// 화면에 떠 있는 물방울. 여기에 이미지를 떨어뜨리면 캘린더까지 간다.
///
/// 상태를 **모양으로** 보여준다 — 색만 바꾸면 흑백 화면이나 색각 이상 사용자에게는
/// 아무 일도 일어나지 않은 것과 같다 (CLAUDE 규칙 13).
struct DropletView: View {
    @ObservedObject var store: TaskStore
    let onOpenList: () -> Void

    @State private var isTargeted = false
    @State private var ripple = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phase: Phase {
        if store.isImporting { return .working }
        if isTargeted { return .ready }
        return .idle
    }

    enum Phase {
        case idle, ready, working

        var symbol: String {
            switch self {
            case .idle: return "drop.fill"
            case .ready: return "arrow.down.circle.fill"
            case .working: return "drop.fill"
            }
        }

        var label: String {
            switch self {
            case .idle: return "물방울. 스크린샷을 여기에 끌어다 놓으세요"
            case .ready: return "놓으면 할 일로 만들어요"
            case .working: return "읽는 중이에요"
            }
        }
    }

    var body: some View {
        ZStack {
            // 떨어뜨릴 수 있다는 신호. 물결이 바깥으로 번진다.
            if isTargeted && !reduceMotion {
                Circle()
                    .stroke(Color.accentColor.opacity(0.5), lineWidth: 2)
                    .scaleEffect(ripple ? 1.30 : 0.94)
                    .opacity(ripple ? 0 : 1)
                    .animation(
                        .easeOut(duration: 1.1).repeatForever(autoreverses: false),
                        value: ripple
                    )
            }

            glass
            surfaceHighlights
            symbol
        }
        .frame(width: DropletPanel.diameter, height: DropletPanel.diameter)
        .contentShape(.circle)
        .scaleEffect(isTargeted && !reduceMotion ? 1.10 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7),
                   value: isTargeted)
        .onDrop(of: [.image, .fileURL], isTargeted: $isTargeted) { providers in
            Task { await handle(providers) }
            return true
        }
        .onChange(of: isTargeted) { _, targeted in
            ripple = targeted
        }
        // 눌러서 목록을 연다. 끌어다 놓기를 모르는 사용자에게 다른 길이 있어야 한다.
        .onTapGesture(perform: onOpenList)
        .accessibilityElement()
        .accessibilityLabel(phase.label)
        .accessibilityHint("탭하면 할 일 목록을 열어요")
        .accessibilityAddTraits(.isButton)
        .help(phase.label)
    }

    /// 물방울 본체.
    ///
    /// **뒤가 비쳐야 물방울이다.** `.ultraThinMaterial` 은 뒤 화면을 흐리게 통과시키고,
    /// 그 위에 아주 옅은 파랑을 얹어 물빛을 준다. 불투명하게 채우면 그냥 원형 버튼이 된다.
    private var glass: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .overlay {
                Circle().fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.62, green: 0.83, blue: 1.0).opacity(0.28),
                            Color(red: 0.30, green: 0.60, blue: 0.95).opacity(0.20),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                // 가장자리 — 유리의 두께. 위쪽이 밝고 아래쪽이 어둡다.
                Circle().strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(isTargeted ? 0.95 : 0.75),
                            .white.opacity(0.15),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isTargeted ? 2.5 : 1.2
                )
            }
            .overlay {
                if isTargeted {
                    Circle().strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 2)
                }
            }
            .shadow(color: .black.opacity(0.22), radius: 10, y: 3)
    }

    /// 표면의 빛 — 이게 있어야 유리로 읽힌다.
    private var surfaceHighlights: some View {
        GeometryReader { geometry in
            let d = min(geometry.size.width, geometry.size.height)
            ZStack {
                // 위쪽 스페큘러
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.75), .white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: d * 0.44, height: d * 0.24)
                    .rotationEffect(.degrees(-24))
                    .offset(x: -d * 0.13, y: -d * 0.20)

                // 아래쪽 반사 — 빛이 바닥에서 한 번 더 튄다
                Ellipse()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: d * 0.40, height: d * 0.10)
                    .offset(y: d * 0.26)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var symbol: some View {
        if store.isImporting {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: phase.symbol)
                .font(.system(size: isTargeted ? 22 : 19, weight: .medium))
                .foregroundStyle(
                    isTargeted ? Color.accentColor : Color.primary.opacity(0.55)
                )
                .shadow(color: .white.opacity(0.6), radius: 1, y: 0.5)
        }
    }

    /// 떨어진 것들을 순서대로 처리한다.
    ///
    /// 한 장이 실패해도 나머지는 진행한다 — 여러 장을 끌어다 놓은 사용자가
    /// 한 장 때문에 전부 잃으면 안 된다.
    private func handle(_ providers: [NSItemProvider]) async {
        for provider in providers {
            guard let data = await imageData(from: provider) else { continue }
            await store.fileImage(data)
        }
    }

    private func imageData(from provider: NSItemProvider) async -> Data? {
        // 파인더에서 끌면 파일 URL 로, 브라우저나 미리보기에서 끌면 이미지 자체로 온다.
        // 둘 다 받는다.
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = try? await provider.loadItem(forURL: UTType.fileURL.identifier),
           let data = try? Data(contentsOf: url) {
            return data
        }
        return try? await provider.loadData(for: UTType.image.identifier)
    }
}

private extension NSItemProvider {
    func loadData(for identifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    func loadItem(forURL identifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: identifier) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                }
            }
        }
    }
}
