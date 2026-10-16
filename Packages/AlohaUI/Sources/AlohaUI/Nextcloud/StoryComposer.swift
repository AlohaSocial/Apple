// SPDX-License-Identifier: MIT

import AVFoundation
import AlohaDesign
import AlohaMedia
import AlohaModels
import AlohaNetwork
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Posting a story: a picture or video from the library, or a few words on a
/// coloured card. Either way the server receives an ordinary media upload
/// and then `POST /api/v1/stories` — a text story is drawn here, at story
/// size, and uploaded as a picture with its words as the description
/// (docs/06 §6).
public struct StoryComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let onPosted: () -> Void
    private let preparer = MediaPreparer()

    enum Kind: Hashable {
        case media, text
    }

    @State private var kind: Kind = .media
    @State private var text = ""
    @State private var backgroundIndex = 0
    @State private var pickedItem: PhotosPickerItem?
    @State private var picture: CGImage?
    @State private var movie: URL?
    @State private var movieDuration: Double = 0
    @State private var stickers: [StorySticker] = []
    @State private var selectedSticker: StorySticker.ID?
    @State private var stickerText = ""
    @State private var caption = ""
    @State private var duration = 5
    @State private var isPosting = false
    @State private var isLoadingMedia = false
    @State private var errorMessage: String?

    static let canvas = CGSize(width: 1080, height: 1920)
    static let textLimit = 280
    static let captionLimit = 500
    static let stickerTextLimit = 60
    static let emojiStickers = ["😂", "😍", "🔥", "🎉", "👍", "❤️", "😮", "✨"]

    public init(session: AccountSession, onPosted: @escaping () -> Void = {}) {
        self.session = session
        self.onPosted = onPosted
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AlohaMetrics.space4) {
                    kindPicker

                    switch kind {
                    case .text: textEditor
                    case .media: mediaEditor
                    }

                    if kind == .media, picture != nil || movie != nil {
                        captionField
                        if picture != nil { durationPicker }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(palette.destructive)
                    }
                }
                .padding(AlohaMetrics.space4)
            }
            .background(palette.background)
            .navigationTitle(Text("New story", comment: "Story composer title"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", comment: "Sheet action")
                    }
                    .disabled(isPosting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await post() }
                    } label: {
                        if isPosting {
                            ProgressView()
                        } else {
                            Text("Share", comment: "Story composer action")
                        }
                    }
                    .disabled(!canPost || isPosting)
                }
            }
            .onChange(of: pickedItem) { _, item in
                Task { await load(item) }
            }
        }
        #if os(macOS)
            .frame(minWidth: 520, minHeight: 640)
        #endif
    }

    private var canPost: Bool {
        switch kind {
        case .text: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .media: picture != nil || movie != nil
        }
    }

    // MARK: - Kind

    private var kindPicker: some View {
        Picker(selection: $kind) {
            Text("Picture or video", comment: "Story kind").tag(Kind.media)
            Text("Text", comment: "Story kind").tag(Kind.text)
        } label: {
            Text("Story kind", comment: "Story composer picker")
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Text story

    private var textEditor: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
            GeometryReader { proxy in
                TextStoryCard(
                    text: text, gradient: gradients[backgroundIndex],
                    scale: proxy.size.width / Self.canvas.width)
            }
            .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
            .frame(maxWidth: 300)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: AlohaMetrics.cornerLarge, style: .continuous))

            TextField(
                String(localized: "Say something…", comment: "Text story field prompt"),
                text: $text, axis: .vertical
            )
            .lineLimit(2...6)
            .textFieldStyle(.roundedBorder)
            .onChange(of: text) { _, new in
                if new.count > Self.textLimit { text = String(new.prefix(Self.textLimit)) }
            }
            .accessibilityLabel(Text("Story text", comment: "Text story field label"))

            HStack {
                Text("\(text.count)/\(Self.textLimit)", comment: "Text story counter")
                    .font(AlohaType.meta)
                    .foregroundStyle(palette.tertiaryLabel)
                    .monospacedDigit()
                Spacer()
                backgroundPicker
            }
        }
    }

    /// Six backgrounds; the first is the reader's own accent.
    private var gradients: [[Color]] {
        [
            [palette.accent, palette.accentMuted],
            [Color(red: 0.98, green: 0.45, blue: 0.25), Color(red: 0.86, green: 0.22, blue: 0.55)],
            [Color(red: 0.16, green: 0.53, blue: 0.93), Color(red: 0.10, green: 0.75, blue: 0.70)],
            [Color(red: 0.24, green: 0.66, blue: 0.36), Color(red: 0.05, green: 0.33, blue: 0.24)],
            [Color(red: 0.55, green: 0.30, blue: 0.85), Color(red: 0.25, green: 0.20, blue: 0.60)],
            [Color(red: 0.25, green: 0.25, blue: 0.28), Color.black],
        ]
    }

    private var backgroundPicker: some View {
        HStack(spacing: AlohaMetrics.space2) {
            ForEach(gradients.indices, id: \.self) { index in
                Button {
                    backgroundIndex = index
                } label: {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradients[index], startPoint: .topLeading,
                                endPoint: .bottomTrailing)
                        )
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle().strokeBorder(
                                index == backgroundIndex ? palette.label : .clear, lineWidth: 2)
                        )
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text("Background \(index + 1)", comment: "Text story background")
                )
                .accessibilityAddTraits(
                    index == backgroundIndex ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    // MARK: - Media story

    @ViewBuilder
    private var mediaEditor: some View {
        if let picture {
            pictureEditor(picture)
        } else if movie != nil {
            movieSummary
        } else {
            // Read out here, not inside the label: `PhotosPicker`'s label
            // closure is `@Sendable`, so touching main-actor state from within
            // it crosses isolation. `Bool` and `Color` are `Sendable`, so
            // capturing the values costs nothing and says nothing untrue.
            let isLoading = isLoadingMedia
            let ink = palette.secondaryLabel
            let surface = palette.surfaceRaised

            PhotosPicker(selection: $pickedItem, matching: .any(of: [.images, .videos])) {
                VStack(spacing: AlohaMetrics.space2) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.largeTitle)
                        Text("Choose a picture or video", comment: "Story composer picker")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .background(
                    surface,
                    in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerLarge, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
    }

    private func pictureEditor(_ picture: CGImage) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
            GeometryReader { proxy in
                StoryPictureCanvas(
                    picture: picture, stickers: $stickers, selected: $selectedSticker,
                    scale: proxy.size.width / Self.canvas.width, isInteractive: true)
            }
            .aspectRatio(Self.canvas.width / Self.canvas.height, contentMode: .fit)
            .frame(maxWidth: 300)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: AlohaMetrics.cornerLarge, style: .continuous))

            HStack {
                Text("Stickers", comment: "Story composer section")
                    .font(AlohaType.section)
                Spacer()
                Button {
                    self.picture = nil
                    pickedItem = nil
                    stickers = []
                } label: {
                    Text("Change", comment: "Story composer action")
                        .font(.footnote)
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: AlohaMetrics.space1) {
                    ForEach(Self.emojiStickers, id: \.self) { emoji in
                        Button {
                            add(.emoji(emoji))
                        } label: {
                            Text(emoji)
                                .font(.title)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Add \(emoji) sticker", comment: "Story sticker"))
                    }
                }
            }
            .scrollIndicators(.hidden)

            HStack(spacing: AlohaMetrics.space2) {
                TextField(
                    String(localized: "Text sticker", comment: "Story sticker field prompt"),
                    text: $stickerText
                )
                .textFieldStyle(.roundedBorder)
                .onChange(of: stickerText) { _, new in
                    if new.count > Self.stickerTextLimit {
                        stickerText = String(new.prefix(Self.stickerTextLimit))
                    }
                }
                .accessibilityLabel(Text("Text sticker", comment: "Story sticker field label"))
                Button {
                    let trimmed = stickerText.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    add(.text(trimmed))
                    stickerText = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(stickerText.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel(Text("Add text sticker", comment: "Story sticker action"))
            }

            if let selectedSticker, stickers.contains(where: { $0.id == selectedSticker }) {
                Button(role: .destructive) {
                    stickers.removeAll { $0.id == selectedSticker }
                    self.selectedSticker = nil
                } label: {
                    Label {
                        Text("Remove selected sticker", comment: "Story sticker action")
                    } icon: {
                        Image(systemName: AlohaSymbol.delete)
                    }
                    .font(.footnote)
                }
            }

            Text(
                "Drag a sticker to place it. It is drawn into the picture when you share.",
                comment: "Story sticker hint"
            )
            .font(.caption)
            .foregroundStyle(palette.tertiaryLabel)
        }
    }

    private var movieSummary: some View {
        HStack(spacing: AlohaMetrics.space3) {
            Image(systemName: AlohaSymbol.video)
                .font(.title2)
                .foregroundStyle(palette.secondaryLabel)
            VStack(alignment: .leading, spacing: 2) {
                Text("Video", comment: "Story composer media kind")
                    .font(.subheadline.weight(.medium))
                Text(
                    Duration.seconds(movieDuration), format: .time(pattern: .minuteSecond)
                )
                .font(AlohaType.meta)
                .foregroundStyle(palette.tertiaryLabel)
                if movieDuration > 30 {
                    Text(
                        "Stories stop at 30 seconds; the server keeps the start.",
                        comment: "Story composer video length warning"
                    )
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                }
            }
            Spacer()
            Button {
                movie = nil
                pickedItem = nil
            } label: {
                Text("Change", comment: "Story composer action")
                    .font(.footnote)
            }
        }
        .padding(AlohaMetrics.space3)
        .background(
            palette.surfaceRaised,
            in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous))
    }

    private var captionField: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
            TextField(
                String(localized: "Caption (optional)", comment: "Story caption prompt"),
                text: $caption, axis: .vertical
            )
            .lineLimit(1...4)
            .textFieldStyle(.roundedBorder)
            .onChange(of: caption) { _, new in
                if new.count > Self.captionLimit { caption = String(new.prefix(Self.captionLimit)) }
            }
            .accessibilityLabel(Text("Caption", comment: "Story caption label"))
            Text("\(caption.count)/\(Self.captionLimit)", comment: "Story caption counter")
                .font(AlohaType.meta)
                .foregroundStyle(palette.tertiaryLabel)
                .monospacedDigit()
        }
    }

    private var durationPicker: some View {
        Picker(selection: $duration) {
            Text("5 s", comment: "Story duration").tag(5)
            Text("10 s", comment: "Story duration").tag(10)
            Text("15 s", comment: "Story duration").tag(15)
        } label: {
            Text("Shown for", comment: "Story duration picker")
        }
        .pickerStyle(.segmented)
    }

    private func add(_ content: StorySticker.Content) {
        let sticker = StorySticker(content: content, position: CGPoint(x: 0.5, y: 0.5))
        stickers.append(sticker)
        selectedSticker = sticker.id
    }

    // MARK: - Loading

    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isLoadingMedia = true
        defer { isLoadingMedia = false }
        errorMessage = nil

        let type = item.supportedContentTypes.first
        if type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true {
            guard let picked = try? await item.loadTransferable(type: PickedMovie.self) else {
                errorMessage = String(
                    localized: "That video couldn't be read.", comment: "Story composer failure")
                return
            }
            movie = picked.url
            let seconds = (try? await AVURLAsset(url: picked.url).load(.duration).seconds) ?? 0
            movieDuration = seconds.isFinite ? seconds : 0
            picture = nil
            return
        }

        guard let data = try? await item.loadTransferable(type: Data.self),
            let image = Self.decodeImage(data)
        else {
            errorMessage = String(
                localized: "That picture couldn't be read.", comment: "Story composer failure")
            return
        }
        picture = image
        movie = nil
        stickers = []
    }

    /// Bounded to the story canvas, and rotated the way the camera meant it.
    static func decodeImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(canvas.height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - Posting

    private func post() async {
        guard canPost, !isPosting else { return }
        isPosting = true
        defer { isPosting = false }
        errorMessage = nil

        do {
            let mediaID: String
            var storyDuration = duration
            switch kind {
            case .text:
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard
                    let jpeg = await render(
                        TextStoryCard(
                            text: trimmed, gradient: gradients[backgroundIndex], scale: 1))
                else { throw StoryComposerError.rendering }
                let attachment = try await upload(
                    jpeg, filename: "story.jpg", mimeType: "image/jpeg")
                // The words are the picture's description, so a reader who
                // cannot see it still gets them.
                _ = try? await session.client.send(
                    Endpoint.media.updateDescription(attachment.id, description: trimmed))
                mediaID = attachment.id
            case .media:
                if let picture {
                    guard
                        let jpeg = await render(
                            StoryPictureCanvas(
                                picture: picture, stickers: .constant(stickers),
                                selected: .constant(nil),
                                scale: 1, isInteractive: false))
                    else { throw StoryComposerError.rendering }
                    let attachment = try await upload(
                        jpeg, filename: "story.jpg", mimeType: "image/jpeg")
                    mediaID = attachment.id
                } else if let movie {
                    let prepared = try await prepareStoryVideo(at: movie)
                    let attachment = try await upload(
                        prepared.data, filename: prepared.filename,
                        mimeType: prepared.mimeType)
                    mediaID = attachment.id
                    storyDuration = Int(
                        min(max(movieDuration, 3), 30).rounded(.up))
                } else {
                    return
                }
            }

            let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await session.client.send(
                Endpoint.stories.post(
                    mediaID: mediaID, caption: trimmedCaption.isEmpty ? nil : trimmedCaption,
                    duration: storyDuration))
            onPosted()
            dismiss()
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? StoryComposerError)?.errorDescription
                ?? (error as? APIError)?.errorDescription
                ?? String(
                    localized: "That story couldn't be shared.", comment: "Story composer failure")
        }
    }

    /// A story video, in whatever container the server will actually take.
    ///
    /// The picker hands back whatever the camera recorded — usually QuickTime,
    /// which a server configured for MP4 refuses with a 422 after the bytes
    /// have already been sent. Asking first turns that into a local decision:
    /// the file goes out as-is when it fits, through the exporter when it does
    /// not, and never at all when it is over the ceiling.
    private func prepareStoryVideo(at url: URL) async throws -> MediaPreparer.Prepared {
        let mimeType = preparer.mimeType(for: url)
        let size =
            ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int)
            ?? 0

        switch UploadPreflight.check(
            fileSize: size, mimeType: mimeType, limits: session.capabilities.limits)
        {
        case .ready:
            let data = try Data(contentsOf: url)
            return MediaPreparer.Prepared(
                data: data, filename: url.lastPathComponent, mimeType: mimeType)

        case .needsTranscode:
            // Stories stop at 30 seconds, so the export may as well be where
            // the clip gets cut rather than leaving it for the server to
            // disagree about later.
            let trim: ClosedRange<Double>? = movieDuration > 30 ? 0.0...30.0 : nil
            return try await preparer.prepareVideo(at: url, trim: trim, quality: .high)

        case .tooLarge(let size, let limit, _):
            throw StoryComposerError.message(
                UploadPreflight.explanation(
                    for: .tooLarge(
                        size: size, limit: limit, isVideo: true))
                    ?? String(
                        localized: "That story couldn't be shared.",
                        comment: "Story composer failure"))

        case .unsupported(let mimeType):
            throw StoryComposerError.message(
                UploadPreflight.explanation(for: .unsupported(mimeType: mimeType))
                    ?? String(
                        localized: "That story couldn't be shared.",
                        comment: "Story composer failure"))
        }
    }

    private func upload(
        _ data: Data, filename: String, mimeType: String
    ) async throws -> MediaAttachment {
        do {
            return try await session.client.decode(
                MediaAttachment.self,
                from: Endpoint.media.upload(
                    data: data, filename: filename, mimeType: mimeType, description: nil, v2: true))
        } catch APIError.notFound {
            return try await session.client.decode(
                MediaAttachment.self,
                from: Endpoint.media.upload(
                    data: data, filename: filename, mimeType: mimeType, description: nil, v2: false)
            )
        }
    }

    /// Draws a story-sized view to JPEG bytes.
    @MainActor
    private func render<Content: View>(_ content: Content) async -> Data? {
        let renderer = ImageRenderer(
            content:
                content
                .frame(width: Self.canvas.width, height: Self.canvas.height)
                .environment(\.alohaPalette, palette))
        renderer.proposedSize = ProposedViewSize(Self.canvas)
        renderer.scale = 1
        guard let image = renderer.cgImage else { return nil }
        return Self.encodeJPEG(image)
    }

    static func encodeJPEG(_ image: CGImage, quality: CGFloat = 0.88) -> Data? {
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

enum StoryComposerError: Error, LocalizedError {
    case rendering
    case message(String)

    var errorDescription: String? {
        switch self {
        case .rendering: nil
        case .message(let text): text
        }
    }
}

/// Something laid over a picture: an emoji or a few words, at a point
/// expressed as a fraction of the canvas so it lands in the same place at
/// preview size and at export size.
struct StorySticker: Identifiable, Hashable {
    enum Content: Hashable {
        case emoji(String)
        case text(String)
    }

    let id = UUID()
    var content: Content
    var position: CGPoint

    var label: String {
        switch content {
        case .emoji(let emoji): emoji
        case .text(let text): text
        }
    }
}

/// A few words on a gradient, at any scale: `scale` 1 is the 1080×1920 export.
struct TextStoryCard: View {
    let text: String
    let gradient: [Color]
    let scale: Double

    /// Shorter texts are set larger; the size steps down as the words grow.
    private var pointSize: Double {
        let count = text.count
        let base: Double = count < 40 ? 96 : count < 100 ? 72 : count < 180 ? 56 : 44
        return base * scale
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(
                text.isEmpty
                    ? String(localized: "Your words here", comment: "Text story placeholder") : text
            )
            .font(.system(size: pointSize, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(text.isEmpty ? 0.6 : 1))
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.25), radius: 6 * scale, y: 2 * scale)
            .padding(96 * scale)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Text story: \(text)", comment: "Text story preview label"))
    }
}

