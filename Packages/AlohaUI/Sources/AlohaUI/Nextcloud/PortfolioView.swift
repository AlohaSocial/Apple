// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Your portfolio: a page of your pictures with a public address, and the
/// settings that shape it. A draft is yours alone; a published one is read by
/// anybody with the link, signed in or not.
public struct PortfolioView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession

    @State private var settings = PortfolioSettings()
    @State private var loaded: PortfolioSettings?
    @State private var collections: [Collection] = []
    @State private var preview: PortfolioPage?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var didSave = false
    @State private var errorMessage: String?
    @State private var section: Section = .settings
    @State private var previewID = UUID()

    enum Section: String, CaseIterable, Identifiable {
        case settings, preview
        var id: String { rawValue }
    }

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker(selection: $section) {
                Text("Settings", comment: "Portfolio section").tag(Section.settings)
                Text("Preview", comment: "Portfolio section").tag(Section.preview)
            } label: {
                Text("Section", comment: "Portfolio section picker")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AlohaMetrics.space4)
            .padding(.vertical, AlohaMetrics.space2)

            switch section {
            case .settings: form
            case .preview: previewPage
            }
        }
        .background(palette.background)
        .navigationTitle(Text("Portfolio", comment: "Screen title"))
        .overlay {
            if isLoading { ProgressView() }
        }
        .task { await load() }
        .sensoryFeedback(.success, trigger: didSave)
    }

    // MARK: - Settings

    private var hasChanges: Bool { loaded.map { $0 != settings } ?? false }

    private var form: some View {
        Form {
            if let errorMessage {
                SwiftUI.Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(palette.destructive)
                    if loaded == nil {
                        Button("Try again") { Task { await load() } }
                            .buttonStyle(.glass)
                            .disabled(isLoading)
                    }
                }
            }

            Group {
                SwiftUI.Section {
                    Toggle(isOn: $settings.active) {
                        Text("Publish my portfolio", comment: "Portfolio switch")
                    }
                    if loaded?.active == true, let url = loaded?.url {
                        HStack {
                            Link(destination: url) {
                                Text(url.absoluteString)
                                    .font(AlohaType.meta)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            ShareLink(item: url) {
                                Image(systemName: AlohaSymbol.share)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(
                                Text("Share the address", comment: "Portfolio action"))
                        }
                    }
                } footer: {
                    Text(
                        "A draft is private. Once published, anybody with the address can see the page without signing in.",
                        comment: "Portfolio publish explanation")
                }

                SwiftUI.Section {
                    TextField(
                        session.snapshot.bestDisplayName, text: $settings.title
                    )
                    .onChange(of: settings.title) { _, value in
                        if value.count > 128 { settings.title = String(value.prefix(128)) }
                    }
                    TextField(
                        String(
                            localized: "A sentence about the work",
                            comment: "Portfolio intro placeholder"),
                        text: $settings.intro, axis: .vertical
                    )
                    .lineLimit(3...6)
                    .onChange(of: settings.intro) { _, value in
                        if value.count > 500 { settings.intro = String(value.prefix(500)) }
                    }
                } header: {
                    Text("Title and introduction", comment: "Portfolio section")
                }

                SwiftUI.Section {
                    Picker(selection: $settings.layout) {
                        Text("A grid of squares", comment: "Portfolio layout").tag(
                            PortfolioSettings.Layout.grid)
                        Text("One at a time, at its own shape", comment: "Portfolio layout")
                            .tag(PortfolioSettings.Layout.rows)
                    } label: {
                        Text("Layout", comment: "Portfolio field")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                } header: {
                    Text("Layout", comment: "Portfolio section")
                }

                SwiftUI.Section {
                    Picker(selection: $settings.source) {
                        Text("My most recent public photos", comment: "Portfolio source")
                            .tag(PortfolioSettings.Source.recent)
                        Text("One of my albums", comment: "Portfolio source")
                            .tag(PortfolioSettings.Source.collection)
                    } label: {
                        Text("Pictures", comment: "Portfolio field")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    if settings.source == .collection {
                        Picker(
                            selection: Binding(
                                get: { settings.collectionID ?? "" },
                                set: { settings.collectionID = $0.isEmpty ? nil : $0 })
                        ) {
                            Text("Choose an album", comment: "Portfolio collection placeholder")
                                .tag("")
                            ForEach(collections) { collection in
                                Text(collection.title).tag(collection.id)
                            }
                        } label: {
                            Text("Album", comment: "Portfolio field")
                        }
                        if collections.isEmpty {
                            Text("You have no albums yet.", comment: "Portfolio no collections")
                                .font(.footnote)
                                .foregroundStyle(palette.secondaryLabel)
                        }
                    }
                } header: {
                    Text("Pictures", comment: "Portfolio section")
                }

                SwiftUI.Section {
                    Toggle(isOn: $settings.showCaptions) {
                        Text("Show captions", comment: "Portfolio switch")
                    }
                    Toggle(isOn: $settings.showPlaces) {
                        Text("Show where each picture was taken", comment: "Portfolio switch")
                    }
                    Toggle(isOn: $settings.showDates) {
                        Text("Show the year", comment: "Portfolio switch")
                    }
                    Toggle(isOn: $settings.showAvatar) {
                        Text("Show my picture at the top", comment: "Portfolio switch")
                    }
                } header: {
                    Text("On the page", comment: "Portfolio section")
                }

                SwiftUI.Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Save", comment: "Portfolio action")
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isSaving || !hasChanges)
                }
            }
            .disabled(isLoading || isSaving || loaded == nil)
        }
        .formStyle(.grouped)
        .alohaGround(palette)
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewPage: some View {
        if let page = preview ?? draftPage {
            ScrollView {
                PortfolioPageView(page: page, showsAvatarFallback: session.snapshot.avatarURL)
            }
            .refreshable { await loadPreview() }
        } else if isLoading {
            Color.clear
        } else {
            ContentUnavailableView {
                Text("Nothing on it yet", comment: "Portfolio empty preview")
            } description: {
                Text(
                    "Once you have public photos, or an album is chosen, they show here the way visitors will see them.",
                    comment: "Portfolio empty preview detail")
            }
        }
    }

    /// The page as the settings describe it, from the pictures the server
    /// sent along with them — so a draft can be looked at before publishing.
    private var draftPage: PortfolioPage? {
        let source = loaded ?? settings
        guard !source.posts.isEmpty else { return nil }
        return PortfolioPage(
            title: settings.title.isEmpty ? session.snapshot.bestDisplayName : settings.title,
            intro: settings.intro.isEmpty ? nil : settings.intro,
            handle: session.snapshot.qualifiedHandle,
            avatar: session.snapshot.avatarURL,
            layout: settings.layout,
            showCaptions: settings.showCaptions, showPlaces: settings.showPlaces,
            showDates: settings.showDates, showAvatar: settings.showAvatar,
            posts: source.posts)
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let own = try await session.client.decode(
                PortfolioSettings.self, from: Endpoint.portfolio.own)
            guard !Task.isCancelled else { return }
            settings = own
            loaded = own
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "Portfolio settings could not be loaded. Please try again.")
        }
        // Albums are optional: no albums, no picker, no error.
        collections =
            (try? await session.client.decode(
                LossyArray<Collection>.self, from: Endpoint.portfolio.ownCollections))?.elements
            ?? []
        await loadPreview()
    }

    private func loadPreview() async {
        let request = UUID()
        previewID = request
        guard loaded?.active == true else {
            preview = nil
            return
        }
        let response = try? await session.client.decode(
            PortfolioPage.self, from: Endpoint.portfolio.page(handle: session.snapshot.handle))
        guard !Task.isCancelled, previewID == request else { return }
        preview = response
    }

    private func save() async {
        guard !isSaving, !isLoading, loaded != nil, hasChanges else { return }
        isSaving = true
        previewID = UUID()
        errorMessage = nil
        defer { isSaving = false }
        do {
            let saved = try await session.client.decode(
                PortfolioSettings.self, from: Endpoint.portfolio.save(settings))
            settings = saved
            loaded = saved
            errorMessage = nil
            didSave.toggle()
            await loadPreview()
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "Your portfolio could not be saved. Please try again.")
        }
    }
}

