// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

#if os(iOS)
    /// The phone's account menu: your face, top left, and behind it everywhere
    /// that is not a timeline.
    ///
    /// The same contents as the sidebar's account drawer on a Mac or iPad, in
    /// the same order. They used to hang off the timeline-source button, which
    /// put "who am I" and "which feed am I reading" behind one control.
    struct AccountMenuButton: View {
        @Environment(AppEnvironment.self) private var environment

        let session: AccountSession
        let onOpen: (Route) -> Void
        let onAddAccount: () -> Void

        var body: some View {
            Menu {
                Section {
                    item("Activities", symbol: AlohaSymbol.notifications, route: .notifications)
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

                Section {
                    item(
                        "My profile", symbol: "person.crop.circle",
                        route: .profile(accountID: session.snapshot.serverAccountID))
                    item(
                        "Follow requests", symbol: "person.badge.clock", route: .followRequests)
                    item("Liked posts", symbol: AlohaSymbol.favourite, route: .favourites)
                    item("Bookmarks", symbol: AlohaSymbol.bookmark, route: .bookmarks)
                    if session.capabilities.isNextcloudSocial {
                        item("Archived posts", symbol: "archivebox", route: .archived)
                        item("Statistics", symbol: "chart.bar.xaxis", route: .statistics)
                    }
                    item("Blocking", symbol: "hand.raised", route: .safety)
                    item("Settings", symbol: AlohaSymbol.settings, route: .settings)
                } header: {
                    Text("Account", comment: "Account menu section")
                }

                Section {
                    ForEach(environment.sessions.filter { $0.id != session.id }) { other in
                        Button {
                            environment.setActiveAccount(other.id)
                        } label: {
                            Label {
                                Text(other.snapshot.qualifiedHandle)
                            } icon: {
                                Image(systemName: "arrow.left.arrow.right")
                            }
                        }
                    }
                    Button(action: onAddAccount) {
                        Label {
                            Text("Add account…", comment: "Account switcher action")
                        } icon: {
                            Image(systemName: "person.badge.plus")
                        }
                    }
                }
            } label: {
                AvatarView(account: session.snapshot.asAccount, size: 30)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(
                Text(
                    "\(session.snapshot.bestDisplayName), account menu",
                    comment: "Accessibility label for the account drawer toggle"))
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
#endif
