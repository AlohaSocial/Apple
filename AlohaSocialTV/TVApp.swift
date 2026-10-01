// SPDX-License-Identifier: MIT

import AVKit
import AlohaDesign
import AlohaMedia
import AlohaModels
import AlohaNetwork
import AlohaStore
import CoreImage.CIFilterBuiltins
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
        .serverTint(model.serverTheme)
        .task { await model.restore() }
    }
}

/// `ASWebAuthenticationSession` does not exist on tvOS, so sign-in goes through
/// the out-of-band redirect the Social app's OAuth controller supports: the
/// authorise page opens on a phone from a QR code, and the code it shows comes
/// back here (docs/03 §7). That code is sixty mixed-case characters
/// (`ClientService::generateToken`), which nobody types with a remote — the
/// phone copies it and the iPhone's Apple TV keyboard pastes it.
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
                        "Scan this with your phone and sign in:",
                        comment: "tvOS out-of-band instruction")
                    if let url = model.pendingAuthorisationURL {
                        QRCodeView(text: url.absoluteString)
                            .frame(width: 320, height: 320)
                        Text(url.absoluteString)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .frame(maxWidth: 900)
                    }

                    Text(
                        "Copy the code it shows, select the field below, and paste it with the keyboard that appears on your iPhone:",
                        comment: "tvOS out-of-band instruction"
                    )
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                    TextField(
                        text: $code,
                        prompt: Text("Code", comment: "tvOS code field")
                    ) {
                        Text("Code", comment: "tvOS code field")
                    }
                    .autocorrectionDisabled()
                    .frame(maxWidth: 900)

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

/// The authorise URL as a QR code, drawn crisp at any size: Core Image makes
/// one module per pixel, and nearest-neighbour scaling keeps the edges hard
/// enough for a phone camera across a living room.
struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = Self.image(for: text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(16)
                .background(.white, in: .rect(cornerRadius: 12))
        }
    }

    private static func image(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
