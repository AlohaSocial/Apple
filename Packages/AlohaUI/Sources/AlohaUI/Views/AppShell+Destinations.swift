// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The screen each route shows, and the titles of the feeds.
extension ThemedAppShell {
    /// A screen, root or pushed. `isRoot` is for the sidebar shells, whose
    /// root already wears "New post" and (on iPad) the account menu: a pushed
    /// screen keeps "New post" — writing should never be a Back away — but
    /// not the account menu, which sat beside the Back button there.
    func destination(
        _ route: Route, session: AccountSession, isRoot: Bool = false
    ) -> some View {
        AnyView(destinationContent(route, session: session))
            .modifier(ContinuityAdvertiser(route: route, session: session))
            .toolbar {
                if usesSidebar && !isRoot { composeToolbar }
            }
    }

    @ViewBuilder
    private func destinationContent(_ route: Route, session: AccountSession) -> some View {
        switch route {
        case .thread(let statusID):
            ThreadView(statusID: statusID, session: session) { handle($0, session: session) }
                .readerColumn
        case .profile(let accountID):
            ProfileView(accountID: accountID, session: session) { handle($0, session: session) }
                .readerColumn
        case .hashtag(let name):
            HashtagTimelineView(name: name, session: session) { handle($0, session: session) }
        case .bookmarks:
            TimelineView(
                key: TimelineKey(mode: .home, source: .bookmarks), session: session
            ) { handle($0, session: session) }
            .navigationTitle(Text("Bookmarks", comment: "Screen title"))
        case .favourites:
            TimelineView(
                key: TimelineKey(mode: .home, source: .favourites), session: session
            ) { handle($0, session: session) }
            .navigationTitle(Text("Liked posts", comment: "Screen title"))
        case .notifications:
            NotificationsView(session: session) { handle($0, session: session) }
                .readerColumn
        case .settings:
            SettingsView(onAddAccount: { isPresentingSignIn = true })
                .readerColumn
        case .explore:
            ExploreView(session: session) { handle($0, session: session) }
        case .search(let query):
            SearchView(session: session, initialQuery: query) { handle($0, session: session) }
                .readerColumn
        case .lists:
            ListsView(session: session)
                .readerColumn
        case .filters:
            FiltersView(session: session)
                .readerColumn
        case .safety:
            SafetyListsView(session: session)
                .readerColumn
        case .conversations:
            ConversationsView(
                session: session,
                onAction: { handle($0, session: session) },
                onOpen: { open($0) })
        case .conversation(let conversation):
            ConversationThreadView(conversation: conversation, session: session) {
                handle($0, session: session)
            }
        case .video(let statusID):
            VideoWatchView(statusID: statusID, session: session) { handle($0, session: session) }
        case .drafts:
            DraftsView(session: session)
        case .scheduledPosts:
            ScheduledPostsView(session: session)
        case .notificationRequests:
            NotificationRequestsView(session: session)
        case .notificationPolicy:
            NotificationPolicyView(session: session)
        case .followRequests:
            FollowRequestsView(session: session) { handle($0, session: session) }
        case .handle(let acct):
            ResolvingProfileView(handle: acct, session: session) { handle($0, session: session) }
        case .timeline(let key):
            TimelineView(key: key, session: session) { handle($0, session: session) }

        // Nextcloud Social surfaces.
        case .interests:
            InterestsSettingsScreen(session: session)
        case .memories:
            MemoriesView(session: session) { handle($0, session: session) }
        case .heldPosts:
            HeldPostsView(session: session)
        case .starterPacks:
            StarterPacksView(session: session) { handle($0, session: session) }
        case .starterPack(let slug):
            StarterPackView(slug: slug, session: session) { handle($0, session: session) }
        case .place(let id):
            PlaceView(id: id, session: session) { handle($0, session: session) }
        case .archived:
            ArchivedPostsView(session: session) { handle($0, session: session) }
        case .statistics:
            StatisticsView(session: session)
        case .portfolio:
            PortfolioView(session: session)
        case .migration:
            MigrationView(session: session)
        case .authorizedApps:
            AuthorizedAppsView(session: session)
        case .featuredTags:
            FeaturedTagsView(session: session)
        case .editProfile:
            EditProfileView(session: session)
        case .channels:
            ChannelsView(session: session)
        case .collections(let accountID):
            CollectionsView(session: session, accountID: accountID) { handle($0, session: session) }
        case .followers(let accountID):
            FollowersView(accountID: accountID, kind: .followers, session: session) {
                handle($0, session: session)
            }
        case .following(let accountID):
            FollowersView(accountID: accountID, kind: .following, session: session) {
                handle($0, session: session)
            }
        case .tagged(let accountID):
            TaggedPostsView(accountID: accountID, session: session) { handle($0, session: session) }
        // Surfaces the web app has, or the server serves and nobody drew.
        case .annualReport:
            AnnualReportView(session: session) { handle($0, session: session) }
        case .serverInfo:
            ServerInfoView(session: session)
        case .deleteAccount:
            DeleteAccountView(session: session)
        case .moderation:
            ModerationView(session: session) { handle($0, session: session) }
        case .moderationReports:
            ModerationReportsView(session: session) { handle($0, session: session) }
        case .moderationReport(let id):
            ModerationReportView(reportID: id, session: session) { handle($0, session: session) }
        case .moderationAccounts:
            ModerationAccountsView(session: session) { handle($0, session: session) }
        case .moderationTrends:
            ModerationTrendsView(session: session) { handle($0, session: session) }

        case .quotes(let statusID):
            QuotesView(statusID: statusID, session: session) { handle($0, session: session) }

        case .blueskyFeeds:
            BlueskyFeedsView(session: session)
        case .blueskyFeed(let uri, let name):
            BlueskyFeedTimelineView(uri: uri, name: name, session: session) {
                handle($0, session: session)
            }
        case .blueskySettings:
            BlueskySettingsView(session: session)
        case .blueskyStarterPack(let address):
            BlueskyStarterPackView(address: address, session: session)
        case .filterPost(let statusID):
            FilterPostView(statusID: statusID, session: session)
        case .linkTimeline(let url, let title):
            LinkTimelineView(url: url, title: title, session: session) {
                handle($0, session: session)
            }
        }
    }

    var sourceTitle: String {
        switch selectedSource {
        case .interests: String(localized: "For you", comment: "Timeline source")
        case .local: String(localized: "Local", comment: "Timeline source")
        case .federated: String(localized: "Global", comment: "Timeline source")
        default: String(localized: "My Feed", comment: "Mode title")
        }
    }

    func modeTitle(_ mode: FeedMode) -> String {
        switch mode {
        // The wording follows Nextcloud Social's own navigation, so the two
        // read as the same product.
        case .home: String(localized: "My Feed", comment: "Mode title")
        case .photos: String(localized: "Photos", comment: "Mode title")
        case .video: String(localized: "Videos", comment: "Mode title")
        case .shorts: String(localized: "Shorts", comment: "Mode title")
        case .news: String(localized: "News", comment: "Mode title")
        case .audio: String(localized: "Audio", comment: "Mode title")
        }
    }
}
