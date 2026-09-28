// SPDX-License-Identifier: MIT

import AlohaMedia
import AlohaModels
import AlohaNetwork
import Foundation
import OSLog
import Observation

/// Uploads attachments for the composer, one pre-flight at a time.
@MainActor
@Observable
public final class ComposerUploader {
    public private(set) var attachments: [MediaAttachment] = []
    public private(set) var progress = UploadProgress()
    public private(set) var errorMessage: String?

    /// Which adjustment each picture is showing, by attachment id. The
    /// preview is a shader on the thumbnail; the bytes are only redrawn when
    /// the choice settles.
    public private(set) var filters: [String: PhotoFilter] = [:]

    private let session: AccountSession
    private let preparer = MediaPreparer()
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "upload")

    /// The picture as it was chosen, kept so a filter can be applied to the
    /// original rather than to an already-filtered copy — flicking from Vivid
    /// to Faded must not stack the two.
    ///
    /// On disk rather than in memory: ten pictures at this server's ceiling is
    /// a hundred megabytes, and a composer is not worth that.
    private var originals: [String: Original] = [:]

    private struct Original {
        var url: URL
        var filename: String
        var mimeType: String
    }

    public init(session: AccountSession) {
        self.session = session
    }

    private var limits: ServerLimits { session.capabilities.limits }

    public var canAddMore: Bool { attachments.count < limits.maxMediaAttachments }

    /// Concurrency cap of two, as docs/07 §4 prescribes — more than that on a
    /// phone connection makes every upload slower rather than the batch faster.
    public func add(data: Data, filename: String, mimeType: String) async {
        guard canAddMore else { return }

        var payload = data
        var type = mimeType
        var name = filename

        switch UploadPreflight.check(fileSize: data.count, mimeType: mimeType, limits: limits) {
        case .ready:
            break

        case .needsTranscode(_, let target) where target == "image/jpeg":
            guard let prepared = preparer.prepareImage(data, filename: filename) else {
                errorMessage = String(
                    localized: "That image couldn't be converted.", comment: "Upload failure")
                return
            }
            payload = prepared.data
            type = prepared.mimeType
            name = prepared.filename

        case .needsTranscode(_, let target):
            errorMessage = String(
                localized: "That file has to be \(target) for your server.",
                comment: "Upload needs a conversion this app cannot do")
            return

        case .tooLarge(let size, _, let isVideo) where !isVideo:
            // One attempt at bringing it under the ceiling before refusing.
            guard let prepared = preparer.prepareImage(data, filename: filename, quality: .high),
                prepared.data.count <= limits.imageSizeLimit
            else {
                errorMessage = UploadPreflight.explanation(
                    for: .tooLarge(size: size, limit: limits.imageSizeLimit, isVideo: false))
                return
            }
            payload = prepared.data
            type = prepared.mimeType
            name = prepared.filename

        case .tooLarge(let size, let limit, let isVideo):
            errorMessage = UploadPreflight.explanation(
                for: .tooLarge(size: size, limit: limit, isVideo: isVideo))
            return

        case .unsupported(let mimeType):
            errorMessage = UploadPreflight.explanation(for: .unsupported(mimeType: mimeType))
            return
        }

        let ticket = progress.begin(name)
        if UploadActivityController.isWorthShowing(
            totalBytes: payload.count, containsVideo: type.hasPrefix("video/"))
        {
            UploadActivityController.shared.start(fileCount: progress.items.count)
        }

        do {
            let attachment = try await upload(data: payload, filename: name, mimeType: type)
            attachments.append(attachment)
            rememberOriginal(payload, filename: name, mimeType: type, for: attachment.id)
            progress.finish(ticket)
            UploadActivityController.shared.update(progress)
            if progress.isFinished { UploadActivityController.shared.finish(failed: false) }
            errorMessage = nil
        } catch {
            progress.finish(ticket, failed: true)
            UploadActivityController.shared.finish(failed: true)
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "That upload didn't finish.", comment: "Upload failure")
        }
    }

    private func upload(
        data: Data, filename: String, mimeType: String
    ) async throws
        -> MediaAttachment
    {
        do {
            return try await session.client.decode(
                MediaAttachment.self,
                from: Endpoint.media.upload(
                    data: data, filename: filename, mimeType: mimeType,
                    description: nil, v2: true))
        } catch APIError.notFound {
            // Modern clients POST v2 and only fall back to v1 on a 404.
            return try await session.client.decode(
                MediaAttachment.self,
                from: Endpoint.media.upload(
                    data: data, filename: filename, mimeType: mimeType,
                    description: nil, v2: false))
        }
    }

    /// **Nextcloud extension.** A picture already on the Nextcloud never
    /// travels to the phone and back — on a 200 MB video over a mobile
    /// connection that is the difference between possible and not (docs/07 §6).
    public func addFromNextcloudFiles(path: String, description: String?) async {
        guard session.capabilities.mediaFromNextcloudFiles, canAddMore else { return }

        let ticket = progress.begin((path as NSString).lastPathComponent)
        do {
            let attachment = try await session.client.decode(
                MediaAttachment.self,
                from: Endpoint.media.fromNextcloudFile(path: path, description: description))
            attachments.append(attachment)
            progress.finish(ticket)
        } catch APIError.unprocessable(let message) {
            progress.finish(ticket, failed: true)
            // A traversal, a folder, or a missing file all arrive as a 422.
            errorMessage =
                message.isEmpty
                ? String(
                    localized: "That file isn't in your Nextcloud files.",
                    comment: "Nextcloud attach failure")
                : message
        } catch {
            progress.finish(ticket, failed: true)
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    public func updateDescription(_ description: String, for attachmentID: String) async {
        guard let index = attachments.firstIndex(where: { $0.id == attachmentID }) else { return }
        do {
            let updated = try await session.client.decode(
                MediaAttachment.self,
                from: Endpoint.media.updateDescription(attachmentID, description: description))
            attachments[index] = updated
        } catch {
            // Keep the local text even where the server refused it, so the
            // person does not lose what they typed.
            attachments[index].description = description
            await session.handle(error)
        }
    }

    public func remove(_ attachmentID: String) {
        attachments.removeAll { $0.id == attachmentID }
        forgetOriginal(attachmentID)
        filters[attachmentID] = nil
    }

    // MARK: - Adjustments

    /// Whether this attachment is a picture the filters can work on.
    public func canFilter(_ attachmentID: String) -> Bool {
        #if canImport(CoreImage) && canImport(ImageIO) && !os(watchOS)
            originals[attachmentID] != nil
        #else
            false
        #endif
    }

    public func filter(for attachmentID: String) -> PhotoFilter {
        filters[attachmentID] ?? .none
    }

    /// Bakes an adjustment in and puts the new picture in the old one's place.
    ///
    /// The filtered copy is a second upload, because the first one is already
    /// on the server — there is no route that replaces the bytes behind a
    /// media id. The old attachment is simply dropped: an unattached upload is
    /// swept by the server's own media job.
    public func applyFilter(_ filter: PhotoFilter, to attachmentID: String) async {
        #if canImport(CoreImage) && canImport(ImageIO) && !os(watchOS)
            guard
                let index = attachments.firstIndex(where: { $0.id == attachmentID }),
                let original = originals[attachmentID],
                let data = try? Data(contentsOf: original.url)
            else { return }

            let previous = filters[attachmentID] ?? .none
            filters[attachmentID] = filter
            guard filter != previous else { return }

            // "Original" needs no round trip when it is already what is up
            // there, and a redraw only happens for the rest.
            guard
                let rendered = PhotoFilterRenderer.apply(
                    filter, to: data, mimeType: original.mimeType)
            else {
                if filter == .none, previous != .none {
                    await replace(at: index, with: data, original: original, id: attachmentID)
                }
                return
            }

            let name =
                (original.filename as NSString).deletingPathExtension
                + "." + rendered.fileExtension
            let description = attachments[index].description

            do {
                var uploaded = try await upload(
                    data: rendered.data, filename: name, mimeType: rendered.mimeType)
                if let description, !description.isEmpty {
                    _ = try? await session.client.send(
                        Endpoint.media.updateDescription(uploaded.id, description: description))
                    uploaded.description = description
                }
                carryOriginal(from: attachmentID, to: uploaded.id, filter: filter)
                attachments[index] = uploaded
            } catch {
                filters[attachmentID] = previous
                await session.handle(error)
                errorMessage =
                    (error as? APIError)?.errorDescription
                    ?? String(localized: "That upload didn't finish.", comment: "Upload failure")
            }
        #endif
    }

    /// Puts the unfiltered picture back, which is its own upload for the same
    /// reason a filtered one is.
    private func replace(
        at index: Int, with data: Data, original: Original, id attachmentID: String
    ) async {
        let description = attachments[index].description
        do {
            var uploaded = try await upload(
                data: data, filename: original.filename, mimeType: original.mimeType)
            if let description, !description.isEmpty {
                _ = try? await session.client.send(
                    Endpoint.media.updateDescription(uploaded.id, description: description))
                uploaded.description = description
            }
            carryOriginal(from: attachmentID, to: uploaded.id, filter: .none)
            attachments[index] = uploaded
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func rememberOriginal(
        _ data: Data, filename: String, mimeType: String, for attachmentID: String
    ) {
        guard mimeType.hasPrefix("image/") else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aloha-original-\(UUID().uuidString)")
        do {
            try data.write(to: url, options: .atomic)
            originals[attachmentID] = Original(
                url: url, filename: filename, mimeType: mimeType)
        } catch {
            // Without the original there are no filters for this picture, which
            // is a missing row in a toolbar rather than a failed upload.
            logger.debug("could not keep the original for filtering")
        }
    }

    private func carryOriginal(from old: String, to new: String, filter: PhotoFilter) {
        guard old != new else {
            filters[new] = filter
            return
        }
        originals[new] = originals[old]
        originals[old] = nil
        filters[old] = nil
        filters[new] = filter
    }

    private func forgetOriginal(_ attachmentID: String) {
        guard let original = originals.removeValue(forKey: attachmentID) else { return }
        try? FileManager.default.removeItem(at: original.url)
    }

    /// Adds an already-prepared file — what the trim sheet and the camera hand
    /// back, having done their own size check.
    public func add(prepared: MediaPreparer.Prepared) async {
        await add(
            data: prepared.data, filename: prepared.filename, mimeType: prepared.mimeType)
    }

    public func reset() {
        for id in originals.keys { forgetOriginal(id) }
        attachments = []
        filters = [:]
        progress.reset()
        errorMessage = nil
    }

    public func restore(_ attachments: [MediaAttachment]) {
        self.attachments = attachments
    }
}
