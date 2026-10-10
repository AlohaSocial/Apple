// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// "My interests": the feed Nextcloud Social builds from the hashtags it has
/// learned you read, and the switches and cloud that govern the learning.
///
/// One screen with two faces rather than a feed and a settings page apart:
/// the feed only makes sense once you have seen what it is made of, and the
/// settings only matter because of the feed.
public struct InterestsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var face: Face = .feed
    @State private var statuses: [Status] = []
    @State private var nextPage: URL?
    @State private var mayHaveMore = true
    @State private var isLoading = true
    @State private var isPagingOlder = false
    @State private var state = InterestsState()
    @State private var isStateLoaded = false
    @State private var errorMessage: String?
    @State private var hiddenIDs: Set<String> = []
    @State private var refreshID = UUID()

    private var visibleStatuses: [Status] {
        statuses.filter { !hiddenIDs.contains($0.displayed.id) }
    }

    enum Face: Hashable {
        case feed, settings
    }

    public init(session: AccountSession, onAction: @escaping (StatusRowAction) -> Void) {
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        Group {
            switch face {
            case .feed: feed
            case .settings:
                InterestsSettingsView(session: session, state: $state, isLoaded: $isStateLoaded)
            }
        }
        .background(palette.background)
        .navigationTitle(Text("My interests", comment: "Screen title"))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(selection: $face) {
                    Text("Feed", comment: "Interests face").tag(Face.feed)
                    Text("Settings", comment: "Interests face").tag(Face.settings)
                } label: {
                    Text("Section", comment: "Interests face picker")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
        }
        .task {
            await loadState()
            await refresh()
        }
    }

    // MARK: - Feed

    private var feed: some View {
        List {
            if let errorMessage {
                HStack(spacing: AlohaMetrics.space2) {
                    Image(systemName: AlohaSymbol.warning)
                        .accessibilityHidden(true)
                    Text(errorMessage).font(.footnote)
                    Spacer()
                    Button {
                        Task { await refresh() }
                    } label: {
                        Text("Retry", comment: "Interests retry action")
                    }
                    .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(palette.destructive)
                .padding(.vertical, AlohaMetrics.space2)
                .listRowBackground(palette.background)
            }

            if isStateLoaded && !state.settings.learning {
                learningOffNotice
            }

            ForEach(visibleStatuses) { status in
                StatusRow(
                    status: status,
                    policy: session.settings.sensitiveMediaPolicy,
                    localHost: session.snapshot.instanceHost,
                    canReact: session.capabilities.emojiReactions,
                    isOwn: status.displayed.account.id == session.snapshot.serverAccountID,
                    showsCounts: session.settings.showPopularityCounts,
                    onAction: onAction
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowBackground(palette.background)
                .listRowSeparator(.hidden)
                .contextMenu {
                    Button {
                        Task { await showFewer(like: status) }
                    } label: {
                        Label {
                            Text("Show fewer like this", comment: "Interests row action")
                        } icon: {
                            Image(systemName: "hand.thumbsdown")
                        }
                    }
                }
                .onAppear {
                    if status.id == visibleStatuses.last?.id {
                        Task { await loadOlder() }
                    }
                }
            }

            if isPagingOlder {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(palette.background)
                .listRowSeparator(.hidden)
            }

            // A first page arriving is a list in progress, not a blank screen.
            if isLoading && statuses.isEmpty {
                SkeletonListRow(person: 4)
                    .listRowBackground(palette.background)
                    .listRowSeparator(.hidden)
            }

            if statuses.isEmpty && !isLoading && errorMessage == nil {
                emptyState
                    .listRowBackground(palette.background)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .alohaGround(palette)
        .refreshable { await refresh() }
    }

    private var learningOffNotice: some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: "pause.circle")
            Text(
                "Learning is off, so this feed stays as it is. Turn it on in Settings.",
                comment: "Interests feed notice"
            )
            .font(.footnote)
        }
        .foregroundStyle(palette.secondaryLabel)
        .padding(AlohaMetrics.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            palette.surfaceRaised,
            in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous)
        )
        .listRowBackground(palette.background)
        .listRowSeparator(.hidden)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Text("Nothing here yet", comment: "Empty interests feed")
        } description: {
            if state.thin || state.interests.isEmpty {
                Text(
                    "Your server learns which hashtags you read and builds this feed from them. Read a little, or add some interests in Settings.",
                    comment: "Empty interests feed explanation")
            } else {
                Text(
                    "Nobody has posted with your interests lately.",
                    comment: "Empty interests feed with interests")
            }
        } actions: {
            Button {
                face = .settings
            } label: {
                Text("Add interests", comment: "Empty interests feed action")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, AlohaMetrics.space6)
    }

    // MARK: - Loading

    private func loadState() async {
        guard
            let loaded = try? await session.client.decode(
                InterestsState.self, from: Endpoint.interests.state)
        else { return }
        guard !Task.isCancelled, !isStateLoaded else { return }
        state = loaded
        isStateLoaded = true
    }

    private func refresh() async {
        let request = UUID()
        refreshID = request
        isLoading = true
        isPagingOlder = false
        errorMessage = nil
        defer { if refreshID == request { isLoading = false } }
        do {
            let page = try await session.client.page(
                LossyArray<Status>.self, from: Endpoint.interests.timeline(limit: 20), limit: 20)
            guard !Task.isCancelled, refreshID == request else { return }
            statuses = page.value.elements
            nextPage = page.link.next
            mayHaveMore = page.mayHaveMore
            errorMessage = nil
            await session.latchCapabilities(observing: statuses)
        } catch {
            guard !Task.isCancelled, refreshID == request else { return }
            await session.handle(error)
            guard !Task.isCancelled, refreshID == request else { return }
            errorMessage = (error as? APIError)?.errorDescription
                ?? String(localized: "Your interests feed could not be loaded. Please try again.")
        }
    }

    private func loadOlder() async {
        guard mayHaveMore, !isPagingOlder, !isLoading else { return }
        let request = refreshID
        isPagingOlder = true
        defer { if refreshID == request { isPagingOlder = false } }
        do {
            let page: Paginated<LossyArray<Status>>
            if let nextPage {
                page = try await session.client.page(
                    LossyArray<Status>.self, following: nextPage, limit: 20)
            } else if let last = statuses.last {
                page = try await session.client.page(
                    LossyArray<Status>.self,
                    from: Endpoint.interests.timeline(limit: 20, anchor: .olderThan(last.id)),
                    limit: 20)
            } else {
                return
            }
            guard !Task.isCancelled, refreshID == request else { return }
            let known = Set(statuses.map(\.id))
            statuses += page.value.elements.filter { !known.contains($0.id) }
            self.nextPage = page.link.next
            mayHaveMore = page.mayHaveMore && !page.value.elements.isEmpty
        } catch {
            guard !Task.isCancelled, refreshID == request else { return }
            await session.handle(error)
            guard !Task.isCancelled, refreshID == request else { return }
            errorMessage = (error as? APIError)?.errorDescription
                ?? String(localized: "More posts could not be loaded. Please try again.")
        }
    }

    /// Hides the row at once; the server call is what makes it stick.
    private func showFewer(like status: Status) async {
        let id = status.displayed.id
        guard hiddenIDs.insert(id).inserted else { return }
        do {
            _ = try await session.client.send(Endpoint.interests.fewerLikeThis(id))
        } catch {
            withAnimation { _ = hiddenIDs.remove(id) }
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
                ?? String(localized: "Your feed preference could not be saved. Please try again.")
        }
    }
}

