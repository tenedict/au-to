import AppKit
import UniformTypeIdentifiers

/// 맥의 공유 메뉴에서 이미지를 받아 메인 앱에 넘긴다.
///
/// **파일 URL 만 받는다.** 그래서 App Group 이 필요 없다.
///
/// `NSWorkspace.open(url)` 로 앱을 열면 LaunchServices 가 **앱에게 그 파일의 샌드박스
/// 확장을 준다** — "다른 앱으로 열기" 와 정확히 같은 길이다. 확장이 파일을 어딘가로
/// 복사할 필요가 없고, 따라서 앱과 확장이 공유하는 저장소도 필요 없다.
///
/// 이미지 **데이터**로 오는 공유(예: 사파리에서 이미지 복사)는 받지 않는다.
/// 그건 확장이 어딘가에 써 두고 앱이 읽어야 하는데, 그러려면 App Group 이 필요하고
/// macOS 의 App Group 은 팀 식별자 접두사를 요구한다 (S-1.3 과 같은 제약).
///
/// 무거운 일은 하지 않는다 (ADR-2). OCR·분석·캘린더는 전부 메인 앱이 한다.
final class MacShareViewController: NSViewController {

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        Task { await forwardToApp() }
    }

    private func forwardToApp() async {
        let providers: [NSItemProvider] = (extensionContext?.inputItems ?? [])
            .compactMap { $0 as? NSExtensionItem }
            .reduce(into: []) { result, item in
                result.append(contentsOf: item.attachments ?? [])
            }

        var opened = 0
        for provider in providers {
            guard let url = await fileURL(from: provider) else { continue }
            NSWorkspace.shared.open(url)
            opened += 1
        }

        finish(error: opened == 0 ? "이미지 파일을 찾지 못했어요." : nil)
    }

    private func fileURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func finish(error message: String?) {
        if let message {
            extensionContext?.cancelRequest(
                withError: NSError(
                    domain: "CaptureTaskMacShare",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            )
        } else {
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
