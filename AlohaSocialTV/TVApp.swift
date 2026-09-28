// SPDX-License-Identifier: MIT

import AVKit
import AlohaMedia
import AlohaModels
import AlohaNetwork
import AlohaStore
import SwiftUI

/// Video only: Video mode and Shorts mode, nothing else (docs/09 §5).
@main
struct AlohaSocialTVApp: App {
    @State private var model = TVModel()

    var body: some Scene {
        WindowGroup {
            TVRootView()
                .environment(model)
        }
    }
}

struct TVRootView: View {
    @Environment(TVModel.self) private var model

    var body: some View {
        Group {
            if model.client == nil {
                TVSignInView()
            } else {
                TabView {
                    Tab {
                        TVBrowseView()
                    } label: {
                        Label {
                            Text("Video", comment: "tvOS tab")
                        } icon: {
                            Image(systemName: "play.rectangle")
                        }
                    }
                    Tab {
                        TVShortsView()
                    } label: {
                        Label {
                            Text("Shorts", comment: "tvOS tab")
                        } icon: {
                            Image(systemName: "play.square.stack")
                        }
                    }
                }
            }
        }
        .task { await model.restore() }
    }
}

/// `ASWebAuthenticationSession` does not exist on tvOS, so sign-in goes through
/// the out-of-band redirect Nextcloud Social's OAuth controller supports: a code
/// shown on a phone and typed here, six characters, once (docs/03 §7).
struct TVSignInView: View {
    @Environment(TVModel.self) private var model

    @State private var host = ""
    @State private var code = ""

    var body: some View {
        VStack(spacing: 32) {
            Text("Sign in to Aloha Social", comment: "tvOS sign-in title")
                .font(.largeTitle.weight(.bold))

            if model.pendingAuthorisationURL == nil {
                TextField(
                    text: $host,
                    prompt: Text(verbatim: "cloud.example.com")
                ) {
                    Text("Your server", comment: "tvOS sign-in field")
                }
                .frame(maxWidth: 600)

                Button {
                    Task { await model.beginSignIn(host: host) }
                } label: {
                    Text("Continue", comment: "tvOS sign-in action")
                }
                .disabled(host.isEmpty)
            } else {
                VStack(spacing: 16) {
                    Text(
                        "On your phone, open this address and sign in:",
                        comment: "tvOS out-of-band instruction")
                    Text(model.pendingAuthorisationURL?.absoluteString ?? "")
                        .font(.footnote.monospaced())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 900)

                    Text(
                        "Then type the code it gives you:", comment: "tvOS out-of-band instruction")
                    TextField(
                        text: $code,
                        prompt: Text("Code", comment: "tvOS code field")
                    ) {
                        Text("Code", comment: "tvOS code field")
                    }
                    .frame(maxWidth: 400)

                    Button {
                        Task { await model.finishSignIn(code: code) }
                    } label: {
                        Text("Sign in", comment: "tvOS sign-in action")
                    }
                    .disabled(code.isEmpty)
                }
            }

            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
        }
        .padding(80)
    }
}

/// Focus-driven shelves, with a preview that starts muted after a moment.
struct TVBrowseView: View {
    @Environment(TVModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                if !model.continueWatching.isEmpty {
                    shelf(
                        title: String(localized: "Continue watching", comment: "tvOS shelf"),
                        statuses: model.continueWatching.compactMap(\.status))
                }
                shelf(
                    title: String(localized: "Following", comment: "tvOS shelf"),
                    statuses: model.home)
                shelf(
                    title: String(localized: "Everywhere", comment: "tvOS shelf"),
                    statuses: model.federated)
            }
            .padding(60)
        }
        .task { await model.loadVideo() }
    }

    private func shelf(title: String, statuses: [Status]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.weight(.semibold))
            ScrollView(.horizontal) {
                LazyHStack(spacing: 32) {
                    ForEach(statuses) { status in
                        NavigationLink {
                            TVPlayerView(status: status)
                        } label: {
                            TVCard(status: status)
                        }
                        .buttonStyle(.card)
                    }
                }
            }
        }
    }
}

struct TVCard: View {
    let status: Status

    var body: some View {
        let attachment = status.displayed.mediaAttachments.first
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: attachment?.previewURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 420, height: 236)
            .clipped()

            Text(status.displayed.account.bestDisplayName)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 420, alignment: .leading)
        }
    }
}

struct TVPlayerView: View {
    @Environment(TVModel.self) private var model
    let status: Status

    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .task { await prepare() }
            .onDisappear { player?.pause() }
    }

    private func prepare() async {
        guard let attachment = status.displayed.mediaAttachments.first,
            let base = model.apiBase
        else { return }

        // The same three-step ladder the phone uses, and the same rule: never
        // point the player at a federated video's origin host.
        let sources = VideoSourceResolver.sources(
            for: attachment, statusID: status.displayed.id, apiBase: base,
            isRemote: VideoSourceResolver.isRemote(attachment))
        guard let first = sources.first else { return }

        let created = AVPlayer(url: first.url)
        player = created
        created.play()
    }
}

struct TVShortsView: View {
    @Environment(TVModel.self) private var model
    @State private var index = 0

    var body: some View {
        Group {
            if model.shorts.isEmpty {
                ContentUnavailableView {
                    Text("No shorts yet", comment: "tvOS empty shorts")
                } description: {
                    Text("Short vertical clips appear here.", comment: "tvOS empty shorts detail")
                }
            } else {
                TabView(selection: $index) {
                    ForEach(Array(model.shorts.enumerated()), id: \.element.id) { offset, status in
                        TVPlayerView(status: status).tag(offset)
                    }
                }
                .tabViewStyle(.page)
            }
        }
        .task { await model.loadShorts() }
    }
}