// MARK: - Settings

/// The learning switches, the interest cloud, the candidates, languages, and
/// the reset — everything that shapes the feed.
struct InterestsSettingsView: View {
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession
    @Binding var state: InterestsState
    @Binding var isLoaded: Bool

    @State private var newTag = ""
    @State private var suggestions: [Tag] = []
    @State private var isAdding = false
    @State private var isShowingCandidates = false
    @State private var isConfirmingReset = false
    @State private var errorMessage: String?
    @State private var languageDraft = ""
    @State private var isWorking = false
    @State private var isLoadingState = false

    var body: some View {
        List {
            if let errorMessage {
                HStack(spacing: AlohaMetrics.space2) {
                    Image(systemName: AlohaSymbol.warning)
                        .accessibilityHidden(true)
                    Text(errorMessage).font(.footnote)
                    Spacer()
                    Button {
                        Task { await load() }
                    } label: {
                        Text("Retry", comment: "Interests retry action")
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.glass)
                    .disabled(isWorking || isLoadingState)
                }
                .foregroundStyle(palette.destructive)
            }

            Group {
                learningSection
                cloudSection
                if !state.candidates.isEmpty { candidatesSection }
                languagesSection
                resetSection
            }
            .disabled(!isLoaded || isWorking || isLoadingState)
        }
        .alohaGround(palette)
        .overlay { if isLoadingState && !isLoaded { ProgressView() } }
        .task { if !isLoaded { await load() } }
        .refreshable { await load() }
        .alert(
            Text("Reset your interests?", comment: "Interests reset confirmation title"),
            isPresented: $isConfirmingReset
        ) {
            Button(role: .destructive) {
                Task { await reset() }
            } label: {
                Text("Reset", comment: "Interests reset action")
            }
            Button(role: .cancel) {
            } label: {
                Text("Cancel", comment: "Interests reset action")
            }
        } message: {
            Text(
                "Everything the server has learned goes, and the feed starts over.",
                comment: "Interests reset confirmation detail")
        }
    }

