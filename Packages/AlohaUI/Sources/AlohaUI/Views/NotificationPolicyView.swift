// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The notification policy screen: five for_* rows with Accept/Filter/Drop,
/// plus a link to the filtered-notifications inbox.
public struct NotificationPolicyView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.alohaMetrics) private var metrics
    @Environment(\.dismiss) private var dismiss

    private let session: AccountSession

    @State private var policy: NotificationPolicy?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var updatingIDs: Set<String> = []

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        List {
            if let errorMessage {
                errorStrip(errorMessage)
            }

            if let policy {
                // Typed locals, not a static table: a key-path literal is
                // inferred as an existential inside a view builder, and a
                // `static let` of one is a mutable global in Swift 6.
                let forNotFollowing:
                    ReferenceWritableKeyPath<
                        NotificationPolicy, NotificationPolicy.Decision
                    > = \.forNotFollowing
                let forNotFollowers:
                    ReferenceWritableKeyPath<
                        NotificationPolicy, NotificationPolicy.Decision
                    > = \.forNotFollowers
                let forNewAccounts:
                    ReferenceWritableKeyPath<
                        NotificationPolicy, NotificationPolicy.Decision
                    > = \.forNewAccounts
                let forPrivateMentions:
                    ReferenceWritableKeyPath<
                        NotificationPolicy, NotificationPolicy.Decision
                    > = \.forPrivateMentions
                let forLimitedAccounts:
                    ReferenceWritableKeyPath<
                        NotificationPolicy, NotificationPolicy.Decision
                    > = \.forLimitedAccounts

                Section {
                    policyRow(
                        key: forNotFollowing,
                        title: Text("People you don't follow", comment: "Policy row"),
                        policy: policy)
                    policyRow(
                        key: forNotFollowers,
                        title: Text("People who don't follow you", comment: "Policy row"),
                        policy: policy)
                    policyRow(
                        key: forNewAccounts,
                        title: Text("New accounts", comment: "Policy row"),
                        policy: policy)
                    policyRow(
                        key: forPrivateMentions,
                        title: Text("Unsolicited private mentions", comment: "Policy row"),
                        policy: policy)
                    policyRow(
                        key: forLimitedAccounts,
                        title: Text("Limited accounts", comment: "Policy row"),
                        policy: policy)
                } footer: {
                    Text(
                        "Mentions from people you don't follow, new accounts and limited accounts are the most common sources of unwanted attention. Setting them to \"Filter\" sends them to the Filtered notifications screen instead of your inbox.",
                        comment: "Notification policy explanation")

                    // docs/05 §6: on Nextcloud Social `drop` behaves as
                    // `filter` — the server has no fourth action. Saying so is
                    // not a footnote to hide behind; a person who picked "Drop"
                    // and later finds the message held in the inbox has been
                    // lied to, however politely.
                    if session.capabilities.isNextcloudSocial {
                        Text(
                            "On this server \"Drop\" holds messages out of your inbox the same way \"Filter\" does — there is no way to refuse them outright, and they are never sent back to their sender.",
                            comment: "Notification policy drop footnote")
                    }
                }

                if let summary = policy.summary,
                    summary.pendingRequestsCount > 0
                {
                    Section {
                        NavigationLink(value: Route.notificationRequests) {
                            HStack {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                Text("Filtered notifications")
                                Spacer()
                                Text("\(summary.pendingRequestsCount)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(palette.accent)
                            }
                        }
                        .accessibilityLabel(
                            Text(
                                "Filtered notifications: \(summary.pendingRequestsCount) waiting",
                                comment: "Filtered count"))
                    }
                }

                Section {
                    NavigationLink(value: Route.notificationRequests) {
                        Label {
                            Text("Open filtered notifications", comment: "Policy action")
                        } icon: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            } else {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
        }
        .alohaGround(palette)
        .navigationTitle(Text("Notification policy", comment: "Screen title"))
        .task { await load() }
    }

    private func policyRow(
        key: ReferenceWritableKeyPath<NotificationPolicy, NotificationPolicy.Decision>,
        title: Text,
        policy: NotificationPolicy
    ) -> some View {
        // The key path's string is the row's identity: it is what the
        // in-flight guard uses, and what SwiftUI needs to tell the rows apart.
        let id = "\(key)"
        let isUpdating = updatingIDs.contains(id)
        return Picker(
            selection: Binding(
                get: { policy[keyPath: key] },
                set: { newValue in
                    guard !isUpdating else { return }
                    Task { await update(key: key, value: newValue) }
                })
        ) {
            ForEach(NotificationPolicy.Decision.allCases.filter { !$0.isUnknown }, id: \.self) {
                decision in
                decisionTitle(decision).tag(decision)
            }
        } label: {
            title
        }
        .disabled(isUpdating)
    }

    /// The three decisions, each with a translator comment: a localised key
    /// cannot be built from the server's raw value, and "accept" is a word a
    /// translator wants context for.
    private func decisionTitle(_ decision: NotificationPolicy.Decision) -> Text {
        switch decision {
        case .accept:
            Text("Accept", comment: "Notification policy decision: mention reaches the inbox")
        case .filter:
            Text("Filter", comment: "Notification policy decision: held in the requests inbox")
        case .drop:
            Text("Drop", comment: "Notification policy decision: discarded by the server")
        case .unknownCase:
            // A state from a newer server than the app: named, not blank, and
            // never offered for sending.
            Text("Unknown", comment: "Notification policy decision the app does not know")
        }
    }

    private func update(
        key: ReferenceWritableKeyPath<NotificationPolicy, NotificationPolicy.Decision>,
        value: NotificationPolicy.Decision
    ) async {
        guard var policy, !updatingIDs.contains("\(key)") else { return }
        updatingIDs.insert("\(key)")
        defer { updatingIDs.remove("\(key)") }
        policy[keyPath: key] = value
        let useV2 = session.capabilities.notificationPolicy
        let endpoint = Endpoint.notifications.updatePolicy(v2: useV2, policy: policy)
        do {
            _ = try await session.client.send(endpoint)
            self.policy = policy
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let useV2 = session.capabilities.notificationPolicy
        do {
            let result = try await session.client.decode(
                NotificationPolicy.self, from: Endpoint.notifications.policy(v2: useV2))
            policy = result
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func errorStrip(_ message: String) -> some View {
        AlohaErrorStrip(message: message) {
            Task { await load() }
        }
    }
}
