// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import SwiftUI
import WatchConnectivity

/// A companion, not a client. It never authenticates on its own: the phone
/// hands it the active account's token and API base on pairing and on change,
/// and it keeps that in the watch's own Keychain with the same accessibility
/// class (docs/09 §4).
@main
struct AlohaSocialWatchApp: App {
    @State private var link = WatchLink()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(link)
        }
    }
}

struct WatchRootView: View {
    @Environment(WatchLink.self) private var link

    var body: some View {
        NavigationStack {
            Group {
                if link.credentials == nil {
                    ContentUnavailableView {
                        Text("Not paired yet", comment: "Watch, no credentials")
                    } description: {
                        Text(
                            "Open Aloha Social on your iPhone to finish setting this up.",
                            comment: "Watch, no credentials detail")
                    }
                } else {
                    WatchTimelineView()
                }
            }
            .navigationTitle(Text("Aloha", comment: "Watch app title"))
        }
        .task { link.activate() }
    }
}

struct WatchTimelineView: View {
    @Environment(WatchLink.self) private var link
    @State private var statuses: [Status] = []
    @State private var isLoading = true

    var body: some View {
        List {
            ForEach(statuses) { status in
                NavigationLink {
                    WatchStatusView(status: status)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.displayed.account.bestDisplayName)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                        Text(plain(status.displayed.content))
                            .font(.caption2)
                            .lineLimit(3)
                    }
                }
            }
            if statuses.isEmpty && !isLoading {
                Text("Nothing yet", comment: "Watch empty timeline").font(.caption2)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let client = link.client else { return }
        // Text and thumbnails only; no video on the wrist.
        statuses =
            (try? await client.decode(
                LossyArray<Status>.self,
                from: Endpoint.timelines.timeline(.home, limit: 20)))?.elements ?? []
    }

    private func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct WatchStatusView: View {
    @Environment(WatchLink.self) private var link
    let status: Status

    @State private var isFavourited = false
    @State private var isBoosted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(status.displayed.account.bestDisplayName)
                    .font(.caption.weight(.semibold))
                Text(plain(status.displayed.content))
                    .font(.caption2)

                HStack(spacing: 12) {
                    Button {
                        Task { await act("favourite") }
                        isFavourited = true
                    } label: {
                        Image(systemName: isFavourited ? "star.fill" : "star")
                    }
                    Button {
                        Task { await act("reblog") }
                        isBoosted = true
                    } label: {
                        Image(systemName: "arrow.2.squarepath")
                    }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func act(_ action: String) async {
        guard let client = link.client,
            let endpoint = Endpoint.StatusAction(rawValue: action)
        else { return }
        _ = try? await client.send(Endpoint.statuses.action(status.displayed.id, endpoint))
    }

    private func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
