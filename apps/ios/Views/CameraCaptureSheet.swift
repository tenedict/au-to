import PhotosUI
import SwiftUI
import UIKit

/// 카메라를 열고, 찍은 사진을 그대로 넘긴다.
///
/// **잠금화면 위젯의 착지점이다.** 종이 안내문·화이트보드·전광판처럼 스크린샷이
/// 존재하지 않는 것을 담는 길이 지금까지 없었다 — 사진을 찍고, 앨범에 들어가고,
/// 공유하고, 고르는 넷을 지나야 했다. 여기서는 찍는 순간 끝난다.
///
/// 찍은 뒤 확인 화면을 두지 않는다. 잘못 찍었으면 다시 찍으면 되고,
/// 등록된 것은 알림에서 눌러 고치거나 지울 수 있다.
///
/// `UIImagePickerController` 를 쓴다. `AVCaptureSession` 을 직접 다루면 화면 회전·
/// 플래시·초점·권한 안내를 전부 우리가 만들어야 하는데, 그건 이 제품이 잘할 일이 아니다.
struct CameraCaptureSheet: UIViewControllerRepresentable {
    /// 찍은 사진. JPEG 로 넘긴다 — 뒤에서 OCR 만 하므로 원본 해상도가 필요 없다.
    let onCapture: (Data) -> Void
    let onCancel: () -> Void

    /// 이 기기에서 카메라를 쓸 수 있는가.
    ///
    /// **시뮬레이터에는 카메라가 없다.** 확인해 보지 않고 열면 빈 검은 화면이 뜨고,
    /// 취소도 안 되는 상태가 된다. 부르는 쪽이 이 값을 보고 사진 고르기로 돌린다.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
        UINavigationControllerDelegate
    {
        private let onCapture: (Data) -> Void
        private let onCancel: () -> Void

        init(onCapture: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.9) else {
                onCancel()
                return
            }
            onCapture(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
