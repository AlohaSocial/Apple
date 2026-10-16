// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The moderator's three screens: the reports queue, the accounts, and what may
/// trend.
///
/// Nextcloud Social's admin panel is a Nextcloud settings page — its
/// `/moderation/*` routes need a session **and** a CSRF token, which no API
/// client has and none can obtain, so a moderator could act from a browser and
/// from nowhere else. The server grew Mastodon's `/api/v1/admin/*` for exactly
/// this, and that is what these screens speak (docs/11 §7).
///
/// **Only a Nextcloud administrator gets past the server's check**, whatever
/// scope a token carries, so the whole section hides itself on a 403 rather
/// than showing three empty lists to everybody else.
///
/// Instance configuration — storage, retention, relays, the blocklist, setup
/// checks — is deliberately not here. It belongs where an administrator already
/// is when they are doing it, which is the web administration page.
public struct ModerationView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var openReports: Int?
    @State private var isPermitted: Bool?

    public init(session: AccountSession, onAction: @escaping (StatusRowAction) -> Void) {
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        List {
            if isPermitted == false {
                Section {
                    ContentUnavailableView {
                        Text("Not yours to moderate", comment: "Moderation forbidden")
                    } description: {
                        Text(
                            "Only an administrator of this Nextcloud can see reports and act on accounts.",
                            comment: "Moderation forbidden detail")
                    }
                }
            } else {
                Section {
                    NavigationLink(value: Route.moderationReports) {
                        HStack {
                            Label {
                                Text("Reports", comment: "Moderation section")
                            } icon: {
                                Image(systemName: AlohaSymbol.report)
                            }
                            Spacer()
                            if let openReports, openReports > 0 {
                                Text(openReports, format: .number)
                                    .font(AlohaType.micro)
                                    .foregroundStyle(palette.destructive)
                                    .padding(.horizontal, AlohaMetrics.space2)
                                    .padding(.vertical, AlohaMetrics.space1)
                                    .background(
                                        palette.destructive.opacity(0.12), in: Capsule())
                            }
                        }
                    }

                    NavigationLink(value: Route.moderationAccounts) {
                        Label {
                            Text("Accounts", comment: "Moderation section")
                        } icon: {
                            Image(systemName: AlohaSymbol.profile)
                        }
                    }

                    NavigationLink(value: Route.moderationTrends) {
                        Label {
                            Text("What may trend", comment: "Moderation section")
                        } icon: {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                        }
                    }
                } footer: {
                    Text(
                        "Everything else an administrator does to this instance — storage, retention, relays, the blocklist — stays in the Nextcloud administration page.",
                        comment: "Moderation scope explanation")
                }
            }
        }
        .alohaGround(palette)
        .navigationTitle(Text("Moderation", comment: "Screen title"))
        .task { await probe() }
    }

    /// One cheap read decides whether the section works at all, and fills the
    /// badge while it is at it.
    private func probe() async {
        do {
            let reports = try await session.client.decode(
                LossyArray<AdminReport>.self,
                from: Endpoint.moderation.reports(resolved: false, limit: 40))
            openReports = reports.elements.count
            isPermitted = true
        } catch APIError.forbidden, APIError.unauthorised {
            isPermitted = false
        } catch {
            // A network failure is not "you may not"; the rows stay.
            isPermitted = true
        }
    }
}

// MARK: - Reports

