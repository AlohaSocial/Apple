// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// What a post shared as an image may show.
///
/// A content warning hides the words, the picture and the poll, as it does in
/// the timeline; a sensitive picture stays covered unless the reading policy
/// shows everything. Either is lifted only by the reader having looked behind
/// it — in the timeline (`RevealedContent`) or in the share sheet itself. A
/// card is a copy that leaves the app: it must never be the way somebody
/// sees, or spreads, what a warning was put there to hold back.
struct PostImageDisclosure: Equatable {
    var showsBody: Bool
    var showsMedia: Bool

    static func decide(
        for status: Status, policy: SensitiveMediaPolicy,
        spoilerRevealed: Bool, mediaRevealed: Bool
    ) -> PostImageDisclosure {
        let post = status.displayed
        let showsBody = !post.hasContentWarning || spoilerRevealed
        let mediaCovered = post.sensitive && policy != .showAll && !mediaRevealed
        return PostImageDisclosure(showsBody: showsBody, showsMedia: showsBody && !mediaCovered)
    }

    /// Whether anything is being held back, which is when the share sheet
    /// offers to show it.
    func hidesSomething(in status: Status) -> Bool {
        let post = status.displayed
        return (post.hasContentWarning && !showsBody)
            || (!showsMedia && post.mediaAttachments.contains { $0.type == .image })
    }
}

/// A poll's options with their share of the votes, as the card draws them.
struct PollResultsSummary: Equatable {
    struct Row: Equatable {
        var title: String
        /// 0…1, or nil where the server hides the totals.
        var share: Double?
        var isLeading: Bool
    }

    var rows: [Row]
    var votes: Int

    init(_ poll: Poll) {
        let counts = poll.options.map { $0.votesCount }
        let total = counts.compactMap { $0 }.reduce(0, +)
        let leading = counts.compactMap { $0 }.max() ?? 0
        rows = poll.options.map { option in
            let share = option.votesCount.map { total > 0 ? Double($0) / Double(total) : 0 }
            return Row(
                title: option.title, share: share,
                isLeading: total > 0 && option.votesCount == leading)
        }
        votes = poll.votersCount ?? poll.votesCount
    }
}

/// The post as a picture: who wrote it, what they wrote, its first picture
/// or its poll, and a code that opens it — framed in the colour of the
/// server it lives on.
///
/// Drawn once by `ImageRenderer`, never on screen as a live view, so it takes
/// everything already decided and loaded: the words as plain text, the
/// pictures as bitmaps, the code as a bitmap. It is drawn light, at one text
/// size, whatever the reader's settings, because it is a picture for other
/// people and their screens.
struct PostImageCard: View {
    let authorName: String
    let handle: String
    let avatar: CGImage?
    let spoiler: String?
    let text: String
    let picture: CGImage?
    let pictureAspect: Double
    let hiddenNotice: String?
    let poll: PollResultsSummary?
    let date: Date
    let host: String
    let accent: Color
    let code: CGImage?

    /// Points; rendered at 3×, a 1080-pixel-wide image — the width the
    /// common photo apps and stories take without scaling.
    static let width: CGFloat = 360

    /// What is left for the words and the picture inside the frame and the
    /// card's own margins (14 and 20 a side).
    static let contentWidth: CGFloat = width - 68

    private let ink = Color(red: 0.11, green: 0.11, blue: 0.12)
    private let quiet = Color(red: 0.38, green: 0.38, blue: 0.40)
    private let paper = Color(red: 0.995, green: 0.99, blue: 0.98)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let spoiler {
                Label {
                    Text(verbatim: spoiler)
                } icon: {
                    Image(systemName: AlohaSymbol.warning)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ink)
            }
            if let hiddenNotice {
                Text(verbatim: hiddenNotice)
                    .font(.subheadline)
                    .italic()
                    .foregroundStyle(quiet)
            }
            if !text.isEmpty {
                Text(verbatim: text)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(3)
                    .foregroundStyle(ink)
                    .lineLimit(16)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let picture {
                Image(decorative: picture, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: Self.contentWidth,
                        height: min(Self.contentWidth / max(pictureAspect, 0.5), 360)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if let poll { pollView(poll) }
            footer
        }
        .padding(20)
        .background(paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(14)
        .frame(width: Self.width)
        .background(
            LinearGradient(
                colors: [accent, accent.opacity(0.75)], startPoint: .topLeading,
                endPoint: .bottomTrailing)
        )
        .environment(\.colorScheme, .light)
        // One size for everybody who will look at the picture, not the
        // sharer's own Dynamic Type setting.
        .dynamicTypeSize(.large)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Group {
                if let avatar {
                    Image(decorative: avatar, scale: 1).resizable().scaledToFill()
                } else {
                    accent.opacity(0.35)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: authorName)
                    .font(.headline)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                Text(verbatim: handle)
                    .font(.footnote)
                    .foregroundStyle(quiet)
                    .lineLimit(1)
            }
        }
    }

    private func pollView(_ poll: PollResultsSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(poll.rows.enumerated()), id: \.offset) { _, row in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(accent.opacity(row.isLeading ? 0.35 : 0.16))
                        .scaleEffect(x: row.share ?? 0, y: 1, anchor: .leading)
                    HStack {
                        Text(verbatim: row.title)
                            .font(.subheadline.weight(row.isLeading ? .semibold : .regular))
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        if let share = row.share {
                            Text(share, format: .percent.precision(.fractionLength(0)))
                                .font(.subheadline.monospacedDigit().weight(.medium))
                        }
                    }
                    .foregroundStyle(ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(quiet.opacity(0.25))
                )
            }
            Text("^[\(poll.votes) vote](inflect: true)", comment: "Shared post image: poll total")
                .font(.caption)
                .foregroundStyle(quiet)
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption)
                    .foregroundStyle(quiet)
                // Ink, not the accent: in dark mode the app's accent is the
                // server colour lightened for a dark ground, and the card is
                // always paper.
                Text(verbatim: host)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ink)
                Text("Aloha Social", comment: "Shared post image: app name in the footer")
                    .font(.caption2)
                    .foregroundStyle(quiet)
            }
            Spacer(minLength: 0)
            if let code {
                Image(decorative: code, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .padding(4)
                    .background(.white, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.top, 2)
    }
}

/// A QR code for a link, drawn by Core Image.
enum PostQRCode {
    /// Black on white, each module a whole number of pixels, so it scans
    /// from a screen and from print alike.
    nonisolated static func image(for url: URL, side: Int = 192) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        // M: about 15 % of the code can be lost, which a photographed
        // screen needs, without the code growing dense.
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
        let scale = max(1, (CGFloat(side) / output.extent.width).rounded(.down))
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext(options: [.useSoftwareRenderer: false])
            .createCGImage(scaled, from: scaled.extent)
    }
}

/// The rendered card, handed to the share sheet as a PNG file.
nonisolated struct PostImageFile: Transferable {
    let png: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName { $0.name }
    }

    /// PNG bytes for a bitmap, through ImageIO, which every platform has.
    nonisolated static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
