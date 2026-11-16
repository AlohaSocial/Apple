// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// "Your year": the year in review as a full-screen story — what you posted,
/// the month you posted most, the hashtags you used and the posts that
/// travelled furthest, one card at a time.
///
/// Mastodon's `#Wrapstodon`. Nextcloud Social serves it over the API and has no
/// web page of its own for it yet, so this is the first place anybody can read
/// one (docs/05 §9).
///
/// Cards advance on their own behind a progress bar; a tap on the leading
/// third goes back and anywhere else goes forward, and holding a finger down
/// pauses. Every gesture has a button too (docs/12 §3, Switch Control). Under
/// Reduce Motion or VoiceOver nothing moves on by itself — see
/// `AnnualReportStory.advancesAutomatically` — and paging by hand works the
/// same. Each card can be shared as a picture, drawn from the very view on
/// screen.
///
/// The report is a query rather than a job on this server, so there is nothing
/// to wait for and no spinner that means "generating" — `generate` is still
/// called first, because a server that does need it will act on it and this
/// screen should work against Mastodon too.
public struct AnnualReportView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var wrapped: WrappedAnnualReports?
    @State private var selectedYear: Int?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadID = UUID()

    // MARK: Playback

    @State private var index = 0
    /// How far through the current card, 0…1. Only moves while cards
    /// advance on their own.
    @State private var progress: Double = 0
    /// A finger is resting on the card.
    @State private var isHolding = false
    /// Paused with the button, which stays paused until pressed again.
    @State private var isPausedByButton = false
    /// Which way the last page went, so the slide comes from the right side.
    @State private var wentForward = true
    @State private var holdTimer: Task<Void, Never>?
    @State private var cardWidth: CGFloat = 0
    /// The current card drawn as a picture, ready for the share button.
    @State private var shareImage: Image?

    public init(session: AccountSession, onAction: @escaping (StatusRowAction) -> Void) {
        self.session = session
        self.onAction = onAction
    }

    private var reports: [AnnualReport] {
        (wrapped?.annualReports ?? []).sorted { $0.year > $1.year }
    }

    private var report: AnnualReport? {
        guard let selectedYear else { return reports.first }
        return reports.first { $0.year == selectedYear }
    }

    private var cards: [AnnualReportStory.Card] {
        report.map { AnnualReportStory.cards(for: $0, in: wrapped) } ?? []
    }

    private var currentCard: AnnualReportStory.Card? {
        cards.indices.contains(index) ? cards[index] : cards.last
    }

    private var advancesAutomatically: Bool {
        #if DEBUG
            // The tours read a card and photograph it: a card that moves on
            // under them is a flaky test, and a progress bar redrawn every
            // 50 ms keeps the app from ever going idle, which slows every
            // query that follows. Paging by hand still works.
            if MockMode.isEnabled { return false }
        #endif
        return AnnualReportStory.advancesAutomatically(
            reduceMotion: reduceMotion, voiceOver: voiceOver)
    }

    private var isPaused: Bool {
        isHolding || isPausedByButton || scenePhase != .active
    }

    public var body: some View {
        Group {
            if let report, let card = currentCard {
                player(report, card: card)
            } else {
                placeholder
            }
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle(Text("Your year", comment: "Screen title"))
        #if os(iOS)
            // Full screen once there is a story to tell; the bars come back
            // for the loading, empty and error states, which need a way out
            // that is not a story control.
            .toolbarVisibility(report == nil ? .automatic : .hidden, for: .navigationBar)
            .toolbarVisibility(report == nil ? .automatic : .hidden, for: .tabBar)
            .statusBarHidden(report != nil)
        #endif
        .task { await load() }
        .task(id: PlaybackKey(year: report?.year, index: index, runs: advancesAutomatically)) {
            await play()
        }
        .task(id: ShareKey(year: report?.year, card: currentCard, scheme: colorScheme)) {
            // Drawn a moment after the card settles rather than during the
            // slide, so the transition never waits for a renderer.
            shareImage = nil
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let report, let card = currentCard else { return }
            shareImage = renderShareImage(card, report: report)
        }
    }

    // MARK: - States

    @ViewBuilder
    private var placeholder: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            VStack(spacing: AlohaMetrics.space3) {
                Label(errorMessage, systemImage: AlohaSymbol.warning)
                    .font(.footnote)
                    .foregroundStyle(palette.destructive)
                Button {
                    Task { await load() }
                } label: {
                    Text("Retry", comment: "Annual report retry action")
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
            }
            .padding(AlohaMetrics.space4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Text("No year to look back on yet", comment: "Annual report empty")
            } description: {
                Text(
                    "A year you posted in gets a report. Come back once you have written something.",
                    comment: "Annual report empty detail")
            }
        }
    }

    // MARK: - Player

    private func player(_ report: AnnualReport, card: AnnualReportStory.Card) -> some View {
        VStack(spacing: AlohaMetrics.space2) {
            topBar
            AnnualReportCardView(
                card: card, report: report,
                showsCounts: session.settings.showPopularityCounts,
                onOpen: { onAction(.open($0)) }
            )
            .id("\(report.year)-\(card.id)")
            .transition(cardTransition)
            .clipShape(RoundedRectangle(cornerRadius: AlohaMetrics.cornerLarge))
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                cardWidth = $0
            }
            .gesture(pressGesture)
            .accessibilityElement(children: .contain)
            .accessibilityValue(
                Text(
                    "Card \(min(index, cards.count - 1) + 1) of \(cards.count)",
                    comment: "Annual report: which card is showing")
            )
            .accessibilityAction(named: Text("Next card", comment: "Annual report action")) {
                page(by: 1)
            }
            .accessibilityAction(named: Text("Previous card", comment: "Annual report action")) {
                page(by: -1)
            }
            bottomBar
        }
        .padding(.horizontal, AlohaMetrics.space3)
        .padding(.vertical, AlohaMetrics.space2)
    }

    private var cardTransition: AnyTransition {
        // A cross-fade under Reduce Motion, a slide otherwise (docs/05 §2).
        if reduceMotion { return .opacity }
        return .push(
            from: (wentForward == (layoutDirection == .leftToRight)) ? .trailing : .leading)
    }

    private var topBar: some View {
        VStack(spacing: AlohaMetrics.space2) {
            progressBar
            HStack {
                if reports.count > 1 {
                    yearMenu
                }
                Spacer()
                #if os(iOS)
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.label)
                    .accessibilityLabel(Text("Close", comment: "Annual report close action"))
                #endif
            }
        }
    }

    /// One segment per card: the past full, the present filling, the future
    /// empty. Drawn rather than read out — the card itself says "Card 2 of 6".
    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(cards.enumerated()), id: \.offset) { offset, _ in
                Capsule()
                    .fill(palette.label.opacity(0.2))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(palette.label)
                            .scaleEffect(x: fill(for: offset), anchor: .leading)
                    }
                    .frame(height: 3)
            }
        }
        .environment(\.layoutDirection, layoutDirection)
        .accessibilityHidden(true)
    }

    private func fill(for offset: Int) -> CGFloat {
        if offset < index { return 1 }
        if offset > index { return 0 }
        // Without auto-advance there is no time running out: the card is
        // simply the one being read.
        return advancesAutomatically ? progress : 1
    }

    private var yearMenu: some View {
        Menu {
            Picker(selection: Binding(get: { report?.year ?? 0 }, set: { choose(year: $0) })) {
                ForEach(reports) { report in
                    Text(verbatim: String(report.year)).tag(report.year)
                }
            } label: {
                Text("Year", comment: "Annual report year picker")
            }
        } label: {
            HStack(spacing: AlohaMetrics.space1) {
                Text(verbatim: String(report?.year ?? 0))
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.label)
            .frame(minHeight: 44)
        }
        .accessibilityLabel(Text("Year", comment: "Annual report year picker"))
        .accessibilityValue(Text(verbatim: String(report?.year ?? 0)))
    }

    /// Every gesture again as a button: back, pause, share, forward.
    private var bottomBar: some View {
        HStack {
            barButton(
                "chevron.backward", Text("Previous card", comment: "Annual report action")
            ) { page(by: -1) }
            .disabled(index == 0)
            Spacer()
            if advancesAutomatically {
                barButton(
                    isPausedByButton ? AlohaSymbol.play : AlohaSymbol.pause,
                    isPausedByButton
                        ? Text("Play", comment: "Annual report action")
                        : Text("Pause", comment: "Annual report action")
                ) { isPausedByButton.toggle() }
                Spacer()
            }
            shareButton
            Spacer()
            barButton(
                "chevron.forward", Text("Next card", comment: "Annual report action")
            ) { page(by: 1) }
            .disabled(index >= cards.count - 1)
        }
        .foregroundStyle(palette.label)
    }

    private func barButton(
        _ symbol: String, _ label: Text, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    @ViewBuilder
    private var shareButton: some View {
        let label = Text("Share this card", comment: "Annual report action")
        if let shareImage {
            ShareLink(
                item: shareImage,
                preview: SharePreview(
                    Text("Your year", comment: "Annual report share preview title"),
                    image: shareImage)
            ) {
                Image(systemName: AlohaSymbol.share)
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .help(label)
        } else {
            Image(systemName: AlohaSymbol.share)
                .font(.body.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(palette.tertiaryLabel)
                .accessibilityLabel(label)
                .accessibilityAddTraits(.isButton)
                .accessibilityRemoveTraits(.isImage)
        }
    }

    // MARK: - Gestures

    /// One gesture for tap, hold and swipe, so they cannot fight: a touch
    /// that rests a quarter of a second pauses until it lifts, a short touch
    /// pages by where it landed, and a horizontal swipe pages by direction.
    /// Buttons and links on a card take their own taps first.
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard holdTimer == nil else { return }
                holdTimer = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    isHolding = true
                }
            }
            .onEnded { value in
                holdTimer?.cancel()
                holdTimer = nil
                let wasHolding = isHolding
                isHolding = false
                let dx = value.translation.width
                let dy = value.translation.height
                if abs(dx) > 40, abs(dx) > abs(dy) {
                    // Swiping towards the leading edge brings the next card.
                    let towardsLeading = (dx < 0) == (layoutDirection == .leftToRight)
                    page(by: towardsLeading ? 1 : -1)
                } else if !wasHolding, abs(dx) < 10, abs(dy) < 10 {
                    let back = AnnualReportStory.tapGoesBack(
                        atX: value.location.x, width: cardWidth,
                        rightToLeft: layoutDirection == .rightToLeft)
                    page(by: back ? -1 : 1)
                }
            }
    }

    private func page(by step: Int) {
        let target = index + step
        guard cards.indices.contains(target) else {
            // Back from the first card starts it again, as every story
            // player does; forward from the last stays put.
            if step < 0 { progress = 0 }
            return
        }
        wentForward = step > 0
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.3)) {
            index = target
        }
        progress = 0
        if voiceOver {
            // The new card is new content; VoiceOver starts reading it.
            AccessibilityNotification.ScreenChanged().post()
        }
    }

    private func choose(year: Int) {
        selectedYear = year
        index = 0
        progress = 0
    }

    /// The clock behind the progress bar. Restarted for every card (the
    /// task's id), and doing nothing at all when cards do not advance on
    /// their own.
    private func play() async {
        guard advancesAutomatically, !cards.isEmpty else { return }
        let tick = Duration.milliseconds(50)
        let step = tick / AnnualReportStory.cardDuration
        while !Task.isCancelled {
            try? await Task.sleep(for: tick)
            guard !Task.isCancelled else { return }
            guard !isPaused else { continue }
            progress = min(1, progress + step)
            if progress >= 1 {
                // The last card stays, full, until the reader leaves.
                if index < cards.count - 1 { page(by: 1) }
                return
            }
        }
    }

    // MARK: - Sharing

    /// The card at a phone's story proportions, three times over for a sharp
    /// picture, in the colours on screen and at the default text size — a
    /// shared picture is read on somebody else's phone, at their size, and
    /// the reader's accessibility size would make it a different card.
    private func renderShareImage(_ card: AnnualReportStory.Card, report: AnnualReport) -> Image? {
        let size = CGSize(width: 360, height: 640)
        let content = VStack(spacing: 0) {
            AnnualReportCardView(
                card: card, report: report,
                showsCounts: session.settings.showPopularityCounts, isInteractive: false)
            HStack(spacing: AlohaMetrics.space2) {
                BrandMark(size: 18)
                Text(verbatim: "Aloha Social")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryLabel)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AlohaMetrics.space3)
            .background(palette.background)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.alohaPalette, palette)
        .environment(\.colorScheme, colorScheme)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.layoutDirection, layoutDirection)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 3
        guard let image = renderer.cgImage else { return nil }
        return Image(decorative: image, scale: 3)
    }

    /// What restarts the clock: another card, another year, or auto-advance
    /// switching on or off (VoiceOver starting, Reduce Motion changing).
    private struct PlaybackKey: Hashable {
        var year: Int?
        var index: Int
        var runs: Bool
    }

    /// What makes the shared picture stale.
    private struct ShareKey: Hashable {
        var year: Int?
        var card: AnnualReportStory.Card?
        var scheme: ColorScheme
    }

    // MARK: - Words

    /// The archetype in a sentence rather than a bare word: "oracle" on its own
    /// is a label, and the point of the line is to say what the year was like.
    static func archetypeLine(_ archetype: AnnualArchetype) -> String {
        switch archetype {
        case .lurker:
            String(
                localized: "A quiet year — you read more than you wrote.",
                comment: "Annual archetype")
        case .booster:
            String(localized: "A year of passing things on.", comment: "Annual archetype")
        case .pollster:
            String(localized: "A year of asking.", comment: "Annual archetype")
        case .replier:
            String(localized: "A year of answering other people.", comment: "Annual archetype")
        case .oracle:
            String(localized: "A year of writing, and of being read.", comment: "Annual archetype")
        case .unknownCase:
            String(localized: "Your year.", comment: "Annual archetype")
        }
    }

    static func monthName(_ month: Int, short: Bool = true) -> String {
        let symbols =
            short ? Calendar.current.shortMonthSymbols : Calendar.current.standaloneMonthSymbols
        guard month >= 1, month <= symbols.count else { return String(month) }
        return symbols[month - 1]
    }

    // MARK: - Data

    private func load() async {
        let request = UUID()
        loadID = request
        isLoading = true
        errorMessage = nil
        defer { if loadID == request { isLoading = false } }
        // The server answers instantly and changes nothing; Mastodon needs it.
        _ = try? await session.client.send(
            Endpoint.annualReports.generate(Self.lastCompleteYear))
        guard !Task.isCancelled, loadID == request else { return }
        do {
            let response = try await session.client.decode(
                WrappedAnnualReports.self, from: Endpoint.annualReports.all)
            guard !Task.isCancelled, loadID == request else { return }
            wrapped = response
            if let selectedYear,
                !response.annualReports.contains(where: { $0.year == selectedYear })
            {
                self.selectedYear = nil
            }
            if index >= cards.count { index = 0 }
            errorMessage = nil
        } catch APIError.notFound {
            guard !Task.isCancelled, loadID == request else { return }
            // A server without the feature is not a broken screen.
            wrapped = WrappedAnnualReports()
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, loadID == request else { return }
            await session.handle(error)
            guard !Task.isCancelled, loadID == request else { return }
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "Your annual report could not be loaded. Please try again.")
        }
    }

    /// The most recent year there can be a full report for.
    static var lastCompleteYear: Int {
        Calendar.current.component(.year, from: Date()) - 1
    }
}
