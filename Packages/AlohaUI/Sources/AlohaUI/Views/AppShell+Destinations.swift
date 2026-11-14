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
    /// not the account menu, which sat beside the Back button there. Nor
    /// does a screen in the iPad's detail column: the primary column beside
    /// it is showing "New post" already, and two would also share ⌘N.
    func destination(
        _ route: Route, session: AccountSession, isRoot: Bool = false
    ) -> some View {
        AnyView(destinationContent(route, session: session))
            .modifier(ContinuityAdvertiser(route: route, session: session))
            // Post actions fail on threads, profiles, Activities and search
            // as well as the timeline; every screen can say so.
            .actionFeedbackToast()
            .toolbar {
                if usesSidebar && !isRoot && column == .primary { composeToolbar }
            }
    }

    /// Every route, in the group it belongs to.
    ///
    /// This used to be one `@ViewBuilder` switch over all of them. On a real
    /// iPad the compiler's frame for that single function was 16.7 KB, and
    /// building the sidebar's tab roots at launch overflowed the main thread's
    /// stack before the first frame was drawn. Each group now has its own
    /// function, so only the branches of the screen being built are alive on
    /// the stack; the tab contents are also built lazily (see
    /// `LazyShellContent`).
    @ViewBuilder
    private func destinationContent(_ route: Route, session: AccountSession) -> some View {
        switch route {
        case .thread, .profile, .hashtag, .bookmarks, .favourites, .notifications,
            .explore, .search, .lists, .filters, .timeline:
            timelineDestination(route, session: session)
        case .safety, .conversations, .conversation, .video, .drafts, .scheduledPosts,
            .notificationRequests, .notificationPolicy, .followRequests, .handle, .settings:
            conversationDestination(route, session: session)
        case .interests, .memories, .heldPosts, .starterPacks, .starterPack, .place,
            .archived, .collections, .followers, .following, .tagged, .annualReport:
            nextcloudSocialDestination(route, session: session)
        case .statistics, .portfolio, .migration, .authorizedApps, .featuredTags,
            .editProfile, .channels, .serverInfo, .deleteAccount:
            nextcloudAccountDestination(route, session: session)
        case .moderation, .moderationReports, .moderationReport, .moderationAccounts,
            .moderationTrends, .quotes:
            moderationDestination(route, session: session)
        case .blueskyFeeds, .blueskyFeed, .blueskySettings, .blueskyStarterPack, .filterPost,
            .linkTimeline:
            blueskyDestination(route, session: session)
        }
    }

    @ViewBuilder
    private func timelineDestination(_ route: Route, session: AccountSession) -> some View {
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
        case .timeline(let key):
            TimelineView(key: key, session: session) { handle($0, session: session) }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func conversationDestination(_ route: Route, session: AccountSession) -> some View {
        switch route {
        case .settings:
            SettingsView(onAddAccount: { presentSignIn() })
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
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func nextcloudSocialDestination(_ route: Route, session: AccountSession) -> some View {
        switch route {
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
        case .annualReport:
            AnnualReportView(session: session) { handle($0, session: session) }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func nextcloudAccountDestination(_ route: Route, session: AccountSession) -> some View {
        switch route {
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
        case .serverInfo:
            ServerInfoView(session: session)
        case .deleteAccount:
            DeleteAccountView(session: session)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func moderationDestination(_ route: Route, session: AccountSession) -> some View {
        switch route {
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
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func blueskyDestination(_ route: Route, session: AccountSession) -> some View {
        switch route {
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
        default:
            EmptyView()
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
