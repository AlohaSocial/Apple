// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// Native navigation menu and checked account picker, shared across platforms.
struct AccountMenuButton: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession
    let onOpen: (Route) -> Void
    let onAddAccount: () -> Void
    var showsBrowseDestinations = true
    var showsName = false
    var usesCompactMenu = false
    /// False where Activities has a tab of its own, so the menu does not
    /// offer the same place twice.
    var showsActivities = true
    /// Unread activities, drawn on the avatar where Activities has no tab to
    /// carry the count — otherwise the only sign of them is the app icon.
    var unreadActivities = 0

    var body: some View {
        Menu {
            if showsBrowseDestinations {
                Section {
                    if showsActivities {
                        item("Activities", symbol: AlohaSymbol.notifications, route: .notifications)
                    }
                    item("Discover", symbol: "safari", route: .explore)
                    item("Your lists", symbol: AlohaSymbol.list, route: .lists)
                    if session.capabilities.isNextcloudSocial {
                        item("My interests", symbol: "sparkles", route: .interests)
                        item(
                            "Subscriptions", symbol: "dot.radiowaves.up.forward",
                            route: .subscriptions)
                    }
                    if session.capabilities.collections {
                        item(
                            "Albums", symbol: "rectangle.stack", route: .collections(accountID: nil)
                        )
                    }
                } header: {
                    Text("Explore", comment: "Account menu section")
                }

            }
            Section {
                item(
                    "My profile", symbol: "person.crop.circle",
                    route: .profile(accountID: session.snapshot.serverAccountID))
                if !usesCompactMenu {
                    item(
                        "Follow requests", symbol: "person.badge.clock", route: .followRequests)
                    item("Liked posts", symbol: AlohaSymbol.favourite, route: .favourites)
                    item("Bookmarks", symbol: AlohaSymbol.bookmark, route: .bookmarks)
                    if session.capabilities.isNextcloudSocial {
                        item("Archived posts", symbol: "archivebox", route: .archived)
                        item("Statistics", symbol: "chart.bar.xaxis", route: .statistics)
                    }
                    item("Blocking", symbol: "hand.raised", route: .safety)
                    if !showsBrowseDestinations {
                        item("Activities", symbol: AlohaSymbol.notifications, route: .notifications)
                    }
                }
                item("Settings", symbol: AlohaSymbol.settings, route: .settings)
            } header: {
                Text("Account", comment: "Account menu section")
            }

            Section {
                Picker(
                    selection: Binding(
                        get: { environment.activeSession?.id ?? session.id },
                        set: { environment.setActiveAccount($0) }
                    )
                ) {
                    ForEach(environment.sessions) { account in
                        Text(account.snapshot.bestDisplayName)
                            .accessibilityLabel(Text(account.snapshot.qualifiedHandle))
                            .tag(account.id)
                    }
                } label: {
                    Label {
                        Text("Switch account", comment: "Account switcher action")
                    } icon: {
                        Image(systemName: "person.crop.circle")
                    }
                }
                .pickerStyle(.menu)
                Button(action: onAddAccount) {
                    Label {
                        Text("Add account…", comment: "Account switcher action")
                    } icon: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
        } label: {
            // The mark is 30pt; the target around it is the 44pt Apple
            // asks for, so the tap does not need aim.
            HStack(spacing: 8) {
                AvatarView(account: session.snapshot.asAccount, size: 30)
                    .overlay(alignment: .topTrailing) {
                        if unreadActivities > 0 { unreadDot }
                    }
                    .accessibilityHidden(true)
                if showsName {
                    VStack(alignment: .leading) {
                        Text(session.snapshot.bestDisplayName).font(.subheadline)
                        Text(session.snapshot.qualifiedHandle).font(.caption).foregroundStyle(
                            .secondary)
                    }
                    .lineLimit(1)
                    Spacer()
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(showsName ? .visible : .hidden)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        guard unreadActivities > 0 else {
            return Text(
                "\(session.snapshot.bestDisplayName), account menu",
                comment: "Accessibility label for the account drawer toggle")
        }
        return Text(
            "\(session.snapshot.bestDisplayName), account menu, ^[\(unreadActivities) unread activity](inflect: true)",
            comment: "Accessibility label for the account drawer toggle with unread activities")
    }

    /// A dot rather than a number on a 30pt avatar: the count is in the
    /// accessibility label, and digits at this size are unreadable anyway.
    private var unreadDot: some View {
        Circle()
            .fill(palette.destructive)
            .frame(width: 10, height: 10)
            .overlay(Circle().strokeBorder(palette.background, lineWidth: 1.5))
            .offset(x: 2, y: -2)
    }

    private func item(
        _ title: String.LocalizationValue, symbol: String, route: Route
    ) -> some View {
        Button {
            onOpen(route)
        } label: {
            Label {
                Text(String(localized: title, comment: "Account menu item"))
            } icon: {
                Image(systemName: symbol)
            }
        }
    }
}