/// The picture with its stickers on it. Interactive at preview size, so
/// stickers can be dragged; inert at export size, so the same layout is
/// what gets drawn into the file.
struct StoryPictureCanvas: View {
    let picture: CGImage
    @Binding var stickers: [StorySticker]
    @Binding var selected: StorySticker.ID?
    let scale: Double
    let isInteractive: Bool

    private var size: CGSize {
        CGSize(
            width: StoryComposerSheet.canvas.width * scale,
            height: StoryComposerSheet.canvas.height * scale)
    }

    var body: some View {
        ZStack {
            Image(decorative: picture, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()

            ForEach(stickers) { sticker in
                stickerView(sticker)
                    .position(
                        x: sticker.position.x * size.width, y: sticker.position.y * size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { if isInteractive { selected = nil } }
    }

    private func stickerView(_ sticker: StorySticker) -> some View {
        Group {
            switch sticker.content {
            case .emoji(let emoji):
                Text(emoji).font(.system(size: 160 * scale))
            case .text(let text):
                Text(text)
                    .font(.system(size: 64 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28 * scale)
                    .padding(.vertical, 14 * scale)
                    .background(.black.opacity(0.55), in: Capsule())
            }
        }
        .overlay {
            if isInteractive && selected == sticker.id {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white, style: StrokeStyle(lineWidth: 2, dash: [4]))
                    .padding(-6)
            }
        }
        .frame(minWidth: isInteractive ? 44 : 0, minHeight: isInteractive ? 44 : 0)
        .contentShape(Rectangle())
        .gesture(isInteractive ? drag(sticker) : nil)
        .accessibilityLabel(Text("Sticker \(sticker.label)", comment: "Story sticker label"))
        .accessibilityAddTraits(isInteractive ? .isButton : [])
    }

    private func drag(_ sticker: StorySticker) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                selected = sticker.id
                guard let index = stickers.firstIndex(where: { $0.id == sticker.id }) else {
                    return
                }
                stickers[index].position = CGPoint(
                    x: min(max(value.location.x / size.width, 0.05), 0.95),
                    y: min(max(value.location.y / size.height, 0.05), 0.95))
            }
    }
}

/// The leading tile of the stories rail: your own face, with a plus badge
/// that opens the composer. Presents its own sheet, so the rail needs no
/// state of its own.
struct StoryComposerTile: View {
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession
    /// The viewer's own live stories, if any: the tile then plays them.
    let ownStories: [Story]
    let onPlay: () -> Void
    let onPosted: () -> Void

    @State private var isComposing = false

    var body: some View {
        VStack(spacing: AlohaMetrics.space1) {
            ZStack(alignment: .bottomTrailing) {
                Button {
                    if ownStories.isEmpty { isComposing = true } else { onPlay() }
                } label: {
                    AvatarView(account: session.snapshot.asAccount, size: 60)
                        .padding(3)
                        .overlay(
                            Circle().strokeBorder(
                                ownStories.isEmpty ? palette.separator : palette.accent,
                                lineWidth: ownStories.isEmpty ? 1 : 2.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    ownStories.isEmpty
                        ? Text("Add a story", comment: "Story rail action")
                        : Text("Your story", comment: "Story rail tile"))

                Button {
                    isComposing = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.onAccent)
                        .frame(width: 22, height: 22)
                        .background(palette.accent, in: Circle())
                        .overlay(Circle().strokeBorder(palette.background, lineWidth: 2))
                        .frame(width: 44, height: 44, alignment: .bottomTrailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: 6)
                .accessibilityLabel(Text("Add a story", comment: "Story rail action"))
            }

            if let views = ownStories.compactMap(\.viewCount).max(), !ownStories.isEmpty {
                Label {
                    Text(views, format: .number)
                } icon: {
                    Image(systemName: AlohaSymbol.reveal)
                }
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: 66)
                .accessibilityLabel(
                    Text("^[\(views) view](inflect: true)", comment: "Story view count"))
            } else {
                Text("Your story", comment: "Story rail tile")
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 66)
            }
        }
        .sheet(isPresented: $isComposing) {
            StoryComposerSheet(session: session, onPosted: onPosted)
        }
    }
}