/// The public page itself: header, then the pictures in the chosen layout.
struct PortfolioPageView: View {
    @Environment(\.alohaPalette) private var palette

    let page: PortfolioPage
    var showsAvatarFallback: URL?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 2)]

    var body: some View {
        VStack(spacing: AlohaMetrics.space4) {
            VStack(spacing: AlohaMetrics.space2) {
                if page.showAvatar, let avatar = page.avatar ?? showsAvatarFallback {
                    RemoteImage(url: avatar)
                        .frame(width: 88, height: 88)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                }
                Text(page.title)
                    .font(AlohaType.display)
                    .multilineTextAlignment(.center)
                if let intro = page.intro, !intro.isEmpty {
                    Text(intro)
                        .font(.body)
                        .foregroundStyle(palette.secondaryLabel)
                        .multilineTextAlignment(.center)
                }
                if let handle = page.handle {
                    Text(handle.hasPrefix("@") ? handle : "@\(handle)")
                        .font(AlohaType.meta)
                        .foregroundStyle(palette.tertiaryLabel)
                }
            }
            .padding(.horizontal, AlohaMetrics.space4)
            .padding(.top, AlohaMetrics.space4)

            let pictures = page.posts.filter { $0.picture != nil }
            if pictures.isEmpty {
                Text("Nothing on it yet", comment: "Portfolio empty page")
                    .font(.footnote)
                    .foregroundStyle(palette.tertiaryLabel)
                    .padding(.vertical, AlohaMetrics.space6)
            } else if page.layout == .grid {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(pictures) { post in
                        if let picture = post.picture {
                            RemoteImage(
                                url: picture.displayImageURL, blurhash: picture.blurhash,
                                accessibilityText: picture.description
                            )
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                        }
                    }
                }
            } else {
                LazyVStack(spacing: AlohaMetrics.space5) {
                    ForEach(pictures) { post in
                        row(post)
                    }
                }
                .padding(.horizontal, AlohaMetrics.space3)
            }
        }
        .padding(.bottom, AlohaMetrics.space6)
    }

    @ViewBuilder
    private func row(_ post: PortfolioPost) -> some View {
        if let picture = post.picture {
            VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                RemoteImage(
                    url: picture.url ?? picture.previewURL, blurhash: picture.blurhash,
                    contentMode: .fit, accessibilityText: picture.description
                )
                .aspectRatio(picture.displayAspectRatio, contentMode: .fit)
                .clipShape(
                    RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous))

                if page.showCaptions, let content = post.content {
                    let caption = StatusHTMLParser().plainText(content)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !caption.isEmpty {
                        Text(caption)
                            .font(.footnote)
                    }
                }

                let facts = footer(post)
                if !facts.isEmpty {
                    Text(facts.joined(separator: " · "))
                        .font(AlohaType.meta)
                        .foregroundStyle(palette.tertiaryLabel)
                }
            }
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }

    private func footer(_ post: PortfolioPost) -> [String] {
        var facts: [String] = []
        if page.showPlaces, let place = post.place {
            let name = [place.name, place.country].compactMap { $0 }.filter { !$0.isEmpty }
            if !name.isEmpty { facts.append(name.joined(separator: ", ")) }
        }
        if page.showDates, let date = post.createdAt {
            facts.append(date.formatted(.dateTime.year()))
        }
        return facts
    }
}
