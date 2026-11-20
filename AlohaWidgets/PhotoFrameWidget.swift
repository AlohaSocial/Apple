// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaStore
import CoreGraphics
import SwiftUI
import WidgetKit

/// A full-bleed picture from Home, a hashtag, a person or a list, turning
/// over through the day. Pictures behind a content warning never appear.
struct PhotoFrameProvider: AppIntentTimelineProvider {
    /// How many pictures one timeline holds, an hour each: few enough for the
    /// extension's memory budget, many enough for an afternoon.
    static let entriesPerTimeline = 4

    func placeholder(in context: Context) -> PhotoFrameEntry {
        PhotoFrameEntry(date: Date(), accountID: nil, photo: nil, image: nil, state: .openApp)
    }

    func snapshot(
        for configuration: PhotoFrameConfiguration, in context: Context
    ) async -> PhotoFrameEntry {
        await entries(for: configuration, family: context.family, now: Date()).first
            ?? placeholder(in: context)
    }

    func timeline(
        for configuration: PhotoFrameConfiguration, in context: Context
    ) async -> Timeline<PhotoFrameEntry> {
        let entries = await entries(for: configuration, family: context.family, now: Date())
        return Timeline(entries: entries, policy: .atEnd)
    }

    @MainActor
    private func entries(
        for configuration: PhotoFrameConfiguration, family: WidgetFamily, now: Date
    ) async -> [PhotoFrameEntry] {
        guard let account = await WidgetData.account(id: configuration.account?.id) else {
            return [
                PhotoFrameEntry(date: now, accountID: nil, photo: nil, image: nil, state: .openApp)
            ]
        }
        guard let source = configuration.photoSource(for: account.id) else {
            return [
                PhotoFrameEntry(
                    date: now, accountID: account.id, photo: nil, image: nil, state: .chooseSource)
            ]
        }
        guard let loaded = await SnapshotData.load(accountID: account.id, photoSources: [source]),
            let set = loaded.snapshot?.photoSet(for: source)
        else {
            return [
                PhotoFrameEntry(
                    date: now, accountID: account.id, photo: nil, image: nil, state: .openApp)
            ]
        }
        guard !set.photos.isEmpty else {
            return [
                PhotoFrameEntry(
                    date: now, accountID: account.id, photo: nil, image: nil, state: .noPhotos)
            ]
        }

        // Starts where the hour of the day points, so two frames on one
        // Home Screen, or one reloaded, do not always open on the same picture.
        let hour = Calendar.current.component(.hour, from: now)
        let start = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        let count = min(Self.entriesPerTimeline, set.photos.count)
        return (0..<count).map { offset in
            let photo = set.photos[(hour + offset) % set.photos.count]
            return PhotoFrameEntry(
                date: offset == 0 ? now : start.addingTimeInterval(Double(offset) * 3600),
                accountID: account.id, photo: photo,
                image: SnapshotData.image(
                    photo.imageFile, in: loaded.store, maxPixels: Self.pixels(for: family)),
                state: .ready)
        }
    }

    /// The decode size for a family: the tile's long side at 3x, no larger
    /// than the app shrank it to.
    static func pixels(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall: 480
        default: 720
        }
    }
}

struct PhotoFrameEntry: WidgetKit.TimelineEntry {
    enum State {
        case ready, chooseSource, openApp, noPhotos
    }

    let date: Date
    let accountID: UUID?
    let photo: WidgetSnapshot.Photo?
    let image: CGImage?
    let state: State

    var url: URL? {
        guard let accountID, let photo else { return nil }
        return WidgetData.statusURL(accountID: accountID, statusID: photo.statusID)
    }
}

struct PhotoFrameWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "PhotoFrame", intent: PhotoFrameConfiguration.self,
            provider: PhotoFrameProvider()
        ) { entry in
            PhotoFrameView(entry: entry)
                .widgetURL(entry.url)
        }
        .configurationDisplayName(Text("Photo frame", comment: "Widget name"))
        .description(
            Text(
                "Photos from your timeline, a hashtag, a person or a list.",
                comment: "Widget description")
        )
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

struct PhotoFrameView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PhotoFrameEntry

    var body: some View {
        Group {
            if let image = entry.image, let photo = entry.photo {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)], startPoint: .center,
                        endPoint: .bottom)
                    Text(photo.author)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(family == .systemSmall ? 10 : 14)
                }
                .containerBackground(for: .widget) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .widgetAccentedRenderingMode(.fullColor)
                        .scaledToFill()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(photo))
            } else {
                SnapshotPlaceholder(symbol: AlohaSymbol.media, text: message)
                    .padding()
                    .containerBackground(.fill.tertiary, for: .widget)
            }
        }
    }

    private func accessibilityLabel(_ photo: WidgetSnapshot.Photo) -> Text {
        if let alt = photo.altText, !alt.isEmpty {
            return Text(
                "Photo by \(photo.author): \(alt)",
                comment: "Photo frame widget, for VoiceOver: author and description")
        }
        return Text("Photo by \(photo.author)", comment: "Photo frame widget, for VoiceOver")
    }

    private var message: Text {
        switch entry.state {
        case .chooseSource:
            Text(
                "Choose a hashtag, person or list in the widget's settings.",
                comment: "Photo frame without a complete source")
        case .noPhotos:
            Text("No photos here lately.", comment: "Photo frame whose source has none")
        case .openApp, .ready:
            SnapshotPlaceholder.openApp
        }
    }
}
