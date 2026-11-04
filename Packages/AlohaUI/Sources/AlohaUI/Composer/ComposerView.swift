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
    @Environment(\.alohaPalette) var palette
    @Environment(AppEnvironment.self) var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.composerHost) private var host
    @Environment(\.scenePhase) private var scenePhase
    @State private var didSend = false
    @State var showsCardOptions = false
    @State var isShowingPollEditor = false

    @State var model: ComposerModel
    @State var pickedItems: [PhotosPickerItem] = []
    @State var isShowingSchedule = false
    @State var isShowingNextcloudFiles = false
    @State var isShowingPlacePicker = false
    @State var isShowingGIFPicker = false
    @State var isShowingEmojiPicker = false
    @State private var isShowingHeldNotice = false
    @State private var isShowingScheduledNotice = false
    @State private var didPrefill = false
    @State var focusingAttachment: MediaAttachment?
    @State var filteringAttachment: MediaAttachment?
    @State var trimmingVideoAt: URL?
    @State var rewritingStyle: RewriteStyle?
    @State var isShowingCamera = false
    @FocusState var isEditorFocused: Bool
    /// Set once the composer has ended on purpose — posted, or cancelled with
    /// the draft saved — so the disappearance that follows is not mistaken
    /// for one that would lose the words.
    @State private var didFinish = false
    @State var selection: TextSelection?
    @State var isShowingImagePlayground = false
    #if canImport(ImagePlayground) && !os(tvOS) && !os(watchOS)
        @Environment(\.supportsImagePlayground) var supportsImagePlayground
    #endif
    /// An edit's text as it arrived, so closing an unchanged edit needs no
    /// guard while closing a changed one does.
    private let editBaseline: String?

    private let prefilledText: String
    private let prefilledAttachments: [PrefilledAttachment]

    /// A file handed over by the share extension, uploaded once the composer
    /// appears so the sheet is on screen while it goes up.
    public struct PrefilledAttachment: Sendable, Hashable {
        /// Where the bytes are: in memory, for a picture, or in a file of the
        /// composer's own to delete once it has gone up — a video, which can
        /// be larger than everything a share extension may hold.
        public enum Source: Sendable, Hashable {
            case data(Data)
            case file(URL)
        }

        public var source: Source
        public var filename: String
        public var mimeType: String

        public init(data: Data, filename: String, mimeType: String) {
            self.source = .data(data)
            self.filename = filename
            self.mimeType = mimeType
        }

        public init(fileURL: URL, filename: String, mimeType: String) {
            self.source = .file(fileURL)
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
                guard !items.isEmpty else { return }
                Task { await model.uploader.whileFetching { await ingest(items) } }
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
            // A scheduled post is a success with nothing to show for it yet,
            // so the composer says when it will go out and where to find it
            // rather than vanishing as if the post were already up.
            .alert(
                Text("Scheduled", comment: "Scheduled post confirmation title"),
                isPresented: $isShowingScheduledNotice
            ) {
                Button {
                    finish(.posted)
                } label: {
                    Text("OK", comment: "Scheduled post confirmation action")
                }
            } message: {
                if let date = model.scheduledFor {
                    Text(
                        """
                        Your post will go out on \
                        \(date.formatted(.dateTime.weekday().day().month().hour().minute())). \
                        You can change or cancel it under Scheduled posts in Settings.
                        """,
                        comment: "Scheduled post confirmation. The argument is a date and time.")
                }
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
                // Once, though the task runs again whenever the composer
                // comes back on screen.
                let isFirstRun = !didPrefill
                didPrefill = true
                // Before `prepare()` waits on the network, and only into an
                // empty box, so nothing typed meanwhile is written over.
                if isFirstRun, !prefilledText.isEmpty, model.text.isEmpty {
                    model.text = prefilledText
                }
                await model.prepare()
                guard isFirstRun else { return }
                for attachment in prefilledAttachments {
                    switch attachment.source {
                    case .data(let data):
                        await model.uploader.add(
                            data: data, filename: attachment.filename,
                            mimeType: attachment.mimeType)
                    case .file(let url):
                        await model.uploader.add(
                            fileAt: url, filename: attachment.filename,
                            mimeType: attachment.mimeType)
                        // The hand-over copy; the server has its own now, or
                        // the upload has said why not.
                        try? FileManager.default.removeItem(at: url)
                    }
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
        // iOS can end an app it has put in the background without another
        // word, and then `onDisappear` never comes. What was written is saved
        // on the way out instead — already at inactive, which leaves time for
        // the store to write — and closing normally later replaces that save.
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active, !didFinish else { return }
            Task { await model.preserveDraft() }
        }
        // Every way out that is not Post or Cancel — the shell replacing the
        // sheet, the account changing underneath it, a window closing — still
        // keeps what was written.
        .onDisappear {
            guard !didFinish else { return }
            UploadActivityController.shared.cancel()
            Task {
                await model.saveDraftIfNeeded()
                await model.saveDraftWhenUploadsSettle()
            }
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
        } else if model.scheduledFor != nil {
            didSend.toggle()
            isShowingScheduledNotice = true
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
            // A file still going up is not dropped: it joins the draft once
            // it lands. (A share extension ends with the composer, and its
            // upload with it.)
            await model.saveDraftWhenUploadsSettle()
        }
    }
}
