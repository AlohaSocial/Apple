// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Never more than two taps from a status or a profile, as App Review's UGC
/// rules require (docs/11 §1.2).
public struct ReportView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let session: AccountSession
    private let account: Account
    private let status: Status?

    @State private var category = "spam"
    @State private var selectedRules: Set<String> = []
    @State private var comment = ""
    @State private var forwardToOrigin = false
    @State private var rules: [InstanceDescription.Rule] = []
    @State private var isSending = false
    @State private var didSend = false
    /// Set only when the report itself did not go through. The form stays up
    /// with everything typed still in it, so the same report can be sent again.
    @State private var sendError: String?
    @State private var alsoBlock = false
    @State private var alsoMute = false

    public init(session: AccountSession, account: Account, status: Status? = nil) {
        self.session = session
        self.account = account
        self.status = status
    }

    private var isRemote: Bool {
        account.acct.contains("@")
    }

    public var body: some View {
        NavigationStack {
            Form {
                if didSend {
                    confirmation
                } else {
                    form
                }
            }
            .formStyle(.grouped)
            .alohaGround(palette)
            .navigationTitle(Text("Report", comment: "Report screen title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", comment: "Sheet action")
                    }
                }
                if !didSend {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await send() }
                        } label: {
                            if isSending {
                                ProgressView()
                            } else {
                                Text("Send", comment: "Report action")
                            }
                        }
                        .disabled(isSending)
                    }
                }
            }
            .task { await loadRules() }
        }
    }

    @ViewBuilder
    private var form: some View {
        if let sendError {
            Section {
                HStack(spacing: AlohaMetrics.space2) {
                    Image(systemName: AlohaSymbol.warning)
                    Text(sendError).font(.footnote)
                    Spacer()
                    Button {
                        Task { await send() }
                    } label: {
                        Text("Try again", comment: "Report send retry")
                    }
                    .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(palette.destructive)
                .listRowSeparator(.hidden)
            }
        }

        Section {
            Picker(selection: $category) {
                Text("Spam", comment: "Report category").tag("spam")
                Text("Breaks a server rule", comment: "Report category").tag("violation")
                Text("Illegal content", comment: "Report category").tag("legal")
                Text("Something else", comment: "Report category").tag("other")
            } label: {
                Text("Reason", comment: "Report field")
            }
            .pickerStyle(.inline)
        } header: {
            Text("Why are you reporting this?", comment: "Report section")
        }

        // The instance's own rules become selectable reasons where it publishes
        // them, which is what makes a "violation" report actionable.
        if category == "violation" && !rules.isEmpty {
            Section {
                ForEach(rules) { rule in
                    Toggle(isOn: selection(for: rule.id)) {
                        Text(rule.text).font(.footnote)
                    }
                    .toggleStyle(.automatic)
                }
            } header: {
                Text("Which rule?", comment: "Report section")
            }
        }

        Section {
            TextField(
                text: $comment,
                prompt: Text("Anything the moderators should know", comment: "Report placeholder"),
                axis: .vertical
            ) {
                Text("Comment", comment: "Report field")
            }
            .lineLimit(3...8)
        }

        if isRemote {
            Section {
                Toggle(isOn: $forwardToOrigin) {
                    Text("Also send to their server", comment: "Report option")
                }
            } footer: {
                Text(
                    "\(account.host ?? "Their server") moderates this account. Sending it there too usually gets more done.",
                    comment: "Report forwarding explanation")
            }
        }

        // The three decisions belong together.
        Section {
            Toggle(isOn: $alsoBlock) {
                Text("Block this account", comment: "Report option")
            }
            Toggle(isOn: $alsoMute) {
                Text("Mute this account", comment: "Report option")
            }
        } header: {
            Text("While you're here", comment: "Report section")
        }
    }

    private var confirmation: some View {
        Section {
            VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                Label {
                    Text("Report sent", comment: "Report confirmation")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(.headline)
                .foregroundStyle(palette.accent)

                Text(
                    forwardToOrigin
                        ? String(
                            localized:
                                "It's gone to this server's moderators and to \(account.host ?? "their server").",
                            comment: "Report confirmation detail")
                        : String(
                            localized: "It's gone to this server's moderators.",
                            comment: "Report confirmation detail")
                )
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)

                Button {
                    dismiss()
                } label: {
                    Text("Done", comment: "Sheet action")
                }
            }
        }
    }

    /// One rule's tick, as a binding the native checkmark style can drive.
    private func selection(for ruleID: String) -> Binding<Bool> {
        Binding(
            get: { selectedRules.contains(ruleID) },
            set: { isOn in
                if isOn {
                    selectedRules.insert(ruleID)
                } else {
                    selectedRules.remove(ruleID)
                }
            })
    }

    private func loadRules() async {
        rules =
            (try? await session.client.decode(
                LossyArray<InstanceDescription.Rule>.self, from: Endpoint.instance.rules))?.elements
            ?? []
    }

    private func send() async {
        isSending = true
        defer { isSending = false }

        do {
            _ = try await session.client.send(
                Endpoint.safety.report(
                    accountID: account.id,
                    statusIDs: status.map { [$0.displayed.id] } ?? [],
                    comment: comment,
                    forward: forwardToOrigin,
                    category: category,
                    ruleIDs: Array(selectedRules)))
        } catch {
            await session.handle(error)
            // Nothing is cleared: the typed comment stays where it was, and
            // "Report sent" is not shown for a report the server never got.
            sendError =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "The report could not be sent. Your comment has been kept.",
                    comment: "Report send failure")
            return
        }

        // Only once the report itself has landed: blocking or muting first
        // would act on the account while the record of why never arrives.
        if alsoBlock {
            _ = try? await session.client.send(
                Endpoint.accounts.simpleAction(account.id, "block"))
        }
        if alsoMute {
            _ = try? await session.client.send(
                Endpoint.accounts.mute(account.id, notifications: true, duration: nil))
        }

        sendError = nil
        didSend = true
    }
}

