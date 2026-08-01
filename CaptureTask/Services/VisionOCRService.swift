import UIKit
import Vision

protocol OCRService: Sendable {
    func recognizeText(in imageData: Data) async throws -> String
}

struct VisionOCRService: OCRService {

    /// 스크린샷 한 장의 인식은 수백 밀리초가 걸린다.
    ///
    /// `VNImageRequestHandler.perform` 은 동기 호출이라 부른 스레드를 그대로 막는다.
    /// 호출자가 `@MainActor` 인 `TaskStore` 이므로, 그냥 부르면 인식이 끝날 때까지
    /// 화면 전체가 멈춘다. 여러 장을 담아 두었으면 앱이 죽은 것처럼 보인다.
    /// 그래서 별도 스레드로 내보낸다.
    func recognizeText(in imageData: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try Self.recognize(imageData))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func recognize(_ imageData: Data) throws -> String {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else {
            throw OCRServiceError.invalidImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ko-KR", "en-US"]

        try VNImageRequestHandler(cgImage: cgImage).perform([request])

        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OCRServiceError.noTextRecognized
        }
        return text
    }
}

enum OCRServiceError: LocalizedError {
    case invalidImage
    case noTextRecognized

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "공유된 이미지를 읽을 수 없어요."
        case .noTextRecognized:
            return "스크린샷에서 글자를 찾지 못했어요. 글자가 있는 화면을 공유해 주세요."
        }
    }
}
