import UIKit
import UniformTypeIdentifiers

/// 공유 시트에서 이미지를 받아 App Group 상자에 담는다.
///
/// **여기서 하는 일은 담기와 알림 한 번뿐이다.** OCR·분석·캘린더는 메인 앱이 한다 (ADR-2).
/// Extension 은 메모리와 실행 시간이 빡빡해서, 무거운 것을 넣으면 시스템이 중간에 죽인다 —
/// 그러면 사용자는 담기가 실패한 줄도 모른다.
final class ShareViewController: UIViewController {
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "스크린샷을 담는 중이에요…"
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        receiveImages()
    }

    private func receiveImages() {
        let providers: [NSItemProvider] = (extensionContext?.inputItems ?? [])
            .compactMap { $0 as? NSExtensionItem }
            .reduce(into: []) { result, item in
                result.append(contentsOf: item.attachments ?? [])
            }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }

        guard !providers.isEmpty else {
            finishWithError("이미지를 찾지 못했어요.")
            return
        }

        if providers.count > 1 {
            statusLabel.text = "\(providers.count)장을 담는 중이에요…"
        }

        Task { await enqueue(providers) }
    }

    private func enqueue(_ providers: [NSItemProvider]) async {
        var captureIDs: [UUID] = []
        var firstFailure: String?

        // 한 장이 실패해도 나머지는 담는다. 여러 장을 고른 사용자가
        // 한 장 때문에 전부 잃으면 안 된다.
        for provider in providers {
            do {
                let data = try await loadImageData(from: provider)
                captureIDs.append(try SharedInbox.enqueue(imageData: data).id)
            } catch {
                firstFailure = firstFailure ?? error.localizedDescription
            }
        }

        await MainActor.run {
            guard !captureIDs.isEmpty else {
                finishWithError(firstFailure ?? "이미지 데이터를 읽지 못했어요.")
                return
            }

            // 분석은 메인 앱에서만 돈다. 이 알림이 없으면 앱을 열지 않은 사용자에게
            // 아무 일도 일어나지 않는다.
            CaptureNotice.postCaptureTaken(captureIDs: captureIDs)

            statusLabel.text = captureIDs.count == 1
                ? "담았어요. CaptureTask에서 할 일을 확인해 주세요."
                : "\(captureIDs.count)장 담았어요. CaptureTask에서 확인해 주세요."
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func loadImageData(from provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(
                forTypeIdentifier: UTType.image.identifier
            ) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: ShareError.emptyImageData)
                }
            }
        }
    }

    private func finishWithError(_ message: String) {
        statusLabel.text = message
        extensionContext?.cancelRequest(
            withError: NSError(
                domain: "CaptureTaskShare",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        )
    }
}

private enum ShareError: LocalizedError {
    case emptyImageData

    var errorDescription: String? { "이미지 데이터를 읽지 못했어요." }
}
