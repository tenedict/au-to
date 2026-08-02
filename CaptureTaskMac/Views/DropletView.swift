import SwiftUI
import UniformTypeIdentifiers

/// 화면에 떠 있는 물방울. 여기에 이미지를 떨어뜨리면 캘린더까지 간다.
///
/// 상태를 **모양으로만** 보여준다. 색은 아예 쓰지 않는다 — 색만 바꾸면 흑백 화면이나
/// 색각 이상 사용자에게는 아무 일도 일어나지 않은 것과 같다 (CLAUDE 규칙 13).
struct DropletView: View {
    @ObservedObject var store: TaskStore
    let onOpenList: () -> Void

    @State private var isTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phase: Phase {
        if store.isImporting { return .working }
        if isTargeted { return .ready }
        return .idle
    }

    enum Phase {
        case idle, ready, working

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
            ring
                // 바깥 지름도 조금 줄어든다. 셔터는 안으로 조이는 동작이다.
                .scaleEffect(isTargeted && !reduceMotion ? 0.90 : 1)

            if store.isImporting {
                ProgressView().controlSize(.small)
            }
        }
        // 크기가 바뀌는 것은 **고리뿐이다.** 이 프레임과 드롭 영역은 그대로 둔다 —
        // 겨냥하는 중에 목표가 작아지면 커서가 밖으로 나가 놓기가 풀리고,
        // 다시 커지면 또 들어와 깜빡인다.
        .frame(width: DropletPanel.diameter, height: DropletPanel.diameter)
        .contentShape(.circle)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82),
                   value: isTargeted)
        .onDrop(of: [.image, .fileURL], isTargeted: $isTargeted) { providers in
            Task { await handle(providers) }
            return true
        }
        // 눌러서 목록을 연다. 끌어다 놓기를 모르는 사용자에게 다른 길이 있어야 한다.
        .onTapGesture(perform: onOpenList)
        .accessibilityElement()
        .accessibilityLabel(phase.label)
        .accessibilityHint("탭하면 할 일 목록을 열어요")
        .accessibilityAddTraits(.isButton)
        .help(phase.label)
    }

    /// 테두리만 있는 고리.
    ///
    /// **가운데는 아무것도 그리지 않는다.** 뒤 화면이 흐려짐 없이 그대로 보인다.
    ///
    /// 예전에는 `.ultraThinMaterial` 로 채웠는데, 그건 뒤를 **흐리게** 만드는 재질이라
    /// 물방울 자리에 뿌연 판이 생겼다. 게다가 macOS 에서는 그 흐림이 원 밖으로 번져
    /// 네모난 자국으로 보였다. 투명하게 하려면 채우지 않는 것이 답이다.
    ///
    /// 스테인리스처럼 보이는 이유는 **각도에 따라 밝기가 도는** 그라디언트 때문이다.
    /// 금속은 한 방향에서만 빛나지 않는다 — 둘레를 돌며 밝은 띠와 어두운 띠가 번갈아 온다.
    ///
    /// **그림자를 쓰지 않는다.** 창이 고리에 딱 맞는 68×68 이라 중심에서 모서리까지가
    /// 고리 반지름보다 가깝다. 그래서 그림자가 네 모서리에 닿고 창 경계에서 직선으로
    /// 잘려 **뿌연 네모**로 보였다. 윤곽은 그림자 대신 바깥쪽 실선으로 만든다.
    ///
    /// 끌고 오면 **카메라 셔터가 닫히듯 조인다.** 두께가 안쪽으로 자라 구멍이 좁아진다 —
    /// 셔터에서 움직이는 것은 날개이지 렌즈 통이 아니다. 바깥이 아니라
    /// **안쪽으로** 자라야 조여지는 것으로 읽힌다.
    ///
    /// **색은 쓰지 않는다.** 강조색 고리와 물결이 있었지만 쇠에 파란 테가 겹치니
    /// 물건 하나가 아니라 두 개로 보였다. 알림은 조임 하나로 충분하다 —
    /// 색을 안 쓰니 규칙 13(색만으로 알리지 않기)도 저절로 지켜진다.
    private var ring: some View {
        let width: CGFloat = isTargeted ? 12 : 3

        return Circle()
            .strokeBorder(Self.steel, lineWidth: width)
            .overlay {
                // 바깥 윤곽 — 밝은 배경 위에서도 고리가 배경에 묻히지 않게 한다.
                // 그림자가 하던 일을, 원 밖으로 한 픽셀도 넘지 않으면서 한다.
                Circle().strokeBorder(.black.opacity(0.30), lineWidth: 0.5)
            }
            .overlay {
                // 안쪽 모서리 — 그늘. 두께가 있다는 신호다.
                Circle()
                    .strokeBorder(.black.opacity(0.35), lineWidth: 0.75)
                    .padding(width - 0.75)
            }
    }

    /// 둘레를 도는 금속 광택.
    ///
    /// 밝은 띠 둘, 어두운 띠 둘을 마주 보게 놓았다. 실제 원통형 금속에 조명이
    /// 하나 있을 때 나타나는 배치다.
    ///
    /// **명암 차가 커야 금속으로 읽힌다.** 처음에는 0.45~1.00 을 썼는데 흰 배경 위에서는
    /// 그냥 흰 고리로 보였다. 어두운 띠를 0.22 까지 내리니 비로소 금속이 됐다 —
    /// 금속의 어두운 부분은 회색이 아니라 거의 검다.
    private static let steel = AngularGradient(
        stops: [
            .init(color: Color(white: 0.97), location: 0.00),
            .init(color: Color(white: 0.32), location: 0.12),
            .init(color: Color(white: 0.72), location: 0.25),
            .init(color: Color(white: 1.00), location: 0.38),
            .init(color: Color(white: 0.28), location: 0.50),
            .init(color: Color(white: 0.86), location: 0.62),
            .init(color: Color(white: 0.22), location: 0.75),
            .init(color: Color(white: 0.78), location: 0.88),
            .init(color: Color(white: 0.97), location: 1.00),
        ],
        center: .center,
        angle: .degrees(-35)
    )

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
