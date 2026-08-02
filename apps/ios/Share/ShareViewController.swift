import UIKit
import UniformTypeIdentifiers

/// 공유 시트에서 이미지를 받아 **등록까지 끝낸다.**
///
/// ## 왜 여기서 다 하나 (ADR-2 를 다시 연 이유)
///
/// 예전 흐름은 넷이었다 — 공유 → 담기 → 앱 열기 → 확인 → 등록.
/// 그 사이 어디서든 잊으면 아무 일도 일어나지 않았고, 담아 두기만 한 스크린샷은
/// 사진첩에 묻힌 것과 다를 게 없었다.
///
/// 지금은 셋이다 — 공유 → 등록 → "언제 무슨 일정이 등록되었습니다" 알림.
///
/// ## 그래도 지키는 것
///
/// **분석보다 담기가 먼저다.** 시스템이 확장을 중간에 죽여도 캡처는 상자에 남고,
/// 앱이 다음에 열릴 때 이어서 처리한다. 이 순서가 ADR-2 의 진짜 알맹이였다 —
/// "무거운 것을 넣지 마라" 가 아니라 **"죽어도 잃지 마라"** 다.
///
/// 확인은 없애지 않았다. 날짜가 모호하면 등록하지 않고 확인을 요청한다
/// (`AutoFilePolicy`). 확실한 것만 바로 들어간다.
final class ShareViewController: UIViewController {
    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "스크린샷을 읽는 중이에요…"
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let spinner: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(style: .medium)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.startAnimating()
        return view
    }()

    private lazy var store = TaskStore()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(statusLabel)
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16)
        ])
        Task { await run() }
    }

    private func run() async {
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

        // ── 1단계 · 먼저 담는다 ────────────────────────────
        // 여기서 죽어도 캡처는 남는다. 이 순서가 유일한 안전망이다.
        var captures: [PendingCapture] = []
        var firstFailure: String?
        for provider in providers {
            do {
                let data = try await loadImageData(from: provider)
                captures.append(try SharedInbox.enqueue(imageData: data))
            } catch {
                firstFailure = firstFailure ?? error.localizedDescription
            }
        }

        guard !captures.isEmpty else {
            finishWithError(firstFailure ?? "이미지 데이터를 읽지 못했어요.")
            return
        }

        if captures.count > 1 {
            statusLabel.text = "\(captures.count)장을 읽는 중이에요…"
        }

        // ── 2단계 · 읽고 등록한다 ──────────────────────────
        var filed: [FiledCapture] = []
        var needsReview: [TaskDraft] = []
        for capture in captures {
            guard let data = try? SharedInbox.imageData(for: capture) else { continue }
            let result = await store.intake(data, captureID: capture.id)
            filed.append(contentsOf: result.filed)
            needsReview.append(contentsOf: result.needsReview)
        }

        await report(filed: filed, captures: captures, needsReview: needsReview)
    }

    /// 무엇이 어떻게 됐는지 알린다.
    ///
    /// **등록한 것과 확인이 필요한 것을 나눠 말한다.** 뭉뚱그리면 사용자는
    /// 앱을 열어 확인해야 하고, 그러면 단계를 줄인 의미가 없다.
    @MainActor
    private func report(
        filed: [FiledCapture],
        captures: [PendingCapture],
        needsReview: [TaskDraft]
    ) async {
        spinner.stopAnimating()

        if !filed.isEmpty {
            CaptureNotice.postFiled(
                summaries: filed.map(\.summary),
                captureID: captures.first?.id
            )
        }
        if !needsReview.isEmpty {
            // 확인이 필요한 것이 남았다. 무엇인지까지 알림이 말한다.
            CaptureNotice.postNeedsReview(
                titles: needsReview.map(\.title),
                captureID: captures.first?.id
            )
        }
        if filed.isEmpty, needsReview.isEmpty {
            CaptureNotice.postNothingFound(captureID: captures.first?.id, reason: nil)
        }

        statusLabel.text = summary(filed: filed, needsReview: !needsReview.isEmpty)
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func summary(filed: [FiledCapture], needsReview: Bool) -> String {
        switch (filed.count, needsReview) {
        case (0, true):
            return "확인이 필요해요. CaptureTask에서 봐 주세요."
        case (0, false):
            return "할 일로 만들 내용을 찾지 못했어요."
        case (let count, false):
            return count == 1
                ? "등록했어요. \(filed[0].summary)"
                : "일정 \(count)개를 등록했어요."
        case (let count, true):
            return "\(count)개는 등록했고, 나머지는 확인이 필요해요."
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

    @MainActor
    private func finishWithError(_ message: String) {
        spinner.stopAnimating()
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
