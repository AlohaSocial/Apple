// SPDX-License-Identifier: MIT

#if os(iOS)
    import SwiftUI
    import UIKit
    import UniformTypeIdentifiers

    /// The system camera, for a photo or a video taken right now.
    ///
    /// A stopgap for a capture screen of the app's own (docs/06): the system
    /// camera already has the shutter, the timer, the flip and the flash, and
    /// what it hands back goes down the same paths as a picked item — a
    /// picture straight to the uploader, a video through the trim sheet.
    struct CameraCapture: UIViewControllerRepresentable {
        enum Captured {
            case photo(Data)
            /// A copy in the temporary directory: the picker's own file is
            /// removed once it is dismissed.
            case movie(URL)
        }

        var allowsVideo = true
        let onCapture: (Captured) -> Void

        @Environment(\.dismiss) private var dismiss

        /// No camera on the simulator, or on a Mac running the iPad app.
        static var isAvailable: Bool {
            UIImagePickerController.isSourceTypeAvailable(.camera)
        }

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.mediaTypes =
                allowsVideo
                ? [UTType.image.identifier, UTType.movie.identifier] : [UTType.image.identifier]
            picker.videoQuality = .typeHigh
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(onCapture: onCapture, dismiss: { dismiss() })
        }

        final class Coordinator: NSObject, UIImagePickerControllerDelegate,
            UINavigationControllerDelegate
        {
            private let onCapture: (Captured) -> Void
            private let dismiss: () -> Void

            init(onCapture: @escaping (Captured) -> Void, dismiss: @escaping () -> Void) {
                self.onCapture = onCapture
                self.dismiss = dismiss
            }

            func imagePickerController(
                _ picker: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                if let url = info[.mediaURL] as? URL {
                    let copy = FileManager.default.temporaryDirectory
                        .appending(path: "camera-\(UUID().uuidString).\(url.pathExtension)")
                    if (try? FileManager.default.copyItem(at: url, to: copy)) != nil {
                        onCapture(.movie(copy))
                    }
                } else if let image = info[.originalImage] as? UIImage,
                    let data = image.jpegData(compressionQuality: 0.9)
                {
                    // JPEG rather than HEIC: every server takes it, and the
                    // uploader's own preflight brings it under the ceiling.
                    onCapture(.photo(data))
                }
                dismiss()
            }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                dismiss()
            }
        }
    }
#endif
