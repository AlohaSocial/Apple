// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import PhotosUI
import SwiftUI

/// The attachments: the strip of pictures and videos with their
/// descriptions, and taking in what was picked, dropped or pasted.
extension ComposerView {
    var mediaStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AlohaMetrics.space2) {
                // Describing four pictures one sheet at a time is four round
                // trips through the same editor (docs/10 §5); one button does
                // the lot, sequentially, and says where it is.
                if model.imagesAwaitingDescription > 0,
                    environment.intelligence.availability.isAvailable
                {
                    if model.isDescribingAll {
                        VStack(spacing: AlohaMetrics.space2) {
                            ProgressView(value: progress)
                                .progressViewStyle(.linear)
                                .frame(width: 96)
                            Text(
                                "^[\(model.describedCount) of \(model.describeAllTotal)](inflect: false)",
                                comment: "Alt text batch progress"
                            )
                            .font(.caption2.monospacedDigit())
                            Button(role: .cancel) {
                                model.cancelDescribeAll()
                            } label: {
                                Text("Stop", comment: "Alt text batch cancel")
                                    .font(.caption2.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(palette.secondaryLabel)
                        }
                        .frame(width: 96, height: 96)
                        .background(
                            palette.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall)
                        )
                        .accessibilityLabel(
                            Text(
                                "Describing images: \(model.describedCount) of \(model.describeAllTotal) done",
                                comment: "Alt text batch progress"))
                    } else {
                        Button {
                            Task { await model.describeAllImages(environment: environment) }
                        } label: {
                            VStack(spacing: AlohaMetrics.space1) {
                                Image(systemName: "text.badge.star")
                                    .font(.title3)
                                Text("Describe all", comment: "Alt text batch action")
                                    .font(.caption2.weight(.semibold))
                                Text(
                                    "^[\(model.imagesAwaitingDescription) image](inflect: true)",
                                    comment: "Alt text batch count"
                                )
                                .font(.caption2.monospacedDigit())
                            }
                            .foregroundStyle(palette.accent)
                            .frame(width: 96, height: 96)
                            .background(
                                palette.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            Text(
                                "Describe all \(model.imagesAwaitingDescription) images",
                                comment: "Alt text batch action"))
                    }
                }

                ForEach(model.attachments) { attachment in
                    ZStack(alignment: .bottomTrailing) {
                        RemoteImage(url: attachment.displayImageURL)
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall))

                        Button {
                            model.isShowingAltTextFor = attachment
                        } label: {
                            Text("ALT", comment: "Composer alt text badge")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    attachment.hasAltText ? palette.accent : palette.destructive,
                                    in: Capsule()
                                )
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                        .accessibilityLabel(
                            attachment.hasAltText
                                ? Text("Edit description", comment: "Composer media action")
                                : Text("Add a description", comment: "Composer media action"))
                    }
                    .overlay(alignment: .topLeading) {
                        if model.focalPoints[attachment.id] != nil {
                            Image(systemName: "scope")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(.black.opacity(0.5), in: Circle())
                                .padding(4)
                                .accessibilityLabel(
                                    Text("Focal point set", comment: "Composer media badge"))
                        }
                    }
                    .contextMenu {
                        if !attachment.type.isPlayable {
                            Button {
                                focusingAttachment = attachment
                            } label: {
                                Label {
                                    Text("Set focal point", comment: "Composer media action")
                                } icon: {
                                    Image(systemName: "scope")
                                }
                            }
                        }
                        Button {
                            model.isShowingAltTextFor = attachment
                        } label: {
                            Label {
                                Text("Describe", comment: "Composer media action")
                            } icon: {
                                Image(systemName: AlohaSymbol.altBadge)
                            }
                        }
                        if model.uploader.canFilter(attachment.id) {
                            Button {
                                filteringAttachment = attachment
                            } label: {
                                Label {
                                    Text("Adjust", comment: "Composer media action")
                                } icon: {
                                    Image(systemName: "camera.filters")
                                }
                            }
                        }
                        Button(role: .destructive) {
                            model.removeAttachment(attachment.id)
                        } label: {
                            Label {
                                Text("Remove", comment: "Composer media action")
                            } icon: {
                                Image(systemName: AlohaSymbol.delete)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AlohaMetrics.space3)
        }
        .frame(height: 112)
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) {
            // A failure in the batch is reported in place — one bad image does
            // not undo the ones that succeeded, and it should not be surfaced
            // as a modal the person has to dismiss to see their remaining work.
            if let describeAllError = model.describeAllError, !model.isDescribingAll {
                Text(describeAllError)
                    .font(.caption2)
                    .foregroundStyle(palette.destructive)
                    .padding(.horizontal, AlohaMetrics.space3)
                    .padding(.vertical, AlohaMetrics.space1)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }

    /// The batch run's progress, for the strip's progress bar.
    private var progress: Double {
        guard model.describeAllTotal > 0 else { return 0 }
        return Double(model.describedCount) / Double(model.describeAllTotal)
    }

    /// Pictures from a drop or a paste go straight up; a video goes through
    /// the trim sheet, one at a time, the way a picked one does.
    func attach(_ items: [DroppedMedia]) async {
        var movie: URL?
        for item in items {
            switch item {
            case .image(let image):
                await model.uploader.add(
                    data: image.data, filename: image.filename, mimeType: image.mimeType)
            case .movie(let url):
                if movie == nil { movie = url }
            }
        }
        if let movie { trimmingVideoAt = movie }
    }

    func ingest(_ items: [PhotosPickerItem]) async {
        defer { pickedItems = [] }
        for item in items {
            let type = item.supportedContentTypes.first
            let mimeType = type?.preferredMIMEType ?? "image/jpeg"
            let ext = type?.preferredFilenameExtension ?? "jpg"

            // A video goes through the trim sheet first, so its length and
            // quality are settled before anything is uploaded.
            if mimeType.hasPrefix("video/"),
                let movie = try? await item.loadTransferable(type: PickedMovie.self)
            {
                trimmingVideoAt = movie.url
                continue
            }

            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            await model.uploader.add(
                data: data, filename: "upload-\(UUID().uuidString).\(ext)", mimeType: mimeType)
        }
    }
}

struct TrimRequest: Identifiable, Hashable {
    let url: URL
    var id: String { url.absoluteString }
}

/// `PhotosPickerItem` hands a movie over as a file rather than as `Data`, which
/// is what lets a long video be trimmed without being read into memory first.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = FileManager.default.temporaryDirectory
                .appending(path: "picked-\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedMovie(url: destination)
        }
    }
}
