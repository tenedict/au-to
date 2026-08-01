import UIKit
import UniformTypeIdentifiers

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
        receiveImage()
    }

    private func receiveImage() {
        let extensionItems = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem } ?? []
        let providers: [NSItemProvider] = extensionItems.reduce(into: []) { result, item in
            result.append(contentsOf: item.attachments ?? [])
        }

        guard let provider = providers.first(
            where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        ) else {
            finishWithError("이미지를 찾지 못했어요.")
            return
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) {
            [weak self] data, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.finishWithError(error.localizedDescription)
                    return
                }
                guard let data else {
                    self.finishWithError("이미지 데이터를 읽지 못했어요.")
                    return
                }

                do {
                    let capture = try SharedInbox.enqueue(imageData: data)
                    // 분석은 메인 앱에서만 돈다. 앱을 열지 않으면 아무 일도 일어나지 않으므로
                    // 여기서 한 번 알린다. 로컬 알림 예약은 파일 쓰기 한 번 수준이라
                    // Extension 을 위험하게 만들지 않는다 (프로젝트 규칙 3 참고).
                    CaptureNotice.postCaptureTaken(captureID: capture.id)
                    self.statusLabel.text = "담았어요. CaptureTask에서 할 일을 확인해 주세요."
                    self.extensionContext?.completeRequest(returningItems: nil)
                } catch {
                    self.finishWithError(error.localizedDescription)
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