/// The queue a moderator opens the panel to work through.
public struct ModerationReportsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var reports: [AdminReport] = []
    @State private var showsResolved = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init(session: AccountSession, onAction: @escaping (StatusRowAction) -> Void) {
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        List {
            if let errorMessage {
                errorStrip(errorMessage)
            }

            Picker(selection: $showsResolved) {
                Text("Open", comment: "Reports filter").tag(false)
                Text("Handled", comment: "Reports filter").tag(true)
            } label: {
                Text("Show", comment: "Reports filter")
            }
            .pickerStyle(.segmented)

            ForEach(reports) { report in
                NavigationLink(value: Route.moderationReport(id: report.id)) {
                    ReportSummaryRow(report: report, localHost: session.snapshot.instanceHost)
                }
            }

            if isLoading && reports.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AlohaMetrics.space5)
            } else if reports.isEmpty && errorMessage == nil {
                ContentUnavailableView {
                    Text(
                        showsResolved
                            ? String(localized: "Nothing handled yet", comment: "Reports empty")
                            : String(localized: "Nothing to look at", comment: "Reports empty"))
                } description: {
                    Text(
                        "Reports from people here and from other servers land in this queue.",
                        comment: "Reports empty detail")
                }
            }
        }
        .alohaGround(palette)
        .navigationTitle(Text("Reports", comment: "Screen title"))
        .refreshable { await load() }
        .task(id: showsResolved) { await load() }
    }

    private func errorStrip(_ message: String) -> some View {
        AlohaErrorStrip(message: message) {
            Task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            reports = try await session.client.decode(
                LossyArray<AdminReport>.self,
                from: Endpoint.moderation.reports(resolved: showsResolved, limit: 40)
            ).elements
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}

struct ReportSummaryRow: View {
    @Environment(\.alohaPalette) private var palette

    let report: AdminReport
    let localHost: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: AlohaMetrics.space2) {
                if let target = report.targetAccount {
                    Text(target.qualifiedHandle(localHost: localHost))
                        .font(AlohaType.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if report.actionTaken {
                    Text("Handled", comment: "Report badge")
                        .font(AlohaType.micro)
                        .foregroundStyle(palette.secondaryLabel)
                } else if report.isAssigned {
                    Text("Taken", comment: "Report badge")
                        .font(AlohaType.micro)
                        .foregroundStyle(palette.accent)
                }
            }

            if !report.comment.isEmpty {
                Text(report.comment)
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(2)
            }

            HStack(spacing: AlohaMetrics.space2) {
                if !report.category.isEmpty {
                    Text(verbatim: report.category)
                        .font(AlohaType.micro)
                        .foregroundStyle(palette.tertiaryLabel)
                }
                if report.forwarded {
                    Text("Forwarded", comment: "Report badge")
                        .font(AlohaType.micro)
                        .foregroundStyle(palette.tertiaryLabel)
                }
                if !report.statuses.isEmpty {
                    Text("^[\(report.statuses.count) post](inflect: true)", comment: "Report badge")
                        .font(AlohaType.micro)
                        .foregroundStyle(palette.tertiaryLabel)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// One report, and the decisions that can be taken from it.
public struct ModerationReportView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    private let session: AccountSession
    private let reportID: String
    private let onAction: (StatusRowAction) -> Void

    @State private var report: AdminReport?
    @State private var note = ""
    @State private var isWorking = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// Identifies the newest `load()` so a slow first response cannot
    /// overwrite a newer one's data or error.
    @State private var loadID = UUID()

    public init(
        reportID: String, session: AccountSession, onAction: @escaping (StatusRowAction) -> Void
    ) {
        self.reportID = reportID
        self.session = session
        self.onAction = onAction
    }

    public var body: some View {
        List {
            if let errorMessage {
                errorStrip(errorMessage)
            }

            if let report {
                Section {
                    if let target = report.targetAccount {
                        Button {
                            onAction(.openProfile(target))
                        } label: {
                            AccountRow(account: target, localHost: session.snapshot.instanceHost)
                        }
                        .buttonStyle(.plain)
                    }
                    if !report.category.isEmpty {
                        LabeledContent {
                            Text(verbatim: report.category)
                        } label: {
                            Text("Category", comment: "Report field")
                        }
                    }
                    if let created = report.createdAt {
                        LabeledContent {
                            Text(created, format: .dateTime)
                        } label: {
                            Text("Reported", comment: "Report field")
                        }
                    }
                } header: {
                    Text("Reported account", comment: "Report section")
                }

                if !report.comment.isEmpty {
                    Section {
                        Text(report.comment)
                    } header: {
                        Text("What the reporter said", comment: "Report section")
                    }
                }

                if let reporter = report.account {
                    Section {
                        Button {
                            onAction(.openProfile(reporter))
                        } label: {
                            AccountRow(account: reporter, localHost: session.snapshot.instanceHost)
                        }
                        .buttonStyle(.plain)
                    } header: {
                        Text("Reported by", comment: "Report section")
                    }
                }

                if !report.statuses.isEmpty {
                    Section {
                        ForEach(report.statuses) { status in
                            Button {
                                onAction(.open(status))
                            } label: {
                                Text(StatusHTMLParser().plainText(status.displayed.content))
                                    .font(.subheadline)
                                    .foregroundStyle(palette.label)
                                    .lineLimit(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("The posts", comment: "Report section")
                    }
                }

                decisions(report)
            }
        }
        .alohaGround(palette)
        .navigationTitle(Text("Report", comment: "Screen title"))
        // Only while the request runs: a failure used to leave the spinner
        // over an empty screen with nothing to do about it.
        .overlay { if isLoading && report == nil { ProgressView() } }
        .task { await load() }
    }

    private func errorStrip(_ message: String) -> some View {
        AlohaErrorStrip(message: message) {
            Task { await load() }
        }
    }

    @ViewBuilder
    private func decisions(_ report: AdminReport) -> some View {
        Section {
            TextField(
                text: $note,
                prompt: Text("Why, for the record", comment: "Moderation note prompt")
            ) {
                Text("Note", comment: "Moderation field")
            }

            if let target = report.targetAccount {
                Button {
                    Task { await act(.silence, on: target.id, report: report) }
                } label: {
                    Text("Silence this account", comment: "Moderation action")
                }
                .disabled(isWorking)

                Button(role: .destructive) {
                    Task { await act(.suspend, on: target.id, report: report) }
                } label: {
                    Text("Suspend this account", comment: "Moderation action")
                }
                .disabled(isWorking)
            }

            if report.actionTaken {
                Button {
                    Task { await simple(Endpoint.moderation.reopenReport(report.id)) }
                } label: {
                    Text("Reopen", comment: "Moderation action")
                }
                .disabled(isWorking)
            } else {
                Button {
                    Task { await simple(Endpoint.moderation.resolveReport(report.id)) }
                } label: {
                    Text("Mark handled, no action", comment: "Moderation action")
                }
                .disabled(isWorking)

                if report.isAssigned {
                    Button {
                        Task { await simple(Endpoint.moderation.unassignReport(report.id)) }
                    } label: {
                        Text("Hand it back", comment: "Moderation action")
                    }
                    .disabled(isWorking)
                } else {
                    Button {
                        Task { await simple(Endpoint.moderation.assignReportToSelf(report.id)) }
                    } label: {
                        Text("Take this one", comment: "Moderation action")
                    }
                    .disabled(isWorking)
                }
            }
        } header: {
            Text("Decide", comment: "Report section")
        } footer: {
            Text(
                "Silencing keeps an account's posts from anyone who does not follow it. Suspending stops them being delivered or shown at all. Either way the report is marked handled.",
                comment: "Moderation decisions explanation")
        }
    }

    private func load() async {
        let requestID = UUID()
        loadID = requestID
        isLoading = true
        defer { if loadID == requestID { isLoading = false } }
        do {
            report = try await session.client.decode(
                AdminReport.self, from: Endpoint.moderation.report(reportID))
            guard !Task.isCancelled, loadID == requestID else { return }
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, loadID == requestID else { return }
            await session.handle(error)
            guard loadID == requestID else { return }
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "The report could not be opened.", comment: "Report load failure")
        }
    }

    private func act(_ action: AdminAccountAction, on accountID: String, report: AdminReport) async
    {
        isWorking = true
        defer { isWorking = false }
        do {
            // `report_id` resolves the report in the same call: a decision taken
            // from a report is the report handled, and two calls could disagree.
            _ = try await session.client.send(
                Endpoint.moderation.act(
                    on: accountID, action: action, note: note, reportID: report.id))
            await load()
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func simple(_ endpoint: Endpoint) async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await session.client.send(endpoint)
            await load()
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
