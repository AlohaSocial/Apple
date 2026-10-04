// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaIntelligence
import AlohaMedia
import AlohaModels
import AlohaNetwork
import AlohaStore
import PhotosUI
import SwiftUI

public struct ComposerView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
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
    @FocusState private var isEditorFocused: Bool

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
        _model = State(
            initialValue: ComposerModel(session: session, editing: status, source: source))
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
        _model = State(
            initialValue: ComposerModel(session: session, replyTo: replyTo, quoting: quoting))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let replyTo = model.replyTo { replyContext(replyTo) }
                if let quoting = model.quoting { quoteCard(quoting) }
                if model.showsContentWarningField {
                    contentWarningField
                    ContentWarningPresets(spoilerText: $model.spoilerText)
                }

                editor

                if !model.pendingGames.isEmpty { gamesHint }
                if model.canBeCard && (showsCardOptions || model.cardBackgroundID != nil) { cardRow }

                if let place = model.place { placeChip(place) }
                if model.isNextcloud && model.hasVideoAttachment { videoMetaFields }

                if !model.uploader.progress.items.isEmpty && !model.uploader.progress.isFinished {
                    uploadProgress
                }
                if let message = model.uploader.errorMessage { uploadError(message) }
                if let scheduledAt = model.scheduledAt { scheduleBanner(scheduledAt) }
                if !model.attachments.isEmpty { mediaStrip }
                if !model.threadSegments.isEmpty { threadEditor }
                if model.hasPoll {
                    Button {
                        isShowingPollEditor = true
                    } label: {
                        Label("Edit poll", systemImage: AlohaSymbol.poll)
                    }
                    .buttonStyle(.glass)
                    .padding(AlohaMetrics.space2)
                }

                toolbar
            }
            .background(palette.background)
            .sensoryFeedback(.success, trigger: didSend)
            .navigationTitle(model.title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        close()
                    } label: {
                        Text("Cancel", comment: "Composer action")
                            .foregroundStyle(palette.label)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
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
                    .buttonStyle(.glassProminent)
                    .tint(palette.accent)
                    .disabled(!model.canPost)
                    .keyboardShortcut(.return, modifiers: .command)
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
                        .navigationTitle("Poll")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isShowingPollEditor = false }
                            }
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Remove poll", role: .destructive) {
                                    model.pollOptions = []
                                    isShowingPollEditor = false
                                }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $isShowingSchedule) {
                SchedulePicker(scheduledAt: $model.scheduledAt)
            }
            .sheet(isPresented: $isShowingPlacePicker) {
                if let session = environment.activeSession {
                    PlacePicker(session: session) { model.place = $0 }
                }
            }
            .sheet(isPresented: $isShowingGIFPicker) {
                if let session = environment.activeSession {
                    GIFPicker(session: session) { entry in
                        Task { await model.attachLibraryPicture(entry) }
                    }
                }
            }
            .sheet(isPresented: $isShowingEmojiPicker) {
                if let session = environment.activeSession {
                    EmojiPicker(session: session) { model.insert(emoji: $0) }
                }
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
                    dismiss()
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
        }
    }

    // MARK: - Posting

    private func send(skippingAltTextCheck: Bool = false) async {
        guard await model.post(skippingAltTextCheck: skippingAltTextCheck) else { return }
        if model.wasHeldForReview {
            isShowingHeldNotice = true
        } else {
            didSend.toggle()
            dismiss()
        }
    }

    // MARK: - Pieces

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

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if model.text.isEmpty {
                Text("What's happening?", comment: "Composer placeholder")
                    .foregroundStyle(palette.tertiaryLabel)
                    .padding(.horizontal, AlohaMetrics.space4)
                    .padding(.vertical, AlohaMetrics.space3 + 2)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $model.text)
                .focused($isEditorFocused)
                .accessibilityLabel(Text("What's happening?", comment: "Composer placeholder"))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, AlohaMetrics.space3)
                .padding(.vertical, AlohaMetrics.space2)
                .font(.body)
        }
        .frame(minHeight: 140)
        .overlay(alignment: .bottom) {
            if !model.completions.isEmpty { completionBar }
        }
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
        .frame(height: 40)
        .background(.thinMaterial)
    }

    private var mediaStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AlohaMetrics.space2) {
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
        VStack(spacing: AlohaMetrics.space2) {
            ForEach(model.pollOptions.indices, id: \.self) { index in
                HStack {
                TextField(
                    text: Binding(
                        get: { model.pollOptions.indices.contains(index) ? model.pollOptions[index] : "" },
                        set: { value in
                            guard model.pollOptions.indices.contains(index) else { return }
                            model.pollOptions[index] = value
                        }),
                    prompt: Text("Choice \(index + 1)", comment: "Poll option placeholder")
                ) {
                    Text("Choice", comment: "Poll option label")
                }
                .textFieldStyle(.plain)
                .padding(.horizontal, AlohaMetrics.space3)
                .frame(minHeight: 44)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
                    Button(role: .destructive) {
                        guard model.pollOptions.count > 2,
                              model.pollOptions.indices.contains(index) else { return }
                        model.pollOptions.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .disabled(model.pollOptions.count <= 2)
                    .accessibilityLabel(Text("Remove choice"))
                }
            }

            HStack {
                Button {
                    model.addPollOption()
                } label: {
                    Text("Add choice", comment: "Poll action")
                }
                .disabled(model.pollOptions.count >= model.limits.maxPollOptions)
                .buttonStyle(.glass)

                Spacer()

                Toggle(isOn: $model.pollMultiple) {
                    Text("Multiple choice", comment: "Poll option")
                }
                .toggleStyle(.switch)
                .labelsHidden()
                Text("Multiple", comment: "Poll option short label").font(.caption)
            }
            .font(.footnote)
        }
        .padding(AlohaMetrics.space3)
        .background(palette.surfaceRaised)
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
        if model.canBeCard {
            Button {
                showsCardOptions.toggle()
            } label: {
                Image(systemName: "rectangle.on.rectangle")
            }
            .accessibilityLabel(Text("Post it as a card", comment: "Composer card section"))
            .accessibilityValue(showsCardOptions ? Text("Expanded") : Text("Collapsed"))
        }
        Button {
            model.isShowingMediaPicker = true
        } label: {
            Image(systemName: AlohaSymbol.media)
        }
        .disabled(!model.canAddMedia)
        .accessibilityLabel(Text("Add media", comment: "Composer action"))

        Button {
            if !model.hasPoll { model.togglePoll() }
            isShowingPollEditor = true
        } label: {
            Image(systemName: AlohaSymbol.poll)
        }
        .disabled(!model.attachments.isEmpty)
        .accessibilityLabel(Text("Add a poll", comment: "Composer action"))

        Button {
            model.showsContentWarningField.toggle()
        } label: {
            Image(systemName: AlohaSymbol.warning)
        }
        .accessibilityLabel(Text("Add a content warning", comment: "Composer action"))

        Button {
            model.addThreadSegment()
        } label: {
            Image(systemName: "text.append")
        }
        .accessibilityLabel(Text("Add to thread", comment: "Composer action"))

        Button {
            isShowingSchedule = true
        } label: {
            Image(systemName: model.scheduledAt == nil ? "clock" : "clock.fill")
        }
        .accessibilityLabel(Text("Schedule this post", comment: "Composer action"))

        if model.capabilities.mediaFromNextcloudFiles {
            Button {
                isShowingNextcloudFiles = true
            } label: {
                Image(systemName: "folder")
            }
            .disabled(!model.canAddMedia)
            .accessibilityLabel(
                Text("Attach from your Nextcloud", comment: "Composer action"))
        }

        if model.isNextcloud {
            Button {
                isShowingGIFPicker = true
            } label: {
                Image(systemName: "photo.stack")
            }
            .disabled(!model.canAddMedia)
            .accessibilityLabel(Text("Add a picture from the library", comment: "Composer action"))

            Button {
                isShowingPlacePicker = true
            } label: {
                Image(systemName: model.place == nil ? "mappin.and.ellipse" : "mappin.circle.fill")
            }
            .accessibilityLabel(Text("Add a place", comment: "Composer action"))
        }

        Button {
            isShowingEmojiPicker = true
        } label: {
            Image(systemName: "face.smiling")
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
                Image(systemName: "character.book.closed")
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
                Image(systemName: model.quotePolicy == .public ? "text.quote" : "text.badge.xmark")
            }
            .accessibilityLabel(Text("Who may quote this", comment: "Composer action"))
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
                Image(systemName: model.postAs == nil ? "person" : "person.3.fill")
            }
            .accessibilityLabel(Text("Post as", comment: "Composer action"))
        }

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

        if environment.intelligence.availability.isAvailable {
            Menu {
                ForEach(RewriteStyle.allCases) { style in
                    Button {
                        Task { await model.rewrite(style, using: environment.intelligence) }
                    } label: {
                        Text(style.displayName)
                    }
                }
            } label: {
                Image(systemName: AlohaSymbol.sparkles)
            }
            .disabled(model.text.isEmpty)
            .accessibilityLabel(Text("Writing help", comment: "Composer action"))
        }
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
                            get: { model.threadSegments.indices.contains(index) ? model.threadSegments[index] : "" },
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
        Task {
            await model.saveDraftIfNeeded()
            dismiss()
        }
    }
}

private struct ComposerToolStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .medium))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .glassEffect(.regular.interactive(), in: Circle())
            .opacity(!isEnabled ? 0.4 : (configuration.isPressed ? 0.65 : 1))
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
