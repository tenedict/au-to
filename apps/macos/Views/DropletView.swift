import SwiftUI
import UniformTypeIdentifiers

/// 화면에 떠 있는 창. 여기에 이미지를 떨어뜨리면 캘린더까지 간다.
///
/// **상태를 크기로만 말한다.** 색은 아예 쓰지 않는다 — 색만 바꾸면 흑백 화면이나
/// 색각 이상 사용자에게는 아무 일도 일어나지 않은 것과 같다 (CLAUDE 규칙 13).
/// 어떤 상태가 얼마나 커지는지는 `DropletAppearance` 가 정하고 테스트가 지킨다.
///
/// **읽는 중이라는 표시는 두지 않는다.** 읽기는 `CaptureQueue` 가 뒤에서 하고,
/// 끝나면 알림이 온다. 물방울에 회전판을 달면 사용자는 그것이 끝날 때까지
/// 화면을 지키게 되는데, 이 제품의 값은 정확히 그 기다림을 없애는 것이다.
/// 대신 놓은 직후 잠깐 크게 머문다 — 삼킨 티가 한 번은 나야 한다.
struct DropletView: View {
    @ObservedObject var motion: DropletMotion
    let onOpenList: () -> Void
    /// 받은 이미지를 넘길 곳. 화면은 들고 있지 않는다 — 창이 열리고 닫혀도
    /// 처리가 끊기면 안 되기 때문이다 (`CaptureQueue` 참고).
    let onReceive: (Data) -> Void

    @State private var isTargeted = false
    @State private var isPressed = false
    /// 방금 삼켰다. 잠깐 크게 머문다.
    @State private var justSwallowed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 놓은 뒤 큰 상태로 머무는 시간.
    private static let swallowLinger: Duration = .milliseconds(420)

    private var phase: DropletPhase {
        if isTargeted || justSwallowed { return .receiving }
        if motion.isMoving { return .moving }
        if isPressed { return .pressed }
        return .idle
    }

    /// 한 변. 예전에는 지름이었다 — 원에서 둥근 사각형으로 바뀌었다.
    private var side: CGFloat { DropletAppearance.side(for: phase) }

