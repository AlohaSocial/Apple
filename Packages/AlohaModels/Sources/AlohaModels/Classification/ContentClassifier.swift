// SPDX-License-Identifier: MIT

import Foundation

/// Decides what a status is, so the media modes can route it.
///
/// Shorts is the mode with no server-side support anywhere, so these rules are
/// part of the contract rather than an implementation detail (docs/06 §4).
/// The single place the rule lives; everything else asks this.
public enum ContentClassifier {
    /// A short is at most this long. Three minutes is generous on purpose —
    /// Loops-style clips are far shorter, and a 3-minute ceiling catches the
    /// vertical video that is a short in everything but duration.
    public static let maximumShortDuration: Double = 180
    /// Under this, duration alone is enough regardless of shape.
    public static let unconditionalShortDuration: Double = 60
    /// Portrait or square. Anything wider is a video, not a short.
    public static let maximumShortAspect: Double = 1.0

    public static let shortHashtags: Set<String> = ["loops", "short", "shorts", "reel", "reels"]

    public static func classify(_ status: Status) -> ContentKind {
        let status = status.displayed
        let attachments = status.mediaAttachments

        guard !attachments.isEmpty else {
            return status.card != nil ? .news : .text
        }

        if attachments.allSatisfy({ $0.type == .audio }) { return .audio }

        let videoLike = attachments.filter { $0.type == .video || $0.type == .gifv }

        if videoLike.count == 1, attachments.count == 1 {
            switch shortness(of: videoLike[0], in: status) {
            case .short: return .short
            case .notShort: return .video
            case .undetermined: return .undetermined
            }
        }

        if !videoLike.isEmpty { return .video }
        if attachments.allSatisfy({ $0.type == .image }) { return .photo }
        return .text
    }

    public enum Shortness: Sendable, Hashable {
        case short
        case notShort
        /// Neither duration nor dimensions were available. The caller stores
        /// `.undetermined` and reclassifies once a player reports real values;
        /// the result is persisted so it costs nothing twice.
        case undetermined
    }

    public static func shortness(of attachment: MediaAttachment, in status: Status) -> Shortness {
        let duration = attachment.duration
        let aspect = attachment.aspectRatio

        // A hashtag is the author saying what they made. It promotes a clip
        // whose shape says otherwise — but it is checked *after* the duration
        // ceiling, so it can never rescue something that is simply too long.
        let tagged = status.tags.contains { shortHashtags.contains($0.name.lowercased()) }

        if let duration, duration > maximumShortDuration { return .notShort }
        if tagged { return .short }
        if let duration, duration <= unconditionalShortDuration { return .short }

        switch (duration, aspect) {
        case (.some, .some(let aspect)):
            // Between the two duration ceilings, shape decides.
            return aspect <= maximumShortAspect ? .short : .notShort
        case (.some, .none):
            // Long enough to need the shape, and the server did not say.
            return .undetermined
        case (.none, .some(let aspect)):
            // Landscape is never a short whatever its length, so that much can
            // be settled; portrait still needs a duration.
            return aspect > maximumShortAspect ? .notShort : .undetermined
        case (.none, .none):
            return .undetermined
        }
    }

    /// Reclassification once a player has reported real values for an
    /// attachment the server described incompletely.
    public static func reclassify(
        _ status: Status, attachmentID: String, duration: Double, width: Int, height: Int
    ) -> ContentKind {
        var patched = status.displayed
        patched.mediaAttachments = patched.mediaAttachments.map { attachment in
            guard attachment.id == attachmentID else { return attachment }
            var copy = attachment
            var meta = copy.meta ?? MediaAttachment.Meta()
            var original = meta.original ?? MediaAttachment.Meta.Dimensions()
            original.duration = duration
            original.width = width
            original.height = height
            original.aspect = height > 0 ? Double(width) / Double(height) : nil
            meta.original = original
            copy.meta = meta
            return copy
        }
        return classify(patched)
    }

    /// The aspect ratio to lay out in before anything has loaded, so nothing
    /// shifts when the bytes arrive.
    public static func layoutAspect(for attachments: [MediaAttachment]) -> Double {
        guard let first = attachments.first else { return 4.0 / 3.0 }
        if attachments.count > 1 { return 1.0 }
        return first.displayAspectRatio
    }
}
