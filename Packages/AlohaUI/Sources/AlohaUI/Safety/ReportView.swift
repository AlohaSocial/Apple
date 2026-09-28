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
                    Button {
                        if selectedRules.contains(rule.id) {
                            selectedRules.remove(rule.id)
                        } else {
                            selectedRules.insert(rule.id)
                        }
                    } label: {
                        HStack(alignment: .top) {
                            Image(
                                systemName: selectedRules.contains(rule.id)
                                    ? "checkmark.square.fill" : "square"
                            )
                            .foregroundStyle(palette.accent)
                            Text(rule.text).font(.footnote)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
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
                .foregroundStyle(palette.boost)

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

    private func loadRules() async {
        rules =
            (try? await session.client.decode(
                LossyArray<InstanceDescription.Rule>.self, from: Endpoint.instance.rules))?.elements
            ?? []
    }

    private func send() async {
        isSending = true
        defer { isSending = false }

        _ = try? await session.client.send(
            Endpoint.safety.report(
                accountID: account.id,
                statusIDs: status.map { [$0.displayed.id] } ?? [],
                comment: comment,
                forward: forwardToOrigin,
                category: category,
                ruleIDs: Array(selectedRules)))

        if alsoBlock {
            _ = try? await session.client.send(
                Endpoint.accounts.simpleAction(account.id, "block"))
        }
        if alsoMute {
            _ = try? await session.client.send(
                Endpoint.accounts.mute(account.id, notifications: true, duration: nil))
        }

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

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        List {
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
                    }
                }
                if blocked.isEmpty { emptyRow }
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
                    }
                }
                if muted.isEmpty { emptyRow }
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
                    .disabled(newDomain.isEmpty)
                }
            } header: {
                Text("Blocked servers", comment: "Safety section")
            } footer: {
                Text(
                    "Blocking a server hides everyone on it and removes your follows there.",
                    comment: "Domain block explanation")
            }
        }
        .navigationTitle(Text("Blocking", comment: "Screen title"))
        .task { await load() }
        .refreshable { await load() }
    }

    private var emptyRow: some View {
        Text("None", comment: "Empty safety list")
            .font(.footnote)
            .foregroundStyle(palette.secondaryLabel)
    }

    /// Blocks and mutes take no cursor and send no `Link` header, so they are
    /// fetched by `limit` alone in a bounded loop (docs/02 §5).
    private func load() async {
        blocked =
            (try? await session.client.decode(
                LossyArray<Account>.self, from: Endpoint.accounts.blocks(limit: 80)))?.elements
            ?? []
        muted =
            (try? await session.client.decode(
                LossyArray<Account>.self, from: Endpoint.accounts.mutes(limit: 80)))?.elements ?? []
        domains =
            (try? await session.client.decode(
                LossyArray<String>.self, from: Endpoint.accounts.domainBlocks))?.elements ?? []
    }

    private func unblock(_ account: Account) async {
        blocked.removeAll { $0.id == account.id }
        _ = try? await session.client.send(Endpoint.accounts.simpleAction(account.id, "unblock"))
    }

    private func unmute(_ account: Account) async {
        muted.removeAll { $0.id == account.id }
        _ = try? await session.client.send(Endpoint.accounts.simpleAction(account.id, "unmute"))
    }

    private func blockDomain() async {
        let domain = newDomain.trimmingCharacters(in: .whitespaces).lowercased()
        guard !domain.isEmpty else { return }
        newDomain = ""
        domains.append(domain)
        _ = try? await session.client.send(Endpoint.accounts.blockDomain(domain))
    }

    private func unblockDomain(_ domain: String) async {
        domains.removeAll { $0 == domain }
        _ = try? await session.client.send(Endpoint.accounts.unblockDomain(domain))
    }
}
