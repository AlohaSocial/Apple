// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaIntelligence
import AlohaMedia
import AlohaModels
import AlohaNetwork
import AlohaStore
import PhotosUI
import SwiftUI

#if canImport(ImagePlayground) && !os(tvOS) && !os(watchOS)
    import ImagePlayground
#endif

public struct ComposerView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.composerHost) private var host
    @State private var didSend = false
    @State private var showsCardOptions = false
    @State private var isShowingPollEditor = false

    @State private var model: ComposerModel
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var isShowingSchedule = false
    @State private var isShowingNextcloudFiles = false
    @State private var isShowingPlacePicker = false
    @State private var isShowingGIFPicker = false
    @State private var isShowingEmojiPicker = false
    @State private var isShowingHeldNotice = false
    @State private var focusingAttachment: MediaAttachment?
    @State private var filteringAttachment: MediaAttachment?
    @State private var trimmingVideoAt: URL?
    @State private var rewritingStyle: RewriteStyle?
    @State private var isShowingCamera = false
    @FocusState private var isEditorFocused: Bool
    /// Set once the composer has ended on purpose — posted, or cancelled with
    /// the draft saved — so the disappearance that follows is not mistaken
    /// for one that would lose the words.
    @State private var didFinish = false
    @State private var selection: TextSelection?
    @State private var isShowingImagePlayground = false
    #if canImport(ImagePlayground) && !os(tvOS) && !os(watchOS)
        @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    #endif
    /// An edit's text as it arrived, so closing an unchanged edit needs no
    /// guard while closing a changed one does.
    private let editBaseline: String?

    private let prefilledText: String
    private let prefilledAttachments: [PrefilledAttachment]

    /// Bytes handed over by the share extension, uploaded once the composer
    /// appears so the sheet is on screen while they go up.
    public struct PrefilledAttachment: Sendable, Hashable {
        public var data: Data
        public var filename: String
        public var mimeType: String

        public init(data: Data, filename: String, mimeType: String) {
            self.data = data
            self.filename = filename
            self.mimeType = mimeType
        }
    }

    /// Editing loads the original plain text from `/source`, never the
    /// rendered HTML (docs/07 §8).
    public init(session: AccountSession, editing status: Status, source: StatusSource) {
        self.quoting = nil
        self.prefilledText = ""
        self.prefilledAttachments = []
        self.editBaseline = source.text
        _model = State(
            initialValue: ComposerModel(session: session, editing: status, source: source))
    }

    /// Reopens a saved draft, as it was left.
    public init(session: AccountSession, draft: DraftSnapshot) {
        self.quoting = nil
        self.prefilledText = ""
        self.prefilledAttachments = []
        self.editBaseline = nil
        _model = State(initialValue: ComposerModel(session: session, draft: draft))
    }

    /// Delete & redraft: the post's words from `/source`, in a fresh composer.
    /// The original is deleted only once this one posts.
    public init(session: AccountSession, redrafting status: Status, source: StatusSource) {
        self.quoting = nil
        self.prefilledText = ""
        self.prefilledAttachments = []
        self.editBaseline = nil
        _model = State(
            initialValue: ComposerModel(session: session, redrafting: status, source: source))
    }

    /// The post being quoted, when the composer opened for a quote.
    private let quoting: Status?

    public init(
        session: AccountSession, replyTo: Status? = nil, quoting: Status? = nil,
        prefilledText: String = "", prefilledAttachments: [PrefilledAttachment] = []
    ) {
        self.quoting = quoting
        self.prefilledText = prefilledText
        self.prefilledAttachments = prefilledAttachments
        self.editBaseline = nil
        _model = State(
            initialValue: ComposerModel(session: session, replyTo: replyTo, quoting: quoting))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.redrafting != nil { redraftNote }
                if let replyTo = model.replyTo { replyContext(replyTo) }
                if let quoting = model.quoting { quoteCard(quoting) }
                if model.showsContentWarningField {
                    contentWarningField
                    ContentWarningPresets(spoilerText: $model.spoilerText)
                }

                editor

                if !model.pendingGames.isEmpty { gamesHint }
                if model.canBeCard && (showsCardOptions || model.cardBackgroundID != nil) {
                    cardRow
                }

                if let place = model.place { placeChip(place) }
                if model.isNextcloud && model.hasVideoAttachment { videoMetaFields }

                if !model.uploader.progress.items.isEmpty && !model.uploader.progress.isFinished {
                    uploadProgress
                }
                if let message = model.uploader.errorMessage { uploadError(message) }
                if let message = model.errorMessage { uploadError(message) }
                if let scheduledAt = model.scheduledAt { scheduleBanner(scheduledAt) }
                if !model.attachments.isEmpty { mediaStrip }
                if !model.threadSegments.isEmpty { threadEditor }
                if model.hasPoll {
                    Button {
                        isShowingPollEditor = true
                    } label: {
                        Label {
                            Text("Edit poll", comment: "Composer action")
                        } icon: {
                            Image(systemName: AlohaSymbol.poll)
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(AlohaMetrics.space2)
                }

                toolbar
                if host?.showsInlineActions == true { inlineActions }
            }
            .background(palette.background)
            .sensoryFeedback(.success, trigger: didSend)
            #if !os(tvOS) && !os(watchOS)
                // A picture or a video dragged in from Photos, Files or
                // another app is an attachment, the same as one picked.
                .dropDestination(for: DroppedMedia.self) { items, _ in
                    guard model.canAddMedia, !items.isEmpty else { return false }
                    Task { await attach(items) }
                    return true
                }
            #endif
            .navigationTitle(model.title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if host?.showsInlineActions != true {
                    ToolbarItem(placement: .cancellationAction) { cancelButton }
                    ToolbarItem(placement: .confirmationAction) { postButton }
                }
            }
            .alert(
                Text("Some media has no description", comment: "Alt text warning title"),
                isPresented: $model.isShowingAltTextWarning
            ) {
                Button {
                    Task { await send(skippingAltTextCheck: true) }
                } label: {
                    Text("Post anyway", comment: "Alt text warning action")
                }
                Button(role: .cancel) {
                } label: {
                    Text("Let me add it", comment: "Alt text warning action")
                }
            } message: {
                // It warns; it never blocks (docs/07 §4).
                Text(
                    "Descriptions let people using a screen reader know what you posted.",
                    comment: "Alt text warning detail")
            }
            .photosPicker(
                isPresented: $model.isShowingMediaPicker,
                selection: $pickedItems,
                maxSelectionCount: model.limits.maxMediaAttachments,
                matching: .any(of: [.images, .videos])
            )
            .onChange(of: pickedItems) { _, items in
                Task { await ingest(items) }
            }
            .sheet(isPresented: $isShowingPollEditor) {
                NavigationStack {
                    ScrollView { pollEditor }
                        .navigationTitle(Text("Poll", comment: "Poll editor title"))
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button {
                                    isShowingPollEditor = false
                                } label: {
                                    Text("Done", comment: "Sheet action")
                                }
                            }
                            ToolbarItem(placement: .cancellationAction) {
                                Button(role: .destructive) {
                                    model.pollOptions = []
                                    isShowingPollEditor = false
                                } label: {
                                    Text("Remove poll", comment: "Poll editor action")
                                }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $filteringAttachment) { attachment in
                PhotoFilterSheet(attachment: attachment, uploader: model.uploader)
            }
            .sheet(item: $focusingAttachment) { attachment in
                FocalPointEditor(
                    attachment: attachment, initial: model.focalPoints[attachment.id]
                ) { point in
                    Task { await model.setFocalPoint(point, for: attachment) }
                }
            }
            // A held post is not a failure: it is published once somebody has
            // looked at it, and the person should hear that rather than watch
            // it vanish (the server's own rule for its review queue).
            .alert(
                Text("Waiting to be looked at", comment: "Held for review title"),
                isPresented: $isShowingHeldNotice
            ) {
                Button {
                    finish(.posted)
                } label: {
                    Text("OK", comment: "Held for review action")
                }
            } message: {
                Text(
                    "Your post is with a moderator and will appear once it has been looked at. You can find it under Settings until then.",
                    comment: "Held for review detail")
            }
            .sheet(isPresented: $isShowingNextcloudFiles) {
                if let credentials = nextcloudCredentials {
                    NextcloudFileBrowser(
                        credentials: credentials,
                        acceptedTypes: model.limits.supportedMIMETypes
                    ) { file in
                        Task {
                            await model.uploader.addFromNextcloudFiles(
                                path: file.path, description: nil)
                        }
                    }
                } else {
                    // No Nextcloud connection: a path still works, because the
                    // server resolves it. Browsing is what needs credentials.
                    NextcloudFilePicker { path in
                        Task {
                            await model.uploader.addFromNextcloudFiles(
                                path: path, description: nil)
                        }
                    }
                }
            }
            .sheet(
                item: Binding(
                    get: { trimmingVideoAt.map { TrimRequest(url: $0) } },
                    set: { trimmingVideoAt = $0?.url })
            ) { request in
                VideoTrimView(url: request.url, limits: model.limits) { prepared in
                    Task { await model.uploader.add(prepared: prepared) }
                }
            }
            // A rewrite is proposed beside what was written, never applied in
            // place: the words are the person's until they choose otherwise
            // (docs/10 §3).
            .sheet(item: $rewritingStyle) { style in
                RewriteSheet(
                    original: model.text, style: style,
                    maximumCharacters: model.limits.maxStatusCharacters,
                    intelligence: environment.intelligence
                ) { proposal in
                    model.text = proposal
                }
            }
            #if os(iOS)
                .fullScreenCover(isPresented: $isShowingCamera) {
                    CameraCapture { captured in
                        switch captured {
                        case .photo(let data):
                            Task {
                                await model.uploader.add(
                                    data: data, filename: "camera-\(UUID().uuidString).jpg",
                                    mimeType: "image/jpeg")
                            }
                        case .movie(let url):
                            // The same trim sheet a picked video goes through.
                            trimmingVideoAt = url
                        }
                    }
                    .ignoresSafeArea()
                }
            #endif
            .sheet(item: $model.isShowingAltTextFor) { attachment in
                AltTextEditor(attachment: attachment) { description in
                    Task { await model.uploader.updateDescription(description, for: attachment.id) }
                }
            }
            .task {
                await model.prepare()
                if !prefilledText.isEmpty { model.text = prefilledText }
                for attachment in prefilledAttachments {
                    await model.uploader.add(
                        data: attachment.data, filename: attachment.filename,
                        mimeType: attachment.mimeType)
                }
            }
            .onAppear { isEditorFocused = true }
            // Handoff carries a new post's text to the other device. A reply,
            // a quote or an edit is not offered: the post it belongs to does
            // not travel with it, and without it the text would land as a new
            // top-level post.
            .userActivity(
                Continuity.composing,
                isActive: model.replyTo == nil && model.quoting == nil
                    && model.editingStatus == nil && !model.text.isEmpty
            ) { activity in
                Continuity.configureComposing(
                    activity, draft: model.text, account: AccountIdentity(session: model.session))
            }
        }
        .interactiveDismissDisabled(dismissal.isGuarded && !didFinish)
        // Every way out that is not Post or Cancel — the shell replacing the
        // sheet, the account changing underneath it, a window closing — still
        // keeps what was written.
        .onDisappear {
            guard !didFinish else { return }
            UploadActivityController.shared.cancel()
            Task { await model.saveDraftIfNeeded() }
        }
    }

    private var dismissal: ComposerDismissal {
        ComposerDismissal(
            text: model.text, spoilerText: model.spoilerText,
            hasAttachments: !model.attachments.isEmpty, hasPoll: model.hasPoll,
            threadSegments: model.threadSegments, editBaseline: editBaseline)
    }

    // MARK: - Posting

    private func send(skippingAltTextCheck: Bool = false) async {
        guard await model.post(skippingAltTextCheck: skippingAltTextCheck) else { return }
        if model.wasHeldForReview {
            isShowingHeldNotice = true
        } else {
            didSend.toggle()
            finish(.posted)
        }
    }

    /// Done, one way or the other: the host's own ending where there is one
    /// (a share extension), otherwise the sheet's.
    private func finish(_ outcome: ComposerOutcome) {
        didFinish = true
        if let host {
            host.finish(outcome)
        } else {
            dismiss()
        }
    }

    // MARK: - Actions

    private var cancelButton: some View {
        Button {
            close()
        } label: {
            Text("Cancel", comment: "Composer action")
                .foregroundStyle(palette.label)
        }
        .keyboardShortcut(.cancelAction)
    }

    private var postButton: some View {
        Button {
            Task { await send() }
        } label: {
            if model.isPosting {
                ProgressView()
            } else {
                Text("Post", comment: "Composer action")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .alohaGlassProminentButtonStyle()
        .tint(palette.accent)
        .disabled(!model.canPost)
        .keyboardShortcut(.return, modifiers: .command)
    }

    /// Cancel and Post under the composer, for a host whose toolbar is not
    /// the composer's to fill (`ComposerHost.showsInlineActions`).
    private var inlineActions: some View {
        HStack {
            cancelButton
            Spacer()
            postButton
        }
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.vertical, AlohaMetrics.space3)
    }

    // MARK: - Pieces

    /// Said before posting, not after: the favourites, boosts and replies the
    /// original gathered do not follow it to the new post.
    private var redraftNote: some View {
        Label {
            Text(
                "Posting this deletes the original, with its favourites, boosts and replies.",
                comment: "Composer note when redrafting")
        } icon: {
            Image(systemName: "arrow.uturn.backward.circle")
        }
        .font(.caption)
        .foregroundStyle(palette.secondaryLabel)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.vertical, AlohaMetrics.space2)
        .background(palette.surfaceRaised)
    }

    /// The post being quoted, as a card the way it will sit under the new
    /// one. Nothing about it is editable here.
    private func quoteCard(_ status: Status) -> some View {
        let target = status.displayed
        return HStack(alignment: .top, spacing: AlohaMetrics.space2) {
            Image(systemName: "text.quote")
                .font(.caption)
                .foregroundStyle(palette.secondaryLabel)
            VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                HStack(spacing: AlohaMetrics.space2) {
                    AvatarView(account: target.account, size: 22)
                    Text(target.account.bestDisplayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(target.account.qualifiedHandle(localHost: nil))
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                RichTextView(status: status, lineLimit: 3)
                    .font(.footnote)
                if !target.mediaAttachments.isEmpty {
                    Label {
                        Text(
                            "^[\(target.mediaAttachments.count) attachment](inflect: true)",
                            comment: "Quote card media count")
                    } icon: {
                        Image(systemName: AlohaSymbol.media)
                    }
                    .font(.caption2)
                    .foregroundStyle(palette.tertiaryLabel)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AlohaMetrics.space3)
        .background(palette.surfaceRaised)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("Quoting \(target.account.bestDisplayName)", comment: "Composer quote context"))
    }

    private func placeChip(_ place: ComposerModel.ComposerPlace) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Label {
                Text(place.displayName)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "mappin.and.ellipse")
            }
            .font(.footnote)
            .foregroundStyle(palette.accent)
            Spacer()
            Button {
                withAnimation { model.place = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(palette.tertiaryLabel)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove place", comment: "Composer action"))
        }
        .padding(.horizontal, AlohaMetrics.space4)
        .background(palette.surfaceRaised)
    }

    /// PeerTube-style metadata for a video, sent alongside the post so a
    /// federated PeerTube shows a title rather than the first line of text.
    private var videoMetaFields: some View {
        VStack(spacing: AlohaMetrics.space2) {
            TextField(
                text: $model.videoTitle,
                prompt: Text("Video title", comment: "Composer video field placeholder")
            ) {
                Text("Video title", comment: "Composer video field label")
            }
            HStack(spacing: AlohaMetrics.space2) {
                TextField(
                    text: $model.videoCategory,
                    prompt: Text("Category", comment: "Composer video field placeholder")
                ) {
                    Text("Category", comment: "Composer video field label")
                }
                TextField(
                    text: $model.videoLicence,
                    prompt: Text("Licence", comment: "Composer video field placeholder")
                ) {
                    Text("Licence", comment: "Composer video field label")
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.footnote)
        .padding(AlohaMetrics.space3)
        .background(palette.surfaceRaised)
    }

    private func replyContext(_ status: Status) -> some View {
        HStack(alignment: .top, spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.reply)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to @\(status.account.acct)", comment: "Composer reply context")
                    .font(.caption.weight(.medium))
                Text(status.account.bestDisplayName)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
            }
            Spacer()
        }
        .foregroundStyle(palette.secondaryLabel)
        .padding(AlohaMetrics.space3)
        .background(palette.surfaceRaised)
    }

    private var contentWarningField: some View {
        TextField(
            text: $model.spoilerText,
            prompt: Text("Content warning", comment: "Composer field placeholder")
        ) {
            Text("Content warning", comment: "Composer field label")
        }
        .textFieldStyle(.plain)
        .padding(AlohaMetrics.space3)
        .background(palette.surfaceRaised)
    }

    /// The editor stays on a plain `String`, deliberately.
    ///
    /// A post is plain text on the wire, and an `AttributedString` editor
    /// would offer formatting and Genmoji the server cannot carry. A Genmoji
    /// is a picture with no faithful text form — its description is not what
    /// was chosen — so rather than quietly turning a picture into words at
    /// posting time, the editor does not offer one. What an attributed editor
    /// was wanted for is the selection, and a `String` editor has that too.
    private var editor: some View {
        TextEditor(text: $model.text, selection: $selection)
            .focused($isEditorFocused)
            .accessibilityLabel(Text("What's happening?", comment: "Composer placeholder"))
            .scrollContentBackground(.hidden)
            #if os(iOS) || os(macOS) || os(visionOS)
                // Proofread and rewrite in place, in the system's own panel.
                .writingToolsBehavior(.complete)
            #endif
            .padding(.horizontal, AlohaMetrics.space3)
            .padding(.vertical, AlohaMetrics.space2)
            .font(.body)
            // `TextEditor` takes no prompt, so the placeholder is drawn over
            // it — and hidden from VoiceOver, which already reads it as the
            // editor's label.
            .overlay(alignment: .topLeading) {
                if model.text.isEmpty {
                    Text("What's happening?", comment: "Composer placeholder")
                        .foregroundStyle(palette.tertiaryLabel)
                        .padding(.horizontal, AlohaMetrics.space4)
                        .padding(.vertical, AlohaMetrics.space3 + 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 140)
            #if os(iOS)
                // Above the keyboard, where a suggestion bar belongs, rather
                // than over the last lines being typed.
                .toolbar {
                    if !model.completions.isEmpty {
                        ToolbarItem(placement: .keyboard) { completionBar }
                    }
                }
            #else
                .overlay(alignment: .bottom) {
                    if !model.completions.isEmpty {
                        completionBar.background(.thinMaterial)
                    }
                }
            #endif
    }

    /// Puts a snippet where the cursor is, replacing a selection, and leaves
    /// the cursor after it.
    private func insertAtCursor(_ snippet: String) {
        var range: Range<String.Index>?
        if case .selection(let selected) = selection?.indices,
            selected.upperBound <= model.text.endIndex
        {
            range = selected
        }
        let result = ComposerTextInsertion.inserting(snippet, into: model.text, replacing: range)
        model.text = result.text
        let cursor =
            model.text.index(
                model.text.startIndex, offsetBy: result.cursorOffset,
                limitedBy: model.text.endIndex) ?? model.text.endIndex
        selection = TextSelection(insertionPoint: cursor)
    }

    /// Pictures from a drop or a paste go straight up; a video goes through
    /// the trim sheet, one at a time, the way a picked one does.
    private func attach(_ items: [DroppedMedia]) async {
        var movie: URL?
        for item in items {
            switch item {
            case .image(let image):
                await model.uploader.add(
                    data: image.data, filename: image.filename, mimeType: image.mimeType)
            case .movie(let url):
                if movie == nil { movie = url }
            }
        }
        if let movie { trimmingVideoAt = movie }
    }

    private var completionBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AlohaMetrics.space2) {
                ForEach(model.completions, id: \.self) { completion in
                    Button {
                        model.apply(completion: completion)
                    } label: {
                        Text(completion)
                            .font(.footnote)
                            .padding(.horizontal, AlohaMetrics.space3)
                            .padding(.vertical, AlohaMetrics.space1)
                            .background(palette.surfaceRaised, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AlohaMetrics.space3)
        }
        .scrollIndicators(.hidden)
        .frame(minHeight: 40)
    }

    private var mediaStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AlohaMetrics.space2) {
                // Describing four pictures one sheet at a time is four round
                // trips through the same editor (docs/10 §5); one button does
                // the lot, sequentially, and says where it is.
                if model.imagesAwaitingDescription > 0,
                    environment.intelligence.availability.isAvailable
                {
                    if model.isDescribingAll {
                        VStack(spacing: AlohaMetrics.space2) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .frame(width: 96)
                            Text(
                                "^[\(model.describedCount) of \(model.describeAllTotal)](inflect: false)",
                                comment: "Alt text batch progress"
                            )
                            .font(.caption2.monospacedDigit())
                            Button(role: .cancel) {
                                model.cancelDescribeAll()
                            } label: {
                                Text("Stop", comment: "Alt text batch cancel")
                                    .font(.caption2.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(palette.secondaryLabel)
                        }
                        .frame(width: 96, height: 96)
                        .background(
                            palette.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall)
                        )
                        .accessibilityLabel(
                            Text(
                                "Describing images: \(model.describedCount) of \(model.describeAllTotal) done",
                                comment: "Alt text batch progress"))
                    } else {
                        Button {
                            Task { await model.describeAllImages(environment: environment) }
                        } label: {
                            VStack(spacing: AlohaMetrics.space1) {
                                Image(systemName: "text.badge.star")
                                    .font(.title3)
                                Text("Describe all", comment: "Alt text batch action")
                                    .font(.caption2.weight(.semibold))
                                Text(
                                    "^[\(model.imagesAwaitingDescription) image](inflect: true)",
                                    comment: "Alt text batch count"
                                )
                                .font(.caption2.monospacedDigit())
                            }
                            .foregroundStyle(palette.accent)
                            .frame(width: 96, height: 96)
                            .background(
                                palette.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            Text(
                                "Describe all \(model.imagesAwaitingDescription) images",
                                comment: "Alt text batch action"))
                    }
                }

                ForEach(model.attachments) { attachment in
                    ZStack(alignment: .bottomTrailing) {
                        RemoteImage(url: attachment.displayImageURL)
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall))

                        Button {
                            model.isShowingAltTextFor = attachment
                        } label: {
                            Text("ALT", comment: "Composer alt text badge")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    attachment.hasAltText ? palette.accent : palette.destructive,
                                    in: Capsule()
                                )
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .accessibilityLabel(
                            attachment.hasAltText
                                ? Text("Edit description", comment: "Composer media action")
                                : Text("Add a description", comment: "Composer media action"))
                    }
                    .overlay(alignment: .topLeading) {
                        if model.focalPoints[attachment.id] != nil {
                            Image(systemName: "scope")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(.black.opacity(0.5), in: Circle())
                                .padding(4)
                                .accessibilityLabel(
                                    Text("Focal point set", comment: "Composer media badge"))
                        }
                    }
                    .contextMenu {
                        if !attachment.type.isPlayable {
                            Button {
                                focusingAttachment = attachment
                            } label: {
                                Label {
                                    Text("Set focal point", comment: "Composer media action")
                                } icon: {
                                    Image(systemName: "scope")
                                }
                            }
                        }
                        Button {
                            model.isShowingAltTextFor = attachment
                        } label: {
                            Label {
                                Text("Describe", comment: "Composer media action")
                            } icon: {
                                Image(systemName: AlohaSymbol.altBadge)
                            }
                        }
                        if model.uploader.canFilter(attachment.id) {
                            Button {
                                filteringAttachment = attachment
                            } label: {
                                Label {
                                    Text("Adjust", comment: "Composer media action")
                                } icon: {
                                    Image(systemName: "camera.filters")
                                }
                            }
                        }
                        Button(role: .destructive) {
                            model.removeAttachment(attachment.id)
                        } label: {
                            Label {
                                Text("Remove", comment: "Composer media action")
                            } icon: {
                                Image(systemName: AlohaSymbol.delete)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AlohaMetrics.space3)
        }
        .frame(height: 112)
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            // A failure in the batch is reported in place — one bad image does
            // not undo the ones that succeeded, and it should not be surfaced
            // as a modal the person has to dismiss to see their remaining work.
            if let describeAllError = model.describeAllError, !model.isDescribingAll {
                Text(describeAllError)
                    .font(.caption2)
                    .foregroundStyle(palette.destructive)
                    .padding(.horizontal, AlohaMetrics.space3)
                    .padding(.vertical, AlohaMetrics.space1)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }

    /// The batch run's progress, for the strip's progress bar.
    private var progress: Double {
        guard model.describeAllTotal > 0 else { return 0 }
        return Double(model.describedCount) / Double(model.describeAllTotal)
    }

    /// What `/dice`, `/flip` and `/pick` will do when this goes out. A hint
    /// rather than a preview: the roll happens once, at the moment of posting,
    /// and showing a number here would be showing one that is not the one sent.
    private var gamesHint: some View {
        HStack(spacing: AlohaMetrics.space2) {
            ForEach(model.pendingGames, id: \.self) { kind in
                Text(verbatim: kind.icon)
            }
            Text("Rolled when this goes out.", comment: "Composer games hint")
                .font(AlohaType.meta)
                .foregroundStyle(palette.secondaryLabel)
            Spacer()
        }
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.bottom, AlohaMetrics.space2)
        .accessibilityElement(children: .combine)
    }

    /// Six backgrounds for a short post, and the way back to plain text.
    private var cardRow: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            Text("Post it as a card", comment: "Composer card section")
                .font(AlohaType.micro)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.horizontal, AlohaMetrics.space4)

            ScrollView(.horizontal) {
                HStack(spacing: AlohaMetrics.space2) {
                    cardSwatch(nil)
                    ForEach(cardBackgrounds) { background in
                        cardSwatch(background)
                    }
                }
                .padding(.horizontal, AlohaMetrics.space4)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.bottom, AlohaMetrics.space2)
    }

    private var cardBackgrounds: [TextCard.Background] {
        TextCard.backgrounds(accountHue: Monogram.hue(for: model.session.snapshot.qualifiedHandle))
    }

    @ViewBuilder
    private func cardSwatch(_ background: TextCard.Background?) -> some View {
        let isSelected = model.cardBackgroundID == background?.id
        Button {
            model.cardBackgroundID = isSelected ? nil : background?.id
        } label: {
            Group {
                if let background {
                    LinearGradient(
                        colors: [background.from, background.to],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                } else {
                    palette.surfaceRaised.overlay {
                        Image(systemName: "textformat")
                            .foregroundStyle(palette.secondaryLabel)
                    }
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall))
            .overlay {
                RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall)
                    .strokeBorder(
                        isSelected ? palette.accent : palette.separator,
                        lineWidth: isSelected ? 3 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            background.map { Text($0.name) }
                ?? Text("Plain text", comment: "Composer card option")
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var pollEditor: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
            Text(
                "Add at least two choices. People can vote after you publish the post.",
                comment: "Poll editor guidance"
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            ForEach(model.pollOptions.indices, id: \.self) { index in
                HStack {
                    TextField(
                        text: Binding(
                            get: {
                                model.pollOptions.indices.contains(index)
                                    ? model.pollOptions[index] : ""
                            },
                            set: { value in
                                guard model.pollOptions.indices.contains(index) else { return }
                                model.pollOptions[index] = value
                            }),
                        prompt: Text("Choice \(index + 1)", comment: "Poll option placeholder")
                    ) {
                        Text("Choice", comment: "Poll option label")
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(minHeight: 44)
                    Button(role: .destructive) {
                        guard model.pollOptions.count > 2,
                            model.pollOptions.indices.contains(index)
                        else { return }
                        model.pollOptions.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.pollOptions.count <= 2)
                    .accessibilityLabel(Text("Remove choice", comment: "Poll editor action"))
                }
            }

            HStack {
                Button {
                    model.addPollOption()
                } label: {
                    Text("Add choice", comment: "Poll action")
                }
                .disabled(model.pollOptions.count >= model.limits.maxPollOptions)
                .buttonStyle(.bordered)

                Spacer()
            }
            .font(.footnote)
            Toggle(isOn: $model.pollMultiple) {
                Text("Multiple choice", comment: "Poll option")
            }
            .toggleStyle(.switch)
        }
        .padding(AlohaMetrics.space3)
    }

    private var toolbar: some View {
        HStack(spacing: AlohaMetrics.space3) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    toolbarButtons
                }
                .buttonStyle(ComposerToolStyle())
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            if let remaining = model.remainingCharacters {
                Text(remaining, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(remaining < 0 ? palette.destructive : palette.secondaryLabel)
                    .fixedSize()
                    .accessibilityLabel(
                        Text(
                            "^[\(remaining) character](inflect: true) left",
                            comment: "Composer counter"))
            }
        }
        .font(.title3)
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.vertical, AlohaMetrics.space3)
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        Button {
            model.isShowingMediaPicker = true
        } label: {
            Image(systemName: AlohaSymbol.media)
        }
        .disabled(!model.canAddMedia)
        .accessibilityLabel(Text("Add media", comment: "Composer action"))

        #if os(iOS)
            if CameraCapture.isAvailable {
                Button {
                    isShowingCamera = true
                } label: {
                    Image(systemName: "camera")
                }
                .disabled(!model.canAddMedia)
                .accessibilityLabel(Text("Take a photo or video", comment: "Composer action"))
            }
        #endif

        #if os(iOS) || os(macOS) || os(visionOS)
            // The system's paste button reads the pasteboard only when tapped,
            // so a copied picture is attached without the "allow paste"
            // prompt, and it greys itself out when nothing pasteable is there.
            PasteButton(payloadType: DroppedMedia.self) { items in
                Task { await attach(items) }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.circle)
            .disabled(!model.canAddMedia)
        #endif

        Button {
            if !model.hasPoll { model.togglePoll() }
            isShowingPollEditor = true
        } label: {
            Image(systemName: AlohaSymbol.poll)
        }
        .disabled(!model.attachments.isEmpty)
        .accessibilityLabel(Text("Add a poll", comment: "Composer action"))

        Menu {
            Picker(selection: $model.visibility) {
                Label {
                    Text("Public", comment: "Visibility")
                } icon: {
                    Image(systemName: AlohaSymbol.globe)
                }.tag(Visibility.public)
                Label {
                    Text("Unlisted", comment: "Visibility")
                } icon: {
                    Image(systemName: "eye.slash")
                }.tag(Visibility.unlisted)
                Label {
                    Text("Followers only", comment: "Visibility")
                } icon: {
                    Image(systemName: AlohaSymbol.lock)
                }.tag(Visibility.private)
                Label {
                    Text("Direct", comment: "Visibility")
                } icon: {
                    Image(systemName: AlohaSymbol.envelope)
                }.tag(Visibility.direct)
            } label: {
                Text("Visibility", comment: "Composer picker")
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: model.visibilitySymbol)
        }
        .accessibilityLabel(Text("Who can see this", comment: "Composer action"))

        Menu {
            if model.canBeCard {
                Button {
                    showsCardOptions.toggle()
                } label: {
                    Label {
                        Text("Post it as a card", comment: "Composer action")
                    } icon: {
                        Image(systemName: "rectangle.on.rectangle")
                    }
                }
                .accessibilityLabel(Text("Post it as a card", comment: "Composer card section"))
                .accessibilityValue(
                    showsCardOptions
                        ? Text("Expanded", comment: "Accessibility state")
                        : Text("Collapsed", comment: "Accessibility state"))
            }
            Button {
                model.showsContentWarningField.toggle()
            } label: {
                Label {
                    Text("Add a content warning", comment: "Composer action")
                } icon: {
                    Image(systemName: AlohaSymbol.warning)
                }
            }
            .accessibilityLabel(Text("Add a content warning", comment: "Composer action"))

            Button {
                model.addThreadSegment()
            } label: {
                Label {
                    Text("Add to thread", comment: "Composer action")
                } icon: {
                    Image(systemName: "text.append")
                }
            }
            .accessibilityLabel(Text("Add to thread", comment: "Composer action"))

            Button {
                isShowingSchedule = true
            } label: {
                Label {
                    Text("Schedule this post", comment: "Composer action")
                } icon: {
                    Image(systemName: model.scheduledAt == nil ? "clock" : "clock.fill")
                }
            }
            .accessibilityLabel(Text("Schedule this post", comment: "Composer action"))

            if model.capabilities.mediaFromNextcloudFiles {
                Button {
                    isShowingNextcloudFiles = true
                } label: {
                    Label {
                        Text("Attach from your Nextcloud", comment: "Composer action")
                    } icon: {
                        Image(systemName: "folder")
                    }
                }
                .disabled(!model.canAddMedia)
                .accessibilityLabel(
                    Text("Attach from your Nextcloud", comment: "Composer action"))
            }

            if model.isNextcloud {
                Button {
                    isShowingGIFPicker = true
                } label: {
                    Label {
                        Text("Add a picture from the library", comment: "Composer action")
                    } icon: {
                        Image(systemName: "photo.stack")
                    }
                }
                .disabled(!model.canAddMedia)
                .accessibilityLabel(
                    Text("Add a picture from the library", comment: "Composer action"))

                Button {
                    isShowingPlacePicker = true
                } label: {
                    Label {
                        Text("Add a place", comment: "Composer action")
                    } icon: {
                        Image(
                            systemName: model.place == nil
                                ? "mappin.and.ellipse" : "mappin.circle.fill")
                    }
                }
                .accessibilityLabel(Text("Add a place", comment: "Composer action"))
            }

            Button {
                isShowingEmojiPicker = true
            } label: {
                Label {
                    Text("Add a custom emoji", comment: "Composer action")
                } icon: {
                    Image(systemName: "face.smiling")
                }
            }
            .accessibilityLabel(Text("Add a custom emoji", comment: "Composer action"))

            Menu {
                LanguagePicker(language: $model.language, fallback: model.defaultLanguage)
            } label: {
                if let code = model.language, !code.isEmpty {
                    Text(LanguagePicker.short(for: code))
                        .font(.caption.weight(.bold))
                        .frame(minWidth: 24, minHeight: 24)
                } else {
                    Label {
                        Text("Language", comment: "Composer action")
                    } icon: {
                        Image(systemName: "character.book.closed")
                    }
                }
            }
            .accessibilityLabel(Text("Language", comment: "Composer action"))

            if model.canQuote, model.editingStatus == nil {
                Menu {
                    Picker(selection: $model.quotePolicy) {
                        Label {
                            Text("Anybody", comment: "Quote policy")
                        } icon: {
                            Image(systemName: AlohaSymbol.globe)
                        }.tag(ComposerModel.QuotePolicy.public)
                        Label {
                            Text("People who follow me", comment: "Quote policy")
                        } icon: {
                            Image(systemName: "person.2")
                        }.tag(ComposerModel.QuotePolicy.followers)
                        Label {
                            Text("Nobody but me", comment: "Quote policy")
                        } icon: {
                            Image(systemName: AlohaSymbol.lock)
                        }.tag(ComposerModel.QuotePolicy.nobody)
                    } label: {
                        Text("Who may quote this", comment: "Composer picker")
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label {
                        Text("Who may quote this", comment: "Composer action")
                    } icon: {
                        Image(
                            systemName: model.quotePolicy == .public
                                ? "text.quote" : "text.badge.xmark")
                    }
                }
                .accessibilityLabel(Text("Who may quote this", comment: "Composer action"))
            }

            if model.isNextcloud, model.editingStatus == nil {
                Menu {
                    Picker(selection: $model.replyPolicy) {
                        ForEach(ReplyPolicy.allCases, id: \.self) { policy in
                            ReplyPolicyLabel(policy: policy).tag(policy)
                        }
                    } label: {
                        Text("Who can reply", comment: "Composer picker")
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label {
                        Text("Who can reply", comment: "Composer action")
                    } icon: {
                        Image(systemName: ReplyPolicyLabel.symbol(model.replyPolicy))
                    }
                }
                .accessibilityLabel(Text("Who can reply", comment: "Composer action"))

                Toggle(isOn: $model.marksAsAIGenerated) {
                    Label {
                        Text("Made with AI", comment: "Composer toggle")
                    } icon: {
                        Image(systemName: "wand.and.sparkles")
                    }
                }
                .accessibilityHint(
                    Text(
                        "Adds #AIgenerated, which readers can choose to filter.",
                        comment: "Composer toggle hint"))
            }

            if !model.teams.isEmpty {
                Menu {
                    Picker(selection: $model.postAs) {
                        Text("Myself", comment: "Post as option").tag(TeamAccount?.none)
                        ForEach(model.teams) { team in
                            Text(team.name).tag(TeamAccount?.some(team))
                        }
                    } label: {
                        Text("Post as", comment: "Composer picker")
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label {
                        Text("Post as", comment: "Composer action")
                    } icon: {
                        Image(systemName: model.postAs == nil ? "person" : "person.3.fill")
                    }
                }
                .accessibilityLabel(Text("Post as", comment: "Composer action"))
            }

            #if canImport(ImagePlayground) && !os(tvOS) && !os(watchOS)
                if supportsImagePlayground {
                    Button {
                        isShowingImagePlayground = true
                    } label: {
                        Label {
                            Text("Create an image", comment: "Composer action")
                        } icon: {
                            Image(systemName: "apple.image.playground")
                        }
                    }
                    .disabled(!model.canAddMedia)
                }
            #endif

            if environment.intelligence.availability.isAvailable {
                Menu {
                    ForEach(RewriteStyle.allCases) { style in
                        Button {
                            rewritingStyle = style
                        } label: {
                            Text(style.displayName)
                        }
                    }
                } label: {
                    Label {
                        Text("Writing help", comment: "Composer action")
                    } icon: {
                        Image(systemName: AlohaSymbol.sparkles)
                    }
                }
                .disabled(model.text.isEmpty)
                .accessibilityLabel(Text("Writing help", comment: "Composer action"))
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(Text("More options", comment: "Composer additional actions"))
        // Each picker comes out of the button it was chosen from: a popover
        // on an iPad or a Mac, where a full sheet over the composer hid the
        // post being written, and a sheet on a phone, where a popover would
        // be a postage stamp.
        .composerPicker(isPresented: $isShowingSchedule) {
            SchedulePicker(scheduledAt: $model.scheduledAt)
        }
        .composerPicker(isPresented: $isShowingPlacePicker) {
            if let session = environment.activeSession {
                PlacePicker(session: session) { model.place = $0 }
            }
        }
        .composerPicker(isPresented: $isShowingGIFPicker) {
            if let session = environment.activeSession {
                GIFPicker(session: session) { entry in
                    Task { await model.attachLibraryPicture(entry) }
                }
            }
        }
        .composerPicker(isPresented: $isShowingEmojiPicker) {
            if let session = environment.activeSession {
                EmojiPicker(session: session) { insertAtCursor(":\($0.shortcode):") }
            }
        }
        #if canImport(ImagePlayground) && !os(tvOS) && !os(watchOS)
            .imagePlaygroundSheet(
                isPresented: $isShowingImagePlayground,
                concepts: model.text.isEmpty ? [] : [.extracted(from: model.text, title: nil)]
            ) { url in
                Task { await attachPlaygroundImage(at: url) }
            }
        #endif
    }

    /// An image made in Image Playground goes up like any other picture, and
    /// the post is marked as made with AI where the server can carry that:
    /// the label is the honest default for a picture the person did not take.
    private func attachPlaygroundImage(at url: URL) async {
        guard let data = try? Data(contentsOf: url) else { return }
        let image = DroppedImage(data: data)
        await model.uploader.add(
            data: image.data, filename: image.filename, mimeType: image.mimeType)
        if model.isNextcloud { model.marksAsAIGenerated = true }
    }

    private var uploadProgress: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
            ForEach(model.uploader.progress.items) { item in
                HStack(spacing: AlohaMetrics.space2) {
                    Text(item.filename).font(.caption).lineLimit(1)
                    Spacer()
                    if item.failed {
                        Image(systemName: AlohaSymbol.warning).foregroundStyle(palette.destructive)
                    } else {
                        ProgressView(value: item.fractionCompleted).frame(width: 80)
                    }
                }
            }
        }
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.vertical, AlohaMetrics.space2)
        .background(palette.surfaceRaised)
    }

    private func scheduleBanner(_ date: Date) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: "clock.fill")
            Text(
                "Scheduled for \(date.formatted(.dateTime.weekday().day().month().hour().minute()))",
                comment: "Composer schedule banner")
            Spacer()
            Button {
                model.scheduledAt = nil
            } label: {
                Text("Cancel", comment: "Composer schedule action")
            }
            .font(.caption)
        }
        .font(.caption)
        .foregroundStyle(palette.accent)
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.vertical, AlohaMetrics.space2)
        .background(palette.surfaceRaised)
    }

    private func uploadError(_ message: String) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.warning)
            Text(message).font(.caption)
            Spacer()
        }
        .foregroundStyle(palette.destructive)
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.vertical, AlohaMetrics.space2)
    }

    /// Each segment is its own text area; posting chains them.
    private var threadEditor: some View {
        VStack(spacing: AlohaMetrics.space2) {
            ForEach(model.threadSegments.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: AlohaMetrics.space2) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundStyle(palette.tertiaryLabel)
                        .padding(.top, 6)
                    TextField(
                        text: Binding(
                            get: {
                                model.threadSegments.indices.contains(index)
                                    ? model.threadSegments[index] : ""
                            },
                            set: { value in
                                guard model.threadSegments.indices.contains(index) else { return }
                                model.threadSegments[index] = value
                            }),
                        prompt: Text("Continue the thread…", comment: "Thread segment placeholder"),
                        axis: .vertical
                    ) {
                        Text("Thread segment", comment: "Thread segment label")
                    }
                    .textFieldStyle(.plain)
                    Button {
                        model.removeThreadSegment(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.tertiaryLabel)
                    .accessibilityLabel(Text("Remove segment", comment: "Thread action"))
                }
            }
        }
        .padding(AlohaMetrics.space3)
        .background(palette.surfaceRaised)
    }

    private func ingest(_ items: [PhotosPickerItem]) async {
        defer { pickedItems = [] }
        for item in items {
            let type = item.supportedContentTypes.first
            let mimeType = type?.preferredMIMEType ?? "image/jpeg"
            let ext = type?.preferredFilenameExtension ?? "jpg"

            // A video goes through the trim sheet first, so its length and
            // quality are settled before anything is uploaded.
            if mimeType.hasPrefix("video/"),
                let movie = try? await item.loadTransferable(type: PickedMovie.self)
            {
                trimmingVideoAt = movie.url
                continue
            }

            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            await model.uploader.add(
                data: data, filename: "upload-\(UUID().uuidString).\(ext)", mimeType: mimeType)
        }
    }

    private var nextcloudCredentials: NextcloudLoginFlow.Credentials? {
        guard let session = environment.activeSession else { return nil }
        return (try? environment.credentials.nextcloudCredentials(for: session.id)) ?? nil
    }

    private func close() {
        // Nothing is in progress once the composer is closed unposted, so an
        // upload's Live Activity does not linger on the Lock Screen.
        UploadActivityController.shared.cancel()
        Task {
            await model.saveDraftIfNeeded()
            finish(.cancelled)
        }
    }
}

