// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The people your follows follow, drawn as a constellation you can drag
/// around and follow from.
///
/// Nextcloud Social's `FollowConstellation.vue`. The data is the same walk the
/// suggestion list uses — `/api/v1/follow_graph` — drawn differently: you in
/// the middle, everybody the walk found on rings around you, near ones being
/// the ones more of your follows follow. The list answers "who should I
/// follow"; this answers "who is around me", which is a different question and
/// the reason the web has both (docs/05 §7).
///
/// Laid out deterministically rather than with a physics simulation: the same
/// graph has to draw the same way twice, or dragging it becomes a way of
/// losing somebody you had just spotted.
public struct FollowConstellationView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let session: AccountSession
    private let suggestions: [FollowGraphSuggestion]
    private let onAction: (StatusRowAction) -> Void

    @State private var offset: CGSize = .zero
    @State private var dragging: CGSize = .zero
    @State private var selected: FollowGraphSuggestion?
    @State private var following: Set<String> = []

    public init(
        session: AccountSession,
        suggestions: [FollowGraphSuggestion],
        onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.session = session
        self.suggestions = suggestions
        self.onAction = onAction
    }

    /// At most this many stars. Beyond it the rings overlap into a smudge, and
    /// the ones left out are the ones fewest of your follows follow anyway.
    private static let maximumStars = 24

    private var stars: [FollowGraphSuggestion] {
        Array(suggestions.sorted { $0.count > $1.count }.prefix(Self.maximumStars))
    }

    public var body: some View {
        GeometryReader { proxy in
            let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) / 2 - 44

            ZStack {
                ForEach(Array(stars.enumerated()), id: \.element.id) { index, suggestion in
                    let position = place(
                        index: index, of: stars.count, centre: centre, radius: radius)

                    Path { path in
                        path.move(to: centre)
                        path.addLine(to: position)
                    }
                    .stroke(palette.separator, lineWidth: 1)

                    star(suggestion)
                        .position(position)
                }

                you.position(centre)
            }
            .offset(x: offset.width + dragging.width, y: offset.height + dragging.height)
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { dragging = $0.translation }
                    .onEnded { value in
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                        dragging = .zero
                    }
            )
        }
        .frame(height: 420)
        .clipped()
        .background(palette.surface, in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerLarge))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            Text(
                "^[\(stars.count) person](inflect: true) the people you follow also follow",
                comment: "Constellation accessibility label")
        )
        .overlay(alignment: .topTrailing) {
            if offset != .zero {
                Button {
                    withAnimation(reduceMotion ? nil : .snappy) { offset = .zero }
                } label: {
                    Image(systemName: "scope")
                        .padding(AlohaMetrics.space2)
                        .background(palette.surfaceRaised, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(AlohaMetrics.space3)
                .accessibilityLabel(Text("Centre again", comment: "Constellation action"))
            }
        }
        .sheet(item: $selected) { suggestion in
            starSheet(suggestion)
        }
    }

    // MARK: - Pieces

    private var you: some View {
        AvatarView(account: session.snapshot.asAccount, size: 56)
            .overlay { Circle().strokeBorder(palette.accent, lineWidth: 3) }
            .accessibilityLabel(Text("You", comment: "Constellation centre"))
    }

    private func star(_ suggestion: FollowGraphSuggestion) -> some View {
        Button {
            selected = suggestion
        } label: {
            VStack(spacing: 2) {
                AvatarView(account: suggestion.account, size: size(for: suggestion))
                    .overlay {
                        Circle().strokeBorder(
                            following.contains(suggestion.account.id)
                                ? palette.accent : palette.separator,
                            lineWidth: 2)
                    }
                Text(suggestion.account.bestDisplayName)
                    .font(AlohaType.micro)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(1)
                    .frame(maxWidth: 76)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(
                "\(suggestion.account.bestDisplayName), followed by ^[\(suggestion.count) person](inflect: true) you follow",
                comment: "Constellation star accessibility label"))
    }

    /// How many of your follows follow them, as size — the only encoding the
    /// drawing has for the number, and the reason the picture says anything the
    /// list does not.
    private func size(for suggestion: FollowGraphSuggestion) -> Double {
        let highest = max(1, stars.first?.count ?? 1)
        let share = Double(min(suggestion.count, highest)) / Double(highest)
        return 30 + share * 22
    }

    /// Golden-angle placement: evenly spread with no two on the same spoke,
    /// and the same for the same list every time.
    private func place(index: Int, of count: Int, centre: CGPoint, radius: Double) -> CGPoint {
        guard count > 0, radius > 0 else { return centre }
        let goldenAngle = Double.pi * (3 - 5.squareRoot())
        let angle = Double(index) * goldenAngle
        // Square root rather than linear, so the rings stay evenly dense.
        let distance = radius * (0.35 + 0.65 * (Double(index + 1) / Double(count)).squareRoot())
        return CGPoint(
            x: centre.x + cos(angle) * distance,
            y: centre.y + sin(angle) * distance)
    }

    private func starSheet(_ suggestion: FollowGraphSuggestion) -> some View {
        NavigationStack {
            List {
                Section {
                    AccountRow(
                        account: suggestion.account, localHost: session.snapshot.instanceHost)
                    if suggestion.count > 0 {
                        Text(
                            "^[\(suggestion.count) person](inflect: true) you follow follows them.",
                            comment: "Constellation star detail"
                        )
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryLabel)
                    }
                }

                if !suggestion.via.isEmpty {
                    Section {
                        ForEach(suggestion.via) { account in
                            AccountRow(account: account, localHost: session.snapshot.instanceHost)
                        }
                    } header: {
                        Text("Through", comment: "Constellation star section")
                    }
                }

                Section {
                    Button {
                        Task { await follow(suggestion) }
                    } label: {
                        if following.contains(suggestion.account.id) {
                            Text("Following", comment: "Follow button state")
                        } else {
                            Text("Follow", comment: "Follow button action")
                        }
                    }
                    .disabled(following.contains(suggestion.account.id))

                    Button {
                        selected = nil
                        onAction(.openProfile(suggestion.account))
                    } label: {
                        Text("Open profile", comment: "Constellation action")
                    }
                }
            }
            .navigationTitle(Text(suggestion.account.bestDisplayName))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .presentationDetents([.medium])
    }

    private func follow(_ suggestion: FollowGraphSuggestion) async {
        following.insert(suggestion.account.id)
        do {
            _ = try await session.client.send(
                Endpoint.accounts.follow(suggestion.account.id))
        } catch {
            following.remove(suggestion.account.id)
            await session.handle(error)
        }
    }
}
