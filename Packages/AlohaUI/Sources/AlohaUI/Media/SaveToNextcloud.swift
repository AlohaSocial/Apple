// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// "Save to Nextcloud" from the media viewer: the attachment's original file,
/// byte for byte, into `Aloha Social/Saved/` in the account's own Files
/// (docs/14 §7).
///
/// The original, not what is on screen: the viewer may be showing a preview
/// or a stream, and a re-encoded copy is a worse picture than the one that was
/// posted. The file is fetched to a temporary file and streamed up from there,
/// so a long video is never held in memory.
@MainActor
@Observable
final class SaveToNextcloud {
    static let folder = "Aloha Social/Saved"

    enum Phase: Equatable {
        case idle
        /// Fetching the original, then sending it: one bar, the first half
        /// for the fetch and the second for the upload.
        case working(Double)
        /// The name it was saved under, which may differ from the original's
        /// when that was taken.
        case saved(String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    @ObservationIgnored private var task: Task<Void, Never>?

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    func save(
        _ attachment: MediaAttachment, session: AccountSession, environment: AppEnvironment
    ) {
        guard !isWorking, let source = attachment.url ?? attachment.remoteURL else { return }
        guard
            let credentials = (try? environment.credentials.nextcloudCredentials(for: session.id))
                ?? nil
        else {
            phase = .failed(Self.reconnectMessage)
            return
        }
        phase = .working(0)
        let transport = environment.transport
        task = Task { [weak self] in
            let headers = await session.client.mediaRequestHeaders(for: source)
            let outcome: Phase
            do {
                let name = try await Self.transfer(
                    source, headers: headers, credentials: credentials, transport: transport
                ) { fraction in
                    Task { @MainActor in self?.progressed(fraction) }
                }
                outcome = .saved(name)
            } catch is CancellationError {
                outcome = .idle
            } catch APIError.cancelled {
                outcome = .idle
            } catch WebDAVClient.WebDAVError.unauthorised {
                outcome = .failed(Self.reconnectMessage)
            } catch {
                outcome = .failed(
                    String(
                        localized: "Couldn't save to your Nextcloud. Please try again.",
                        comment: "Save to Nextcloud failure"))
            }
            self?.phase = outcome
        }
    }

    /// A late report must not move a finished save back to working.
    private func progressed(_ fraction: Double) {
        guard case .working = phase else { return }
        phase = .working(fraction)
    }

    func dismiss() {
        guard !isWorking else { return }
        phase = .idle
    }

    func cancel() {
        task?.cancel()
    }

    private static var reconnectMessage: String {
        String(
            localized: "Your Nextcloud connection has expired. Reconnect it in Settings.",
            comment: "WebDAV auth failure")
    }

    /// Fetch, then upload. Answers the name the file was saved under.
    nonisolated private static func transfer(
        _ source: URL, headers: [String: String],
        credentials: NextcloudLoginFlow.Credentials, transport: any HTTPTransport,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        var request = URLRequest(url: source)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        let (file, response) = try await transport.download(request) { progress($0 / 2) }
        defer { try? FileManager.default.removeItem(at: file) }
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.server(status: response.statusCode, body: nil)
        }

        let contentType = response.mimeType ?? "application/octet-stream"
        let name = fileName(for: source, contentType: contentType)
        let client = WebDAVClient(credentials: credentials, transport: transport)
        let saved = try await client.saveNew(
            file: file, inFolder: folder, preferredName: name, contentType: contentType
        ) { progress(0.5 + $0 / 2) }
        return (saved as NSString).lastPathComponent
    }

    /// The name the server gave the file, with the extension its type calls
    /// for when the URL has none.
    nonisolated static func fileName(for source: URL, contentType: String) -> String {
        let last = source.lastPathComponent
        let base = last.isEmpty || last == "/" ? "media" : last
        guard (base as NSString).pathExtension.isEmpty,
            let ext = UTType(mimeType: contentType)?.preferredFilenameExtension
        else { return base }
        return "\(base).\(ext)"
    }
}

/// The bar at the foot of the media viewer while a save goes, and the word
/// that it is done — or why it is not.
struct SaveToNextcloudStatus: View {
    let saver: SaveToNextcloud

    var body: some View {
        HStack(spacing: AlohaMetrics.space2) {
            switch saver.phase {
            case .idle:
                EmptyView()
            case .working(let fraction):
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .tint(.white)
                Text("Saving to Nextcloud…", comment: "Save to Nextcloud in progress")
                Button {
                    saver.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Stop saving", comment: "Save to Nextcloud cancel"))
            case .saved(let name):
                Image(systemName: "checkmark.circle.fill")
                Text(
                    "Saved to \(SaveToNextcloud.folder) as \(name)",
                    comment:
                        "Save to Nextcloud success. The arguments are the folder and the file name."
                )
                .lineLimit(2)
            case .failed(let message):
                Image(systemName: AlohaSymbol.warning)
                Text(message).lineLimit(3)
                Button {
                    saver.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Dismiss", comment: "Save to Nextcloud dismiss"))
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.vertical, AlohaMetrics.space2)
        .alohaGlassEffect(MediaViewer.controlGlass, in: Capsule())
        .padding(.horizontal, AlohaMetrics.space4)
        .accessibilityElement(children: .combine)
        .task(id: saver.phase) {
            switch saver.phase {
            case .saved(let name):
                AccessibilityNotification.Announcement(
                    String(
                        localized: "Saved to \(SaveToNextcloud.folder) as \(name)",
                        comment:
                            "Save to Nextcloud success. The arguments are the folder and the file name."
                    )
                ).post()
                // Long enough to read, then out of the way of the picture.
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { saver.dismiss() }
            case .failed(let message):
                AccessibilityNotification.Announcement(message).post()
            default:
                break
            }
        }
    }
}
