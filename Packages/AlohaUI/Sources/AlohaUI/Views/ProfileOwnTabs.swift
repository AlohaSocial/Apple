// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// The tab a profile opens on.
///
/// Saved, Drafts and Statistics are tabs of your own profile, as they are on
/// the web (`useProfileKinds`). The routes that used to open screens of their
/// own — `.bookmarks`, `.favourites`, `.drafts`, `.scheduledPosts`,
/// `.heldPosts`, `.archived`, `.statistics` — open your profile on the
/// matching tab instead, so every link, shortcut, Handoff and widget that
/// named one still lands where it did.
struct ProfileStart: Hashable, Sendable {
    var tab: ProfileView.Tab
    var saved: ProfileView.SavedKind = .favorites

    static let posts = ProfileStart(tab: .posts)

    /// The own-profile tab a route now opens, or nil for a route that has a
    /// screen of its own.
    static func ownTab(for route: Route) -> ProfileStart? {
        switch route {
        case .favourites: ProfileStart(tab: .saved, saved: .favorites)
        case .bookmarks: ProfileStart(tab: .saved, saved: .bookmarks)
        case .drafts, .scheduledPosts, .heldPosts, .archived: ProfileStart(tab: .drafts)
        case .statistics: ProfileStart(tab: .statistics)
        default: nil
        }
    }
}

extension ProfileView {
    /// The sections of the Drafts tab.
    enum DraftSection: Hashable, Sendable {
        case drafts, scheduled, waitingForReview, archived
    }

    /// The tabs a profile shows, in Nextcloud Social's order: the public ones
    /// first, then — on the reader's own profile only — Saved, Drafts and
    /// Statistics. What a server cannot serve is left out, as before:
    /// Tagged, Statistics, held and archived posts are Nextcloud Social's.
    static func tabs(isOwn: Bool, capabilities: ServerCapabilities) -> [Tab] {
        var tabs: [Tab] = [.posts, .photos, .videos]
        if capabilities.isNextcloudSocial { tabs.append(.tagged) }
        if capabilities.collections { tabs.append(.collections) }
        if isOwn {
            tabs += [.saved, .drafts]
            if capabilities.isNextcloudSocial { tabs.append(.statistics) }
        }
        return tabs
    }

    /// The sections of the Drafts tab, as on the web.
    static func draftSections(capabilities: ServerCapabilities) -> [DraftSection] {
        capabilities.isNextcloudSocial
            ? [.drafts, .scheduled, .waitingForReview, .archived] : [.drafts, .scheduled]
    }
}

/// The Drafts tab of your own profile: what you have not sent yet, what waits
/// for its time, what waits for a moderator, and what you took off your
/// profile. Each section draws inside the profile's own scroll view.
struct ProfileDraftsTab: View {
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession
    let onAction: (StatusRowAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space5) {
            ForEach(ProfileView.draftSections(capabilities: session.capabilities), id: \.self) {
                section in
                VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                    title(section)
                        .font(.headline)
                        .foregroundStyle(palette.label)
                        .accessibilityAddTraits(.isHeader)
                    content(section)
                }
            }
        }
        .padding(.horizontal, AlohaMetrics.space4)
        .padding(.vertical, AlohaMetrics.space3)
    }

    private func title(_ section: ProfileView.DraftSection) -> Text {
        switch section {
        case .drafts: Text("Drafts", comment: "Profile drafts tab section")
        case .scheduled: Text("Scheduled posts", comment: "Profile drafts tab section")
        case .waitingForReview: Text("Waiting for review", comment: "Profile drafts tab section")
        case .archived: Text("Archived posts", comment: "Profile drafts tab section")
        }
    }

    @ViewBuilder
    private func content(_ section: ProfileView.DraftSection) -> some View {
        switch section {
        case .drafts: DraftsView(session: session)
        case .scheduled: ScheduledPostsView(session: session)
        case .waitingForReview: HeldPostsView(session: session)
        case .archived: ArchivedPostsView(session: session, onAction: onAction)
        }
    }
}

/// An empty section of an own-profile tab: one quiet line, not a full-screen
/// placeholder in the middle of a profile.
struct ProfileSectionNote: View {
    @Environment(\.alohaPalette) private var palette
    let text: Text

    var body: some View {
        text
            .font(.subheadline)
            .foregroundStyle(palette.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, AlohaMetrics.space2)
    }
}
