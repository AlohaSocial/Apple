// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import ImageIO
import SwiftUI

/// Browsing the person's own Nextcloud Files to pick an attachment.
///
/// The file never travels to the device: the path goes to
/// `POST /api/v1/media/from-file` and the server copies the bytes itself. On a
/// 200 MB video over a mobile connection that is the difference between
/// possible and not (docs/07 §6).
public struct NextcloudFileBrowser: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let credentials: NextcloudLoginFlow.Credentials
    private let acceptedTypes: [String]
    private let onPick: (NextcloudFile) -> Void

    @State private var path = ""
    @State private var entries: [NextcloudFile] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var client: WebDAVClient { WebDAVClient(credentials: credentials) }

    public init(
        credentials: NextcloudLoginFlow.Credentials,
        acceptedTypes: [String],
        onPick: @escaping (NextcloudFile) -> Void
    ) {
        self.credentials = credentials
        self.acceptedTypes = acceptedTypes
        self.onPick = onPick
    }

    public var body: some View {
        NavigationStack {
            List {
                if !path.isEmpty { parentRow }

                ForEach(visibleEntries) { entry in
                    row(entry)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(palette.destructive)
                }

                if visibleEntries.isEmpty && !isLoading && errorMessage == nil {
                    ContentUnavailableView {
                        Text("Nothing to attach here", comment: "Empty Nextcloud folder")
                    } description: {
                        Text(
                            "This folder has no pictures, video or audio your server accepts.",
                            comment: "Empty Nextcloud folder detail")
                    }
                }
            }
            .listStyle(.plain)
            .overlay { if isLoading && entries.isEmpty { ProgressView() } }
            .navigationTitle(title)
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", comment: "Sheet action")
                    }
                }
            }
            .task(id: path) { await load() }
            .refreshable { await load() }
        }
    }

    private var title: String {
        path.isEmpty
            ? String(localized: "Your files", comment: "Nextcloud browser root title")
            : (path.split(separator: "/").last.map(String.init) ?? path)
    }

    /// Folders always, plus the files this server would actually accept —
    /// offering a `.docx` that the upload will refuse is a wasted tap.
    private var visibleEntries: [NextcloudFile] {
        entries
            .filter { $0.isDirectory || $0.isAttachable(acceptedTypes: acceptedTypes) }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private var parentRow: some View {
        Button {
            var components = path.split(separator: "/").map(String.init)
            components.removeLast()
            path = components.joined(separator: "/")
        } label: {
            Label {
                Text("Back", comment: "Nextcloud browser action")
            } icon: {
                Image(systemName: "chevron.left")
            }
        }
        .buttonStyle(.plain)
    }

    private func row(_ entry: NextcloudFile) -> some View {
        Button {
            if entry.isDirectory {
                path = entry.path
            } else {
                onPick(entry)
                dismiss()
            }
        } label: {
            HStack(spacing: AlohaMetrics.space3) {
                thumbnail(entry)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.subheadline).lineLimit(1)
                    if !entry.isDirectory {
                        HStack(spacing: AlohaMetrics.space1) {
                            Text(entry.size.formatted(.byteCount(style: .file)))
                            if let modified = entry.modifiedAt {
                                Text(verbatim: "·")
                                Text(modified, format: .relative(presentation: .named))
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(palette.secondaryLabel)
                    }
                }

                Spacer(minLength: 0)

                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(palette.tertiaryLabel)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func thumbnail(_ entry: NextcloudFile) -> some View {
        if entry.isDirectory {
            Image(systemName: "folder.fill")
                .font(.title3)
                .foregroundStyle(palette.accent)
                .frame(width: 40, height: 40)
        } else if let preview = client.previewURL(for: entry) {
            // Nextcloud's own preview endpoint, so showing a huge video costs
            // a few kilobytes.
            AuthenticatedImage(url: preview, authorization: client.authorizationHeader)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: symbol(for: entry))
                .font(.title3)
                .foregroundStyle(palette.secondaryLabel)
                .frame(width: 40, height: 40)
        }
    }

    private func symbol(for entry: NextcloudFile) -> String {
        guard let type = entry.contentType else { return "doc" }
        if type.hasPrefix("image/") { return "photo" }
        if type.hasPrefix("video/") { return "film" }
        if type.hasPrefix("audio/") { return "waveform" }
        return "doc"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            entries = try await client.list(path: path)
            errorMessage = nil
        } catch WebDAVClient.WebDAVError.unauthorised {
            errorMessage = String(
                localized: "Your Nextcloud connection has expired. Reconnect it in Settings.",
                comment: "WebDAV auth failure")
        } catch WebDAVClient.WebDAVError.notFound {
            errorMessage = String(
                localized: "That folder isn't there any more.", comment: "WebDAV 404")
        } catch {
            errorMessage = String(
                localized: "Couldn't read your files.", comment: "WebDAV failure")
        }
    }
}

/// A thumbnail that carries an `Authorization` header, which the shared image
/// loader deliberately does not — it is built for public media.
struct AuthenticatedImage: View {
    let url: URL
    let authorization: String

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        var request = URLRequest(url: url)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let decoded = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 120,
                ] as CFDictionary)
        else { return }

        image = decoded
    }
}