    private var learningSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { state.settings.learning },
                    set: { value in Task { await save(learning: value) } })
            ) {
                Text("Learn from my reading", comment: "Interests setting")
            }
            Toggle(
                isOn: Binding(
                    get: { state.settings.paused },
                    set: { value in Task { await save(paused: value) } })
            ) {
                Text("Pause learning", comment: "Interests setting")
            }
            .disabled(!state.settings.learning)
        } header: {
            Text("Learning", comment: "Interests section")
        } footer: {
            if !state.settings.learning {
                Text(
                    "Nothing you read changes your interests. The feed keeps what it has.",
                    comment: "Interests learning off explanation")
            } else if state.settings.paused {
                Text(
                    "Learning is paused for now; what the server knows stays as it is.",
                    comment: "Interests paused explanation")
            } else if state.thin {
                Text(
                    "The server keeps track of which hashtags you spend time on. It has not seen much yet.",
                    comment: "Interests thin explanation")
            } else {
                Text(
                    "The server keeps track of which hashtags you spend time on, and nothing else. It stays on your server.",
                    comment: "Interests learning explanation")
            }
        }
    }

    private var cloudSection: some View {
        Section {
            if state.interests.isEmpty {
                Text("No interests yet. Add one below.", comment: "Empty interest cloud")
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
            } else {
                InterestCloud(tags: state.interests) { tag in
                    Task { await remove(tag) }
                } onTogglePin: { tag in
                    Task { await togglePin(tag) }
                }
            }

            VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                HStack(spacing: AlohaMetrics.space2) {
                    Text(verbatim: "#")
                        .foregroundStyle(palette.tertiaryLabel)
                    TextField(
                        String(localized: "Add a hashtag", comment: "Interests add field prompt"),
                        text: $newTag
                    )
                    .textFieldStyle(.plain)
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .onSubmit { Task { await add(newTag) } }
                    .accessibilityLabel(
                        Text("Hashtag to add", comment: "Interests add field label"))

                    Button {
                        Task { await add(newTag) }
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!canAdd || isAdding)
                    .accessibilityLabel(Text("Add interest", comment: "Interests add action"))
                }

                if !suggestions.isEmpty {
                    ScrollView(.horizontal) {
                        GlassEffectContainer(spacing: AlohaMetrics.space2) {
                            HStack(spacing: AlohaMetrics.space2) {
                                ForEach(suggestions) { tag in
                                    Button {
                                        Task { await add(tag.name) }
                                    } label: {
                                        Text(verbatim: "#\(tag.name)")
                                            .font(.footnote)
                                            .padding(.horizontal, AlohaMetrics.space3)
                                            .frame(minHeight: 32)
                                    }
                                    .buttonStyle(.glass)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .task(id: newTag) { await suggest() }
        } header: {
            Text("Interests", comment: "Interests section")
        } footer: {
            Text(
                "Bigger means the server is surer. Pinned interests stay put whatever you read.",
                comment: "Interest cloud explanation")
        }
    }

    private var candidatesSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isShowingCandidates) {
                InterestChips(tags: state.candidates, symbol: "plus") { tag in
                    Task { await add(tag.tag) }
                }
            } label: {
                Text(
                    "^[\(state.candidates.count) hashtag](inflect: true) learned, not yet an interest",
                    comment: "Interests candidates disclosure"
                )
                .font(.subheadline)
            }
        } footer: {
            Text(
                "Hashtags you have read but not enough to count. Tap one to make it an interest.",
                comment: "Interests candidates explanation")
        }
    }

    private var languagesSection: some View {
        Section {
            if state.settings.languages.isEmpty {
                Text("All languages", comment: "Interests languages empty")
                    .foregroundStyle(palette.secondaryLabel)
            } else {
                ForEach(state.settings.languages, id: \.self) { code in
                    HStack {
                        Text(Locale.current.localizedString(forLanguageCode: code) ?? code)
                        Spacer()
                        Text(code)
                            .font(AlohaType.meta)
                            .foregroundStyle(palette.tertiaryLabel)
                    }
                }
                .onDelete { offsets in
                    var languages = state.settings.languages
                    languages.remove(atOffsets: offsets)
                    Task { await save(languages: languages) }
                }
            }

            HStack(spacing: AlohaMetrics.space2) {
                TextField(
                    String(
                        localized: "Language code, like de",
                        comment: "Interests language field prompt"),
                    text: $languageDraft
                )
                .textFieldStyle(.plain)
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .onSubmit { addLanguage() }
                .accessibilityLabel(
                    Text("Language to add", comment: "Interests language field label"))

                Button {
                    addLanguage()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glassProminent)
                .disabled(!isLanguageDraftValid)
                .accessibilityLabel(Text("Add language", comment: "Interests language add action"))
            }
        } header: {
            Text("Languages", comment: "Interests section")
        } footer: {
            Text(
                "Only posts in these languages reach the feed. Leave it empty for all of them.",
                comment: "Interests languages explanation")
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingReset = true
            } label: {
                Text("Reset my interests", comment: "Interests reset action")
            }
        }
    }

    // MARK: - State

    private var canAdd: Bool { Tag.normalise(newTag) != nil }

    private var isLanguageDraftValid: Bool {
        let code = languageDraft.trimmingCharacters(in: .whitespaces).lowercased()
        return (2...3).contains(code.count) && code.allSatisfy(\.isLetter)
            && !state.settings.languages.contains(code)
    }

    private func load() async {
        guard !isWorking, !isLoadingState else { return }
        isLoadingState = true
        errorMessage = nil
        defer { isLoadingState = false }
        do {
            let response = try await session.client.decode(
                InterestsState.self, from: Endpoint.interests.state)
            guard !Task.isCancelled else { return }
            state = response
            isLoaded = true
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
                ?? String(localized: "Interests could not be loaded. Please try again.")
        }
    }

    /// Every write answers with the whole state, so one handler fits all.
    @discardableResult
    private func apply(_ endpoint: Endpoint) async -> Bool {
        guard isLoaded, !isWorking, !isLoadingState else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            state = try await session.client.decode(InterestsState.self, from: endpoint)
            errorMessage = nil
            return true
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
                ?? String(localized: "Your interests could not be updated. Please try again.")
            return false
        }
    }

    @discardableResult
    private func save(learning: Bool? = nil, paused: Bool? = nil, languages: [String]? = nil) async -> Bool
    {
        guard isLoaded, !isWorking, !isLoadingState else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        // Settings answer with the settings object alone; reload for the rest.
        do {
            _ = try await session.client.send(
                Endpoint.interests.settings(
                    learning: learning, paused: paused, languages: languages))
            if let learning { state.settings.learning = learning }
            if let paused { state.settings.paused = paused }
            if let languages { state.settings.languages = languages }
            errorMessage = nil
            return true
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
                ?? String(localized: "Interest settings could not be saved. Please try again.")
            return false
        }
    }

    private func add(_ raw: String) async {
        guard !isAdding, !isWorking, let tag = Tag.normalise(raw) else { return }
        let submittedDraft = newTag
        isAdding = true
        defer { isAdding = false }
        if await apply(Endpoint.interests.add(tag)), newTag == submittedDraft {
            newTag = ""
            suggestions = []
        }
    }

    private func remove(_ tag: InterestTag) async {
        await apply(Endpoint.interests.remove(tag.tag))
    }

    private func togglePin(_ tag: InterestTag) async {
        await apply(
            tag.pinned ? Endpoint.interests.unpin(tag.tag) : Endpoint.interests.pin(tag.tag))
    }

    private func reset() async {
        await apply(Endpoint.interests.reset)
    }

    private func addLanguage() {
        guard isLanguageDraftValid, !isWorking, !isLoadingState else { return }
        let submittedDraft = languageDraft
        let code = languageDraft.trimmingCharacters(in: .whitespaces).lowercased()
        let languages = state.settings.languages + [code]
        Task {
            if await save(languages: languages), languageDraft == submittedDraft {
                languageDraft = ""
            }
        }
    }

    private func suggest() async {
        guard let query = Tag.normalise(newTag), query.count >= 2 else {
            suggestions = []
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let found = try? await session.client.decode(
            SearchResults.self, from: Endpoint.search.search(query, type: "hashtags", limit: 6))
        guard !Task.isCancelled else { return }
        let mine = Set(state.interests.map(\.id))
        suggestions = (found?.hashtags ?? []).filter { !mine.contains($0.id) }
    }
}

