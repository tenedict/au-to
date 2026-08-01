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
                    .stroke(Color.accentColor.opacity(0.55), lineWidth: 2)
                    .scaleEffect(ripple ? 1.28 : 0.94)
                    .opacity(ripple ? 0 : 1)
                    .animation(
                        .easeOut(duration: 1.1).repeatForever(autoreverses: false),
                        value: ripple
                    )
            }

            Circle()
                .fill(.regularMaterial)
                .overlay(
                    Circle().strokeBorder(
                        isTargeted ? Color.accentColor : Color.primary.opacity(0.18),
                        lineWidth: isTargeted ? 3 : 1
                    )
                )
                .shadow(color: .black.opacity(0.28), radius: 12, y: 4)

            if store.isImporting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: phase.symbol)
                    .font(.system(size: isTargeted ? 30 : 27, weight: .medium))
                    .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            }
        }
        .frame(width: DropletPanel.diameter, height: DropletPanel.diameter)
        .contentShape(.circle)
        .scaleEffect(isTargeted && !reduceMotion ? 1.08 : 1)
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
