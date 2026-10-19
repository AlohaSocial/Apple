// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// Native navigation menu and checked account picker, shared across platforms.
struct AccountMenuButton: View {
    @Environment(AppEnvironment.self) private var environment

    let session: AccountSession
    let onOpen: (Route) -> Void
    let onAddAccount: () -> Void
    var showsBrowseDestinations = true
    var showsName = false
    var usesCompactMenu = false

    var body: some View {
        Menu {
            if showsBrowseDestinations {
                // No Activities: it is a tab or a sidebar row on every
                // platform, as in Nextcloud Social's sidebar.
                Section {
                    item("Discover", symbol: "safari", route: .explore)
                    item("Your lists", symbol: AlohaSymbol.list, route: .lists)
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
                }
                #if os(macOS)
                    // The Mac has a Settings window (⌘,), and settings that
                    // open inside the main window are a phone's habit.
                    SettingsLink {
                        Label {
                            Text("Settings…", comment: "Account menu item")
                        } icon: {
                            Image(systemName: AlohaSymbol.settings)
                        }
                    }
                #else
                    item("Settings", symbol: AlohaSymbol.settings, route: .settings)
                #endif
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
        .help(Text("Account", comment: "Account menu section"))
    }

    private var accessibilityLabel: Text {
        Text(
            "\(session.snapshot.bestDisplayName), account menu",
            comment: "Accessibility label for the account drawer toggle")
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