// MARK: - Cloud and chips

/// The interests as a cloud: every tag a chip, its size following the score.
struct InterestCloud: View {
    @Environment(\.alohaPalette) private var palette

    let tags: [InterestTag]
    let onRemove: (InterestTag) -> Void
    let onTogglePin: (InterestTag) -> Void

    private var maximum: Double { max(tags.map(\.score).max() ?? 1, 0.001) }

    var body: some View {
        GlassEffectContainer(spacing: AlohaMetrics.space2) {
            FlowLayout(spacing: AlohaMetrics.space2) {
                ForEach(tags) { tag in
                    HStack(spacing: AlohaMetrics.space1) {
                        if tag.pinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .accessibilityLabel(Text("Pinned", comment: "Interest pinned state"))
                        }
                        Text(verbatim: "#\(tag.tag)")
                            .font(font(for: tag))
                        Button {
                            onRemove(tag)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityLabel(
                            Text("Remove \(tag.tag)", comment: "Interest remove action"))
                    }
                    .padding(.leading, AlohaMetrics.space3)
                    .padding(.trailing, AlohaMetrics.space1)
                    .frame(minHeight: 44)
                    .background {
                        if tag.pinned { Capsule().fill(palette.accentMuted) }
                    }
                    .glassEffect(.regular, in: Capsule())
                    .contextMenu {
                        Button {
                            onTogglePin(tag)
                        } label: {
                            if tag.pinned {
                                Label {
                                    Text("Unpin", comment: "Interest action")
                                } icon: {
                                    Image(systemName: "pin.slash")
                                }
                            } else {
                                Label {
                                    Text("Pin", comment: "Interest action")
                                } icon: {
                                    Image(systemName: "pin")
                                }
                            }
                        }
                        Button(role: .destructive) {
                            onRemove(tag)
                        } label: {
                            Label {
                                Text("Remove", comment: "Interest action")
                            } icon: {
                                Image(systemName: "xmark")
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, AlohaMetrics.space1)
    }

    /// The cloud's weight as Dynamic Type styles, so it grows with the
    /// reader's own text size rather than clipping at a fixed point size.
    private func font(for tag: InterestTag) -> Font {
        let weight = min(max(tag.score / maximum, 0), 1)
        let base: Font
        if weight < 0.25 { base = .caption }
        else if weight < 0.5 { base = .footnote }
        else if weight < 0.75 { base = .subheadline }
        else { base = .title3 }
        return tag.pinned ? base.weight(.semibold) : base
    }
}

/// Candidates as plain chips with one action.
struct InterestChips: View {
    let tags: [InterestTag]
    let symbol: String
    let onTap: (InterestTag) -> Void

    var body: some View {
        GlassEffectContainer(spacing: AlohaMetrics.space2) {
            FlowLayout(spacing: AlohaMetrics.space2) {
                ForEach(tags) { tag in
                    Button {
                        onTap(tag)
                    } label: {
                        HStack(spacing: AlohaMetrics.space1) {
                            Image(systemName: symbol).font(.caption)
                            Text(verbatim: "#\(tag.tag)").font(.footnote)
                        }
                        .padding(.horizontal, AlohaMetrics.space3)
                        .frame(minHeight: 36)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel(
                        Text("Add \(tag.tag)", comment: "Interest candidate action"))
                }
            }
        }
        .padding(.vertical, AlohaMetrics.space1)
    }
}

/// Wraps its children onto as many lines as the width needs.
struct FlowLayout: Layout {
    var spacing: Double = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return arrange(subviews, width: width).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let arrangement = arrange(subviews, width: bounds.width)
        for (subview, origin) in zip(subviews, arrangement.origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: Double) -> (size: CGSize, origins: [CGPoint])
    {
        var origins: [CGPoint] = []
        var x = 0.0
        var y = 0.0
        var rowHeight = 0.0
        var maxX = 0.0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: width.isFinite ? width : maxX, height: y + rowHeight), origins)
    }
}
