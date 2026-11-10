// SPDX-License-Identifier: MIT

#if os(iOS)
    import AVFoundation
    import AlohaDesign
    import SwiftUI
    import UIKit

    /// The story's canvas as a live camera: the viewfinder fills the same
    /// 9:16 frame the story will be shared in, and the shutter takes the
    /// picture straight into the editor. Choosing a file from the library
    /// stays one tap away for when the camera is pointed at the wrong thing.
    struct StoryCameraCanvas: View {
        @Environment(\.alohaPalette) private var palette

        let onCapture: (Data) -> Void
        let onPickLibrary: () -> Void

        @StateObject private var camera = StoryCameraController()
        @State private var isCapturing = false

        var body: some View {
            ZStack {
                StoryCameraPreview(session: camera.session)
                    .opacity(camera.isReady ? 1 : 0)

                LinearGradient(
                    colors: [.black.opacity(0.5), .clear, .black.opacity(0.6)],
                    startPoint: .top, endPoint: .bottom)

                if !camera.isReady {
                    VStack(spacing: AlohaMetrics.space2) {
                        Image(systemName: camera.isDenied ? "camera.badge.ellipsis" : "camera")
                            .font(.system(size: 38, weight: .light))
                        Text(
                            camera.isDenied
                                ? String(
                                    localized: "Camera access is off",
                                    comment: "Story camera state")
                                : String(
                                    localized: "Starting camera…",
                                    comment: "Story camera state")
                        )
                        .font(.footnote.weight(.medium))
                        if camera.isDenied {
                            Button("Choose from library", action: onPickLibrary)
                                .buttonStyle(.bordered)
                                .tint(.white)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(AlohaMetrics.space4)
                }

                VStack {
                    HStack {
                        Button(action: onPickLibrary) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.28), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            Text("Choose from library", comment: "Story camera action"))

                        Spacer()

                        Text("LIVE", comment: "Story camera badge")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.28), in: Capsule())
                            .accessibilityHidden(true)
                    }
                    .padding(AlohaMetrics.space3)

                    Spacer()

                    Button {
                        capture()
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(.white, lineWidth: 4)
                                .frame(width: 70, height: 70)
                            Circle()
                                .fill(.white)
                                .frame(width: 56, height: 56)
                            if isCapturing { ProgressView().tint(.black) }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!camera.isReady || isCapturing)
                    .opacity(camera.isReady ? 1 : 0.4)
                    .accessibilityLabel(Text("Take a photo", comment: "Story camera action"))
                    .padding(.bottom, AlohaMetrics.space4)
                }
            }
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: AlohaMetrics.cornerLarge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AlohaMetrics.cornerLarge, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Live camera preview", comment: "Story camera"))
            .accessibilityIdentifier("story.camera")
            .task { await camera.start() }
            .onDisappear { camera.stop() }
        }

        private func capture() {
            guard !isCapturing else { return }
            isCapturing = true
            Task {
                if let data = await camera.capture() { onCapture(data) }
                isCapturing = false
            }
        }
    }

    private struct StoryCameraPreview: UIViewRepresentable {
        let session: AVCaptureSession

        func makeUIView(context: Context) -> StoryCameraPreviewView {
            let view = StoryCameraPreviewView()
            view.previewLayer.session = session
            view.previewLayer.videoGravity = .resizeAspectFill
            return view
        }

        func updateUIView(_ uiView: StoryCameraPreviewView, context: Context) {
            if uiView.previewLayer.session !== session {
                uiView.previewLayer.session = session
            }
        }
    }

    private final class StoryCameraPreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            // The layer class above is the only one this view can have.
            layer as! AVCaptureVideoPreviewLayer
        }
    }

    @MainActor
    private final class StoryCameraController: NSObject, ObservableObject,
        AVCapturePhotoCaptureDelegate
    {
        let session = AVCaptureSession()
        @Published private(set) var isReady = false
        @Published private(set) var isDenied = false

        private let output = AVCapturePhotoOutput()
        private var isConfigured = false
        private var pending: CheckedContinuation<Data?, Never>?

        func start() async {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                break
            case .notDetermined:
                guard await AVCaptureDevice.requestAccess(for: .video) else {
                    isDenied = true
                    return
                }
            default:
                isDenied = true
                return
            }
            configure()
        }

        private func configure() {
            guard !isConfigured else { return }
            isConfigured = true
            session.beginConfiguration()
            session.sessionPreset = .photo
            let device =
                AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            if let device, let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            {
                session.addInput(input)
            }
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            guard !session.inputs.isEmpty else { return }
            session.startRunning()
            isReady = true
        }

        func capture() async -> Data? {
            guard isReady else { return nil }
            return await withCheckedContinuation { continuation in
                pending = continuation
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }

        func stop() {
            guard session.isRunning else { return }
            session.stopRunning()
        }

        nonisolated func photoOutput(
            _ output: AVCapturePhotoOutput,
            didFinishProcessingPhoto photo: AVCapturePhoto,
            error: Error?
        ) {
            let data = error == nil ? photo.fileDataRepresentation() : nil
            Task { @MainActor in
                self.pending?.resume(returning: data)
                self.pending = nil
            }
        }
    }
#endif
