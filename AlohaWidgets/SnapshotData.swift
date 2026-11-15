// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaStore
import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import SwiftUI
import WidgetKit

/// One account's widget snapshot, as a provider reads it.
struct LoadedSnapshot {
    let account: AccountStore.Snapshot
    let snapshot: WidgetSnapshot?
    let store: WidgetSnapshotStore?

    var serverTheme: AlohaThemeModifier.ServerTheme? { WidgetData.serverTheme(of: account) }
}

/// Reads what `WidgetSnapshotWriter` wrote; a widget never downloads
/// (docs/09 §8).
enum SnapshotData {
    /// The account picked, or the active one, with its snapshot. Records the
    /// account as wanted, so the app keeps its snapshot fresh.
    @MainActor
    static func load(
        accountID: UUID?, people: [String] = [], photoSources: [WidgetPhotoSource] = []
    ) async -> LoadedSnapshot? {
        guard let account = await WidgetData.account(id: accountID) else { return nil }
        WidgetWants.record(accountID: account.id, people: people, photoSources: photoSources)
        let store = WidgetSnapshotStore.shared
        return LoadedSnapshot(
            account: account, snapshot: store?.read(accountID: account.id), store: store)
    }

    /// A picture the app already shrank, decoded no larger than the widget
    /// draws it.
    static func image(_ file: String?, in store: WidgetSnapshotStore?, maxPixels: Int) -> CGImage? {
        guard let url = store?.imageURL(file),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            ] as CFDictionary)
    }

    /// `alohasocial://<host>/<account>`: the screen, opened under the account
    /// the widget shows rather than whichever one the app has active.
    static func url(_ host: String, accountID: UUID?) -> URL? {
        var components = URLComponents()
        components.scheme = "alohasocial"
        components.host = host
        if let accountID { components.path = "/\(accountID.uuidString)" }
        return components.url
    }

    static func profileURL(accountID: UUID, personID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "alohasocial"
        components.host = "profile"
        components.path = "/\(accountID.uuidString)/\(personID)"
        return components.url
    }

    /// Drafts live in the shared store already; counting them needs no
    /// snapshot.
    @MainActor
    static func draftCount(accountID: UUID) -> Int {
        let descriptor = FetchDescriptor<DraftRecord>(
            predicate: #Predicate { $0.accountID == accountID })
        return (try? StoreContainer.reader().mainContext.fetchCount(descriptor)) ?? 0
    }

    /// The Lock Screen families for a count: circle, rectangle and line.
    /// They are the iPhone's; a Mac has none of them, and cannot even name them.
    static var lockScreenCountFamilies: [WidgetFamily] {
        #if os(iOS)
            [.accessoryCircular, .accessoryRectangular, .accessoryInline]
        #else
            []
        #endif
    }

    /// The Lock Screen families with room for words: rectangle and line.
    static var lockScreenTextFamilies: [WidgetFamily] {
        #if os(iOS)
            [.accessoryRectangular, .accessoryInline]
        #else
            []
        #endif
    }

    /// "Today" in the key the follower history uses.
    static func today(_ now: Date = Date()) -> String {
        MemoriesSnapshot.dayKey(for: now)
    }
}

/// What a widget says when the app has not written its part yet.
struct SnapshotPlaceholder: View {
    let symbol: String
    let text: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .widgetAccentable()
            text
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    static var openApp: Text {
        Text(
            "Open Aloha Social to fill this widget.",
            comment: "Widget whose data the app has not written yet")
    }
}

/// A small heading over a widget's content: an icon and a title, in the tint.
struct WidgetHeading: View {
    let symbol: String
    let title: Text
    var trailing: Text?

    var body: some View {
        HStack(spacing: 4) {
            Label {
                title
            } icon: {
                Image(systemName: symbol)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
            .lineLimit(1)
            .widgetAccentable()
            Spacer(minLength: 0)
            if let trailing {
                trailing
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
