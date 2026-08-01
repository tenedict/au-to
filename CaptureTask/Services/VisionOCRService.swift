import UIKit
import Vision

protocol OCRService: Sendable {
    func recognizeText(in imageData: Data) async throws -> String
}

struct VisionOCRService: OCRService {
    func recognizeText(in imageData: Data) async throws -> String {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            throw OCRServiceError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["ko-KR", "en-US"]

            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum OCRServiceError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        "공유된 이미지를 읽을 수 없어요."
    }
}

