// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import Charts
import SwiftUI

/// About this server: what it says about itself, how busy it has been, who it
/// federates with, and which servers it refuses.
///
/// Mastodon's three "about" routes, which Nextcloud Social serves and nothing
/// in the app read: `/instance/activity`, `/instance/peers` and
/// `/instance/domain_blocks`. All three are public — they say what the server
/// does, not who its people are — and all three can legitimately answer with
/// nothing, so each section hides itself rather than showing a broken row
/// (docs/05 §9).
public struct ServerInfoView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession

    @State private var activity: [InstanceActivityWeek] = []
    @State private var peers: [String] = []
    @State private var blocks: [PublicDomainBlock] = []
    @State private var rules: [InstanceDescription.Rule] = []
    @State private var peerFilter = ""
    @State private var isLoading = true

    public init(session: AccountSession) {
        self.session = session
    }

    private var filteredPeers: [String] {
        let needle = peerFilter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return peers }
        return peers.filter { $0.contains(needle) }
    }

    public var body: some View {
        List {
            Section {
                LabeledContent {
                    Text(verbatim: session.snapshot.instanceHost)
                } label: {
                    Text("Server", comment: "Server info field")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    Text(
                        "Server: \(Self.spoken(session.snapshot.instanceHost))",
                        comment: "Spoken form of the server's hostname"))
                if !peers.isEmpty {
                    LabeledContent {
                        Text(peers.count, format: .number)
                    } label: {
                        Text("Servers it has heard of", comment: "Server info field")
                    }
                }
            }

            if activity.contains(where: { $0.statuses > 0 }) {
                Section {
                    Chart {
                        ForEach(activity.sorted { $0.week < $1.week }) { week in
                            BarMark(
                                x: .value(
                                    String(localized: "Week", comment: "Chart axis"), week.date,
                                    unit: .weekOfYear),
                                y: .value(
                                    String(localized: "Posts", comment: "Chart axis"), week.statuses
                                )
                            )
                            .foregroundStyle(palette.accent)
                        }
                    }
                    .frame(height: 160)
                    .listRowBackground(palette.background)
                } header: {
                    Text("Posts a week", comment: "Server info section")
                } footer: {
                    Text(
                        "Sign-ins and new accounts are not counted: an account here is a Nextcloud user, so there is no registration for the server to count.",
                        comment: "Server info activity explanation")
                }
            }

            if !rules.isEmpty {
                Section {
                    ForEach(rules) { rule in
                        Text(rule.text)
                    }
                } header: {
                    Text("Rules", comment: "Server info section")
                }
            }

            if !blocks.isEmpty {
                Section {
                    ForEach(blocks) { block in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: block.domain)
                            if !block.comment.isEmpty {
                                Text(block.comment)
                                    .font(AlohaType.meta)
                                    .foregroundStyle(palette.secondaryLabel)
                            }
                        }
                        // Labelled on the row: a row combines its children for
                        // VoiceOver, and a label on an inner `Text` is
                        // discarded when it does.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            Text(verbatim: "\(Self.spoken(block.domain)) \(block.comment)"))
                    }
                } header: {
                    Text("Servers it refuses", comment: "Server info section")
                } footer: {
                    Text(
                        "Published by the administrators of this server. A server that publishes none shows nothing here, which is not the same as refusing none.",
                        comment: "Server info blocks explanation")
                }
            }

            if !peers.isEmpty {
                Section {
                    TextField(
                        text: $peerFilter,
                        prompt: Text("Filter", comment: "Server info peer filter")
                    ) {
                        Text("Filter", comment: "Server info peer filter")
                    }
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                    ForEach(filteredPeers.prefix(200), id: \.self) { peer in
                        Text(verbatim: peer)
                            .accessibilityLabel(Self.spoken(peer))
                    }
                    if filteredPeers.count > 200 {
                        Text(
                            "^[\(filteredPeers.count - 200) more](inflect: true). Filter to narrow the list.",
                            comment: "Server info peers truncated"
                        )
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryLabel)
                    }
                } header: {
                    Text("Who it federates with", comment: "Server info section")
                }
            }
        }
        .navigationTitle(Text("About this server", comment: "Screen title"))
        .overlay {
            if isLoading && peers.isEmpty && activity.isEmpty { ProgressView() }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    /// A hostname a screen reader can say.
    ///
    /// `spam.example` is one unpronounceable token to VoiceOver, and the
    /// accessibility audit is right to call it unreadable — this is a list of
    /// nothing but hostnames, so every row would be. The dots are spoken; the
    /// text on screen is untouched.
    static func spoken(_ host: String) -> String {
        host.replacingOccurrences(of: ".", with: " dot ")
    }

    private func load() async {
        defer { isLoading = false }
        // Each is separately optional: a server may publish its activity and
        // not its peers, or neither, and one absence must not empty the page.
        async let activityTask = try? await session.client.decode(
            LossyArray<InstanceActivityWeek>.self, from: Endpoint.instance.activity)
        async let peersTask = try? await session.client.decode(
            LossyArray<String>.self, from: Endpoint.instance.peers)
        async let blocksTask = try? await session.client.decode(
            LossyArray<PublicDomainBlock>.self, from: Endpoint.instance.domainBlocks)
        async let rulesTask = try? await session.client.decode(
            LossyArray<InstanceDescription.Rule>.self, from: Endpoint.instance.rules)

        activity = (await activityTask)?.elements ?? []
        peers = ((await peersTask)?.elements ?? []).sorted()
        blocks = (await blocksTask)?.elements ?? []
        rules = (await rulesTask)?.elements ?? []
    }
}