    var body: some View {
        droplet
        // 창은 고정이고 물방울만 커진다. 창까지 같이 커지면 겨냥하는 중에
        // 드롭 영역이 움직여서 커서가 안팎을 오간다.
        .frame(width: DropletAppearance.panelSide, height: DropletAppearance.panelSide)
        .contentShape(.rect)
        // 모션 줄이기는 **크기 변화가 아니라 애니메이션**을 끈다. 크기는 이 물방울의
        // 유일한 상태 신호라, 없애면 무슨 일이 일어나는지 알 방법이 사라진다.
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.72),
                   value: phase)
        .gesture(pressAndMove)
        .onDrop(of: [.image, .fileURL], isTargeted: $isTargeted) { providers in
            showSwallow()
            Task { await handle(providers) }
            return true
        }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityHint("탭하면 할 일 목록을 열어요. 끌면 옮길 수 있어요")
        .accessibilityAddTraits(.isButton)
        .help(label)
    }

    // MARK: - 떠 있는 창

    /// 유리판 위의 둥근 사각형.
    ///
    /// 예전에는 **물방울(원)** 이었다. 앱 아이콘을 사람이 그린 둥근 사각형으로
    /// 바꾸면서 여기만 원으로 남으니, 화면 구석의 그것과 Dock 의 아이콘이
    /// 서로 다른 앱처럼 보였다. **표식은 하나여야 한다.**
    ///
    /// 층이 넷이고 순서가 곧 광학이다.
    ///
    /// 1. **유리** — 가운데를 아주 옅게 채운다 (macOS 26+). 굴절은 아니지만
    ///    "무언가 놓여 있다" 가 생긴다.
    /// 2. **어두운 가장자리** — 흰 배경 위에서 이것을 보이게 하는 것은 이 층 하나다.
    ///    흰 림라이트만 쓰면 흰 화면에서 통째로 사라진다.
    /// 3. **얇은 밝은 선** — 유리에 닿은 경계.
    /// 4. **표식** — 앱 아이콘과 같은 빗금 셋. 이게 없으면 그냥 반투명한 사각형이다.
    private var droplet: some View {
        RoundedRectangle(cornerRadius: side * Mark.cornerRatio, style: .continuous)
            .fill(.clear)
            .glassIfAvailable(cornerRadius: side * Mark.cornerRatio)
            .overlay { edgeShade }
            .overlay { innerRim }
            .overlay { highlight }
            .overlay { mark }
            .frame(width: side, height: side)
            // 그림자는 아주 얕게. 유리에 닿아 있지 떠 있지 않다.
            // 창이 넉넉히 커서(edgeAllowance) 잘리지 않는다.
            .shadow(color: .black.opacity(0.18), radius: 2.5, x: 0, y: 1.5)
    }

    /// 가장자리 그늘. 가운데는 투명하고 테두리로 갈수록 짙어진다.
    private var edgeShade: some View {
        RoundedRectangle(cornerRadius: side * Mark.cornerRatio, style: .continuous)
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: .clear, location: 0.55),
                        .init(color: Color(white: 0.08).opacity(0.26), location: 1.0),
                    ],
                    center: .center, startRadius: 0, endRadius: side * 0.75
                )
            )
    }

    /// 안쪽 얇은 밝은 선.
    private var innerRim: some View {
        RoundedRectangle(cornerRadius: side * Mark.cornerRatio, style: .continuous)
            .strokeBorder(.white.opacity(0.55), lineWidth: 0.9)
            .blendMode(.plusLighter)
    }

    /// 왼쪽 위에서 비스듬히 떨어지는 빛 한 줄기.
    private var highlight: some View {
        LinearGradient(
            colors: [.white.opacity(0.30), .clear],
            startPoint: .topLeading,
            endPoint: .center
        )
        .clipShape(RoundedRectangle(cornerRadius: side * Mark.cornerRatio, style: .continuous))
    }

    /// 앱 아이콘과 같은 표식. 바깥 윤곽은 창 자체가 이미 그리므로 빗금만 그린다.
    private var mark: some View {
        Canvas { context, size in
            context.fill(
                Mark.bars(in: CGRect(origin: .zero, size: size)),
                with: .color(Palette.ink1.opacity(0.72)))
        }
        .frame(width: side, height: side)
    }

    // MARK: - 누르기 · 옮기기 · 탭

    /// 하나의 제스처가 셋을 다 받는다.
    ///
    /// 나눠 달면 탭과 드래그가 서로를 먹는다. `minimumDistance: 0` 이라 손이 닿는
    /// 순간부터 알 수 있고, 문턱을 넘으면 그때부터 창을 옮긴다.
    private var pressAndMove: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isPressed {
                    isPressed = true
                    motion.begin()
                }
                // 이동량은 제스처가 아니라 화면 좌표에서 읽는다 — 이유는 DropletMotion 에.
                motion.drag()
            }
            .onEnded { _ in
                let wasTap = motion.end()
                isPressed = false
                if wasTap { onOpenList() }
            }
    }

    private var label: String {
        switch phase {
        case .idle, .pressed: return "Whenly. 스크린샷을 여기에 끌어다 놓으세요"
        case .moving: return "옮기는 중이에요"
        case .receiving:
            return justSwallowed
                ? "받았어요. 다 읽으면 알림으로 알려 드려요"
                : "놓으면 할 일로 만들어요"
        }
    }

    // MARK: - 받은 것 처리

    /// 떨어진 것들에서 **바이트만 꺼내** 줄에 넘긴다.
    ///
    /// 여기서 읽거나 분석하지 않는다. 파인더가 준 파일 URL 의 접근권은 드롭 세션이
    /// 끝나면 사라지므로 **지금 복사해 둬야 한다.** 그 다음 일은 화면 밖에서 돈다.
    ///
    /// 한 장이 실패해도 나머지는 진행한다 — 여러 장을 끌어다 놓은 사용자가
    /// 한 장 때문에 전부 잃으면 안 된다.
    private func handle(_ providers: [NSItemProvider]) async {
        for provider in providers {
            guard let data = await imageData(from: provider) else { continue }
            onReceive(data)
        }
    }

    /// 삼킨 티를 잠깐 남긴다.
    private func showSwallow() {
        justSwallowed = true
        Task { @MainActor in
            try? await Task.sleep(for: Self.swallowLinger)
            justSwallowed = false
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

private extension View {
    /// macOS 26 의 유리를 쓸 수 있으면 쓴다.
    ///
    /// 26 미만에서는 채우지 않는다. 대신 가운데가 완전히 투명해 뒤가 그대로 보인다.
    @ViewBuilder
    func glassIfAvailable(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            // `.regular` 가 아니라 `.clear` 다. `.regular` 는 뒤를 서리처럼 가려서
            // **불투명한 알약**으로 보인다. 떠 있는 것은 뒤가 보여야 화면을 덜 가린다.
            self.glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
        } else {
            self
        }
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