/// The composer's tool row: tinted glyphs at the text size the person reads
/// at, each with a hit area that grows with it.
///
/// Glass is the navigation layer's material, not a control's inside the
/// content; a row of glass circles under the text read as a second toolbar
/// floating over the post. A fixed 18-point glyph also ignored Dynamic Type.
private struct ComposerToolStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .title3) private var side: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.medium))
            .frame(minWidth: side, minHeight: side)
            .contentShape(Rectangle())
            .foregroundStyle(.tint)
            .opacity(!isEnabled ? 0.4 : (configuration.isPressed ? 0.6 : 1))
    }
}

extension View {
    /// A composer picker: a popover in regular width and on the Mac, a sheet
    /// in compact width, sized so a search field and a grid of results have
    /// room either way.
    fileprivate func composerPicker<Content: View>(
        isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        popover(isPresented: isPresented, arrowEdge: .bottom) {
            content()
                .frame(minWidth: 320, idealWidth: 400, minHeight: 420, idealHeight: 560)
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.medium, .large])
        }
    }
}

struct TrimRequest: Identifiable, Hashable {
    let url: URL
    var id: String { url.absoluteString }
}

/// `PhotosPickerItem` hands a movie over as a file rather than as `Data`, which
/// is what lets a long video be trimmed without being read into memory first.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = FileManager.default.temporaryDirectory
                .appending(path: "picked-\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}