/// Blocked accounts, muted accounts and blocked domains.
public struct SafetyListsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession

    @State private var blocked: [Account] = []
    @State private var muted: [Account] = []
    @State private var domains: [String] = []
    @State private var newDomain = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// The accounts and domains with a request in flight, so a second tap
    /// cannot send the same one twice.
    @State private var pendingIDs: Set<String> = []
    @State private var isBlockingDomain = false

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        List {
            if let errorMessage {
                errorStrip(errorMessage)
            }

            Section {
                ForEach(blocked) { account in
                    HStack {
                        AccountRow(account: account, localHost: session.snapshot.instanceHost)
                        Spacer()
                        Button {
                            Task { await unblock(account) }
                        } label: {
                            Text("Unblock", comment: "Safety action")
                        }
                        .font(.caption)
                        .disabled(pendingIDs.contains(account.id))
                    }
                }
                if blocked.isEmpty && !isLoading && errorMessage == nil { emptyRow }
            } header: {
                Text("Blocked accounts", comment: "Safety section")
            }

            Section {
                ForEach(muted) { account in
                    HStack {
                        AccountRow(account: account, localHost: session.snapshot.instanceHost)
                        Spacer()
                        Button {
                            Task { await unmute(account) }
                        } label: {
                            Text("Unmute", comment: "Safety action")
                        }
                        .font(.caption)
                        .disabled(pendingIDs.contains(account.id))
                    }
                }
                if muted.isEmpty && !isLoading && errorMessage == nil { emptyRow }
            } header: {
                Text("Muted accounts", comment: "Safety section")
            }

            Section {
                ForEach(domains, id: \.self) { domain in
                    HStack {
                        Text(domain)
                        Spacer()
                        Button {
                            Task { await unblockDomain(domain) }
                        } label: {
                            Text("Unblock", comment: "Safety action")
                        }
                        .font(.caption)
                        .disabled(pendingIDs.contains(domain))
                    }
                }
                HStack {
                    TextField(
                        text: $newDomain,
                        prompt: Text(verbatim: "example.social")
                    ) {
                        Text("Domain", comment: "Safety field")
                    }
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                    Button {
                        Task { await blockDomain() }
                    } label: {
                        Text("Block", comment: "Safety action")
                    }
                    .disabled(
                        newDomain.isEmpty || isBlockingDomain
                            || domains.contains(domainKey(newDomain)))
                }
                if domains.isEmpty && !isLoading && errorMessage == nil { emptyRow }
            } header: {
                Text("Blocked servers", comment: "Safety section")
            } footer: {
                Text(
                    "Blocking a server hides everyone on it and removes your follows there.",
                    comment: "Domain block explanation")
            }
        }
        .alohaGround(palette)
        .overlay {
            if isLoading && blocked.isEmpty && muted.isEmpty && domains.isEmpty {
                ProgressView()
            }
        }
        .navigationTitle(Text("Blocking", comment: "Screen title"))
        .task { await load() }
        .refreshable { await load() }
    }

    private func errorStrip(_ message: String) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.warning)
            Text(message).font(.footnote)
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Text("Retry", comment: "Blocking reload action")
            }
            .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(palette.destructive)
        .listRowSeparator(.hidden)
    }

    private var emptyRow: some View {
        ContentUnavailableView {
            Text("None", comment: "Empty safety list")
        }
        .listRowSeparator(.hidden)
    }

    private func domainKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Blocks and mutes take no cursor and send no `Link` header, so they are
    /// fetched by `limit` alone in a bounded loop (docs/02 §5).
    private func load() async {
        // A load that lands mid-action would overwrite the optimistic list
        // with the server's pre-action snapshot; the action's own outcome is
        // the newer truth.
        guard pendingIDs.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let blocks = session.client.decode(
                LossyArray<Account>.self, from: Endpoint.accounts.blocks(limit: 80))
            async let mutes = session.client.decode(
                LossyArray<Account>.self, from: Endpoint.accounts.mutes(limit: 80))
            async let servers = session.client.decode(
                LossyArray<String>.self, from: Endpoint.accounts.domainBlocks)
            blocked = try await blocks.elements
            muted = try await mutes.elements
            domains = try await servers.elements
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "Blocking could not be loaded. Pull down to try again.",
                    comment: "Blocking load failure")
        }
    }

    private func unblock(_ account: Account) async {
        guard !pendingIDs.contains(account.id) else { return }
        pendingIDs.insert(account.id)
        defer { pendingIDs.remove(account.id) }
        let index = blocked.firstIndex { $0.id == account.id } ?? blocked.endIndex
        blocked.removeAll { $0.id == account.id }
        do {
            _ = try await session.client.send(
                Endpoint.accounts.simpleAction(account.id, "unblock"))
            errorMessage = nil
        } catch {
            // Only the refused row comes back — never a whole pre-action
            // snapshot. Restoring that would resurrect rows whose actions
            // succeeded while this one was still on the wire.
            if !blocked.contains(where: { $0.id == account.id }) {
                blocked.insert(account, at: min(index, blocked.endIndex))
            }
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "That account could not be unblocked. Try again.",
                    comment: "Unblock failure")
        }
    }

    private func unmute(_ account: Account) async {
        guard !pendingIDs.contains(account.id) else { return }
        pendingIDs.insert(account.id)
        defer { pendingIDs.remove(account.id) }
        let index = muted.firstIndex { $0.id == account.id } ?? muted.endIndex
        muted.removeAll { $0.id == account.id }
        do {
            _ = try await session.client.send(
                Endpoint.accounts.simpleAction(account.id, "unmute"))
            errorMessage = nil
        } catch {
            if !muted.contains(where: { $0.id == account.id }) {
                muted.insert(account, at: min(index, muted.endIndex))
            }
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "That account could not be unmuted. Try again.",
                    comment: "Unmute failure")
        }
    }

    private func blockDomain() async {
        let domain = domainKey(newDomain)
        guard !domain.isEmpty, !domains.contains(domain), !isBlockingDomain else { return }
        isBlockingDomain = true
        defer { isBlockingDomain = false }
        newDomain = ""
        domains.append(domain)
        do {
            _ = try await session.client.send(Endpoint.accounts.blockDomain(domain))
            errorMessage = nil
        } catch {
            // Duplicating an id in this list would break the rows built from
            // it, and the typed domain comes back so it can be sent again.
            domains.removeAll { $0 == domain }
            newDomain = domain
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "That server could not be blocked. Try again.",
                    comment: "Domain block failure")
        }
    }

    private func unblockDomain(_ domain: String) async {
        guard !pendingIDs.contains(domain) else { return }
        pendingIDs.insert(domain)
        defer { pendingIDs.remove(domain) }
        let index = domains.firstIndex(of: domain) ?? domains.endIndex
        domains.removeAll { $0 == domain }
        do {
            _ = try await session.client.send(Endpoint.accounts.unblockDomain(domain))
            errorMessage = nil
        } catch {
            if !domains.contains(domain) {
                domains.insert(domain, at: min(index, domains.endIndex))
            }
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "That server could not be unblocked. Try again.",
                    comment: "Domain unblock failure")
        }
    }
}
