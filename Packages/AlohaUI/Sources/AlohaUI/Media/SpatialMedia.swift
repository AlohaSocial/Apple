// SPDX-License-Identifier: MIT

#if os(visionOS)
    import AVFoundation
    import AlohaDesign
    import ImageIO
    import RealityKit
    import SwiftUI
    import UniformTypeIdentifiers

    /// How a picture is shown in depth on Vision Pro.
    enum PictureDepth: Hashable {
        /// A spatial photo, in its own two eyes.
        case stereo
        /// A flat photo made into a spatial scene on the device.
        case scene
    }

    /// A picture in depth, filling the space it is given: a spatial photo as
    /// it was taken, or any photo turned into a spatial scene.
    ///
    /// On Vision Pro this is what the media viewer shows in place of the flat
    /// picture. A spatial photo used to open in Quick Look, a second window
    /// on top of the viewer, to be seen as what it is on the one device made
    /// for it.
    struct SpatialPicture: View {
        let file: URL
        let depth: PictureDepth
        var accessibilityText: String?
        /// Called when the picture cannot be shown in depth — a scene the
        /// device could not make, a file that is not what it said — so the
        /// viewer can go back to the flat one.
        var onFailure: () -> Void = {}

        @State private var entity = Entity()
        /// The picture's width over its height; zero until it is known.
        @State private var aspect: Float = 0
        @State private var isMakingScene = false

        var body: some View {
            // Read here, in the body, so a new size reaches `update`.
            let size = SIMD2(aspect * Self.screenHeight, Self.screenHeight)
            GeometryReader3D { geometry in
                RealityView { content in
                    content.add(entity)
                } update: { content in
                    DepthFit.fit(
                        entity, size: size, in: geometry.frame(in: .local), content: content)
                }
            }
            .overlay {
                if aspect == 0 || isMakingScene {
                    VStack(spacing: AlohaMetrics.space2) {
                        ProgressView()
                        if isMakingScene {
                            Text(
                                "Making a spatial scene…",
                                comment: "Shown while a flat photo is turned into a 3D scene"
                            )
                            .font(.callout)
                        }
                    }
                    .padding(AlohaMetrics.space4)
                    .glassBackgroundEffect()
                }
            }
            .accessibilityElement()
            .accessibilityLabel(
                accessibilityText.map { Text(verbatim: $0) }
                    ?? Text(
                        "Photo", comment: "Accessibility label for a picture without a description")
            )
            .accessibilityAddTraits(.isImage)
            .task(id: TaskKey(file: file, depth: depth)) { await present() }
        }

        /// The height the component is told its screen has, in metres. Only
        /// the proportion matters: `DepthFit` scales it to the window.
        private static let screenHeight: Float = 1

        private struct TaskKey: Hashable {
            let file: URL
            let depth: PictureDepth
        }

        private func present() async {
            aspect = 0
            entity.components.remove(ImagePresentationComponent.self)
            guard let measured = DepthFile.aspectRatio(of: file) else { return onFailure() }
            do {
                switch depth {
                case .stereo:
                    var component = try await ImagePresentationComponent(contentsOf: file)
                    component.screenHeight = Self.screenHeight
                    if component.availableViewingModes.contains(.spatialStereo) {
                        component.desiredViewingMode = .spatialStereo
                    }
                    entity.components.set(component)
                    aspect = measured

                case .scene:
                    let image = try await ImagePresentationComponent.Spatial3DImage(
                        contentsOf: file)
                    var component = ImagePresentationComponent(spatial3DImage: image)
                    component.screenHeight = Self.screenHeight
                    // The flat picture first, so there is something to look
                    // at while the scene is made.
                    entity.components.set(component)
                    aspect = measured
                    isMakingScene = true
                    defer { isMakingScene = false }
                    try await image.generate()
                    component.desiredViewingMode = .spatial3D
                    entity.components.set(component)
                }
            } catch {
                guard !Task.isCancelled else { return }
                onFailure()
            }
        }
    }

    /// A spatial video, in depth. Only for a video that is one
    /// (`SpatialVideo.isSpatial`): it has no transport of its own, and an
    /// ordinary video keeps the system player and its scrubber.
    struct SpatialVideoSurface: View {
        let player: AVPlayer

        @State private var entity = Entity()

        var body: some View {
            GeometryReader3D { geometry in
                RealityView { content in
                    var component = VideoPlayerComponent(avPlayer: player)
                    component.desiredViewingMode = .stereo
                    component.desiredSpatialVideoMode = .spatial
                    entity.components.set(component)
                    content.add(entity)
                } update: { content in
                    // Read through `observable`, so the fit is made again
                    // once the player knows the video's size.
                    let size =
                        entity.observable.components[VideoPlayerComponent.self]?.playerScreenSize
                        ?? .zero
                    DepthFit.fit(
                        entity, size: size, in: geometry.frame(in: .local), content: content)
                }
            }
            // A tap anywhere toggles the viewer's controls, as on the flat
            // player; the video itself is not a target.
            .contentShape(.rect)
        }
    }

    enum SpatialVideo {
        /// Whether the player's current video carries both eyes (MV-HEVC,
        /// as iPhone and Vision Pro record it).
        static func isSpatial(_ player: AVPlayer) async -> Bool {
            guard let asset = player.currentItem?.asset else { return false }
            let tracks = try? await asset.loadTracks(
                withMediaCharacteristic: .containsStereoMultiviewVideo)
            return tracks?.isEmpty == false
        }
    }

    @MainActor
    enum DepthFit {
        /// Scales `entity`, whose content is `size` metres across, to the
        /// largest size that fits `frame` and centres it there — what
        /// `.aspectRatio(contentMode: .fit)` does for a flat picture.
        static func fit(
            _ entity: Entity, size: SIMD2<Float>, in frame: Rect3D, content: RealityViewContent
        ) {
            guard size.x > 0, size.y > 0 else { return }
            let bounds = content.convert(frame, from: .local, to: .scene)
            let scale = min(bounds.extents.x / size.x, bounds.extents.y / size.y)
            entity.scale = SIMD3(scale, scale, 1)
            entity.position = SIMD3(bounds.center.x, bounds.center.y, bounds.min.z)
        }
    }

    enum DepthFile {
        /// The picture's width over its height, upright, read from its
        /// header without decoding it.
        static func aspectRatio(of file: URL) -> Float? {
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                    as? [CFString: Any],
                let width = properties[kCGImagePropertyPixelWidth] as? Int,
                let height = properties[kCGImagePropertyPixelHeight] as? Int,
                width > 0, height > 0
            else { return nil }
            // Orientations 5 to 8 turn the picture on its side.
            let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
            let isTurned = (5...8).contains(orientation)
            return isTurned ? Float(height) / Float(width) : Float(width) / Float(height)
        }

        /// A copy of `original` named with the extension its contents call
        /// for. The image cache's files have none, and RealityKit decides
        /// how to read a file by its name.
        @concurrent
        static func named(_ original: URL, id: String) async -> URL? {
            guard let source = CGImageSourceCreateWithURL(original as CFURL, nil),
                let type = CGImageSourceGetType(source),
                let ext = UTType(type as String)?.preferredFilenameExtension
            else { return nil }
            let safeName = id.filter { $0.isLetter || $0.isNumber }
            let copy = FileManager.default.temporaryDirectory
                .appending(path: "depth-\(safeName.isEmpty ? "photo" : safeName).\(ext)")
            if !FileManager.default.fileExists(atPath: copy.path()) {
                guard (try? FileManager.default.copyItem(at: original, to: copy)) != nil else {
                    return nil
                }
            }
            return copy
        }
    }
#endif
