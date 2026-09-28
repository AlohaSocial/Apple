// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import Charts
import SwiftUI

/// Per-account statistics: what you posted, who answered, when, and in what
/// language — over a window you choose. Everything is counted by your own
/// server; nothing leaves it.
public struct StatisticsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession

    @State private var statistics: AccountStatistics?
    @State private var days = 90
    @State private var isLoading = true
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var errorMessage: String?

    private static let windows: [(days: Int, title: LocalizedStringResource)] = [
        (30, LocalizedStringResource("30 days", comment: "Statistics window")),
        (90, LocalizedStringResource("90 days", comment: "Statistics window")),
        (365, LocalizedStringResource("A year", comment: "Statistics window")),
        (0, LocalizedStringResource("All time", comment: "Statistics window")),
    ]

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlohaMetrics.space5) {
                windowPicker

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(palette.destructive)
                }

                if let statistics {
                    hero(statistics)
                    engagement(statistics)
                    postsByMonth(statistics)
                    engagementByMonth(statistics)
                    activity(statistics)
                    visibility(statistics)
                    consistency(statistics)
                    namedCounts(
                        Text("Hashtags", comment: "Statistics section"), statistics.hashtags,
                        prefix: "#")
                    namedCounts(
                        Text("Languages", comment: "Statistics section"), statistics.languages)
                    namedCounts(
                        Text("Sites you link to", comment: "Statistics section"), statistics.domains
                    )
                    partners(statistics)
                    media(statistics)
                } else if !isLoading {
                    ContentUnavailableView {
                        Text("Nothing to count yet", comment: "Statistics empty")
                    } description: {
                        Text("Post something and come back.", comment: "Statistics empty detail")
                    }
                }
            }
            .padding(AlohaMetrics.space4)
        }
        .background(palette.background)
        .navigationTitle(Text("Statistics", comment: "Screen title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        Task { await load(fresh: true) }
                    } label: {
                        Label {
                            Text("Count again", comment: "Statistics action")
                        } icon: {
                            Image(systemName: AlohaSymbol.refresh)
                        }
                    }
                    Button {
                        Task { await export() }
                    } label: {
                        Label {
                            Text("Export as CSV", comment: "Statistics action")
                        } icon: {
                            Image(systemName: AlohaSymbol.share)
                        }
                    }
                    .disabled(isExporting)
                } label: {
                    Image(systemName: AlohaSymbol.more)
                }
                .accessibilityLabel(Text("More actions", comment: "Statistics action"))
            }
        }
        .overlay {
            if isLoading && statistics == nil { ProgressView() }
        }
        .sheet(item: Binding(get: { exportURL.map(ExportFile.init) }, set: { exportURL = $0?.url }))
        { file in
            ExportShareSheet(url: file.url)
        }
        .task(id: days) { await load() }
        .refreshable { await load() }
    }

    // MARK: - Sections

    private var windowPicker: some View {
        Picker(selection: $days) {
            ForEach(Self.windows, id: \.days) { window in
                Text(window.title).tag(window.days)
            }
        } label: {
            Text("Window", comment: "Statistics window picker")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func hero(_ statistics: AccountStatistics) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            HStack(spacing: AlohaMetrics.space3) {
                AvatarView(account: session.snapshot.asAccount, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.snapshot.bestDisplayName).font(AlohaType.name)
                    Text(
                        statistics.account.map { "@\($0.acct)" } ?? session.snapshot.qualifiedHandle
                    )
                    .font(AlohaType.meta)
                    .foregroundStyle(palette.tertiaryLabel)
                }
            }
            HStack(spacing: AlohaMetrics.space4) {
                stat(
                    Int(
                        statistics.posts["total"] ?? statistics.posts["count"]
                            ?? Double(statistics.window?.counted ?? 0)),
                    Text("Posts", comment: "Statistics stat"))
                stat(
                    statistics.account?.followers ?? 0,
                    Text("Followers", comment: "Statistics stat"))
                stat(
                    statistics.account?.following ?? 0,
                    Text("Following", comment: "Statistics stat"))
            }
            if let window = statistics.window, window.capped {
                Text(
                    "Counted the most recent ^[\(window.counted) post](inflect: true); older ones are left out.",
                    comment: "Statistics window capped"
                )
                .font(AlohaType.meta)
                .foregroundStyle(palette.secondaryLabel)
            }
        }
        .card(palette)
    }

    private func engagement(_ statistics: AccountStatistics) -> some View {
        let e = statistics.engagement
        let r = statistics.rates
        return VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
            Text("Engagement", comment: "Statistics section").font(AlohaType.section)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: AlohaMetrics.space3)],
                spacing: AlohaMetrics.space3
            ) {
                tile(
                    e["favourites"] ?? e["likes"] ?? 0,
                    Text("Favourites", comment: "Statistics tile"))
                tile(e["boosts"] ?? e["reblogs"] ?? 0, Text("Boosts", comment: "Statistics tile"))
                tile(e["replies"] ?? 0, Text("Replies", comment: "Statistics tile"))
                if let reach = e["reach"] {
                    tile(reach, Text("Estimated reach", comment: "Statistics tile"))
                }
                if let rate = r["engagement"] ?? r["engagement_rate"] {
                    tile(rate, Text("Per follower", comment: "Statistics tile"), asPercent: true)
                }
                if let average = r["average"] ?? r["per_post"] {
                    tile(average, Text("Per post", comment: "Statistics tile"), fraction: true)
                }
                if let silent = e["silent"] {
                    tile(silent, Text("Posts with no reply", comment: "Statistics tile"))
                }
            }
        }
        .card(palette)
    }

    @ViewBuilder
    private func postsByMonth(_ statistics: AccountStatistics) -> some View {
        let rows = statistics.byMonth.sorted
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                Text("Posts by month", comment: "Statistics section").font(AlohaType.section)
                Chart(rows, id: \.key) { row in
                    BarMark(x: .value("Month", monthLabel(row.key)), y: .value("Posts", row.value))
                        .foregroundStyle(palette.accent)
                }
                .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.caption2) } }
                .frame(height: 160)
                .accessibilityLabel(Text("Posts by month", comment: "Statistics section"))
            }
            .card(palette)
        }
    }

    @ViewBuilder
    private func engagementByMonth(_ statistics: AccountStatistics) -> some View {
        let rows = statistics.engagementByMonth.sorted
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                Text("Engagement by month", comment: "Statistics section").font(AlohaType.section)
                Chart(rows, id: \.key) { row in
                    LineMark(
                        x: .value("Month", monthLabel(row.key)), y: .value("Engagement", row.value)
                    )
                    .foregroundStyle(palette.favourite)
                    AreaMark(
                        x: .value("Month", monthLabel(row.key)), y: .value("Engagement", row.value)
                    )
                    .foregroundStyle(palette.favourite.opacity(0.12))
                }
                .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.caption2) } }
                .frame(height: 140)
                .accessibilityLabel(Text("Engagement by month", comment: "Statistics section"))
            }
            .card(palette)
        }
    }

    @ViewBuilder
    private func activity(_ statistics: AccountStatistics) -> some View {
        if let activity = statistics.activity {
            let months = Set(activity.originals.values.keys)
                .union(activity.replies.values.keys).union(activity.boosts.values.keys).sorted()
            if !months.isEmpty {
                VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                    Text("Posts, replies and boosts", comment: "Statistics section").font(
                        AlohaType.section)
                    Chart {
                        ForEach(months, id: \.self) { month in
                            BarMark(
                                x: .value("Month", monthLabel(month)),
                                y: .value("Count", activity.originals[month] ?? 0)
                            )
                            .foregroundStyle(
                                by: .value(
                                    "Kind", String(localized: "Posts", comment: "Statistics series")
                                ))
                            BarMark(
                                x: .value("Month", monthLabel(month)),
                                y: .value("Count", activity.replies[month] ?? 0)
                            )
                            .foregroundStyle(
                                by: .value(
                                    "Kind",
                                    String(localized: "Replies", comment: "Statistics series")))
                            BarMark(
                                x: .value("Month", monthLabel(month)),
                                y: .value("Count", activity.boosts[month] ?? 0)
                            )
                            .foregroundStyle(
                                by: .value(
                                    "Kind",
                                    String(localized: "Boosts", comment: "Statistics series")))
                        }
                    }
                    .chartForegroundStyleScale([
                        String(localized: "Posts", comment: "Statistics series"): palette.accent,
                        String(localized: "Replies", comment: "Statistics series"): palette.mention,
                        String(localized: "Boosts", comment: "Statistics series"): palette.boost,
                    ])
                    .chartXAxis { AxisMarks { _ in AxisValueLabel().font(.caption2) } }
                    .frame(height: 170)
                }
                .card(palette)
            }
        }
    }

    @ViewBuilder
    private func visibility(_ statistics: AccountStatistics) -> some View {
        let rows = statistics.visibility.sorted.filter { $0.value > 0 }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                Text("Who could see them", comment: "Statistics section").font(AlohaType.section)
                let total = rows.reduce(0) { $0 + $1.value }
                ForEach(rows, id: \.key) { row in
                    HStack {
                        visibilityTitle(row.key)
                        Spacer()
                        Text(Int(row.value), format: .number)
                            .fontWeight(.semibold)
                        Text(
                            (total > 0 ? row.value / total : 0),
                            format: .percent.precision(.fractionLength(0))
                        )
                        .foregroundStyle(palette.tertiaryLabel)
                        .frame(width: 44, alignment: .trailing)
                    }
                    .font(.footnote)
                }
            }
            .card(palette)
        }
    }

    @ViewBuilder
    private func consistency(_ statistics: AccountStatistics) -> some View {
        let c = statistics.consistency
        if !c.values.isEmpty {
            VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                Text("Rhythm", comment: "Statistics section").font(AlohaType.section)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), spacing: AlohaMetrics.space3)],
                    spacing: AlohaMetrics.space3
                ) {
                    if let days = c["active_days"] {
                        tile(days, Text("Days with a post", comment: "Statistics tile"))
                    }
                    if let streak = c["longest_streak"] ?? c["streak"] {
                        tile(streak, Text("Longest streak", comment: "Statistics tile"))
                    }
                    if let gap = c["longest_gap"] ?? c["gap"] {
                        tile(gap, Text("Longest quiet spell", comment: "Statistics tile"))
                    }
                }
            }
            .card(palette)
        }
    }

    @ViewBuilder
    private func namedCounts(_ title: Text, _ rows: [NamedCount], prefix: String = "") -> some View
    {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                title.font(AlohaType.section)
                ForEach(rows.prefix(12)) { row in
                    HStack {
                        Text(prefix + row.name)
                            .lineLimit(1)
                        Spacer()
                        Text(row.count, format: .number)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .font(.footnote)
                }
            }
            .card(palette)
        }
    }

    @ViewBuilder
    private func partners(_ statistics: AccountStatistics) -> some View {
        if let partners = statistics.partners,
            !(partners.inbound.isEmpty && partners.outbound.isEmpty)
        {
            VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                Text("Conversations", comment: "Statistics section").font(AlohaType.section)
                if !partners.inbound.isEmpty {
                    partnerList(
                        Text("Who replies to you", comment: "Statistics subsection"),
                        partners.inbound)
                }
                if !partners.outbound.isEmpty {
                    partnerList(
                        Text("Who you reply to", comment: "Statistics subsection"),
                        partners.outbound)
                }
            }
            .card(palette)
        }
    }

    private func partnerList(_ title: Text, _ rows: [ConversationPartner]) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
            title.font(.caption.weight(.semibold)).foregroundStyle(palette.secondaryLabel)
            ForEach(rows.prefix(8)) { row in
                HStack {
                    Text(row.account.hasPrefix("@") ? row.account : "@\(row.account)")
                        .lineLimit(1)
                    Spacer()
                    Text(
                        "^[\(row.replies) reply](inflect: true)",
                        comment: "Statistics partner count"
                    )
                    .foregroundStyle(palette.tertiaryLabel)
                }
                .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private func media(_ statistics: AccountStatistics) -> some View {
        let m = statistics.media
        if !m.values.isEmpty {
            VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                Text("Pictures", comment: "Statistics section").font(AlohaType.section)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), spacing: AlohaMetrics.space3)],
                    spacing: AlohaMetrics.space3
                ) {
                    if let pictures = m["pictures"] ?? m["images"] ?? m["with_media"] {
                        tile(pictures, Text("Posts with pictures", comment: "Statistics tile"))
                    }
                    if let described = m["described"] ?? m["with_alt"] ?? m["alt_text"] {
                        tile(described, Text("With a description", comment: "Statistics tile"))
                    }
                    if let share = m["described_share"] ?? m["alt_share"] {
                        tile(share, Text("Described", comment: "Statistics tile"), asPercent: true)
                    }
                }
            }
            .card(palette)
        }
    }

    // MARK: - Pieces

    private func stat(_ value: Int, _ label: Text) -> some View {
        HStack(spacing: 4) {
            Text(value, format: .number.notation(.compactName))
                .fontWeight(.semibold)
                .fontDesign(.rounded)
            label.foregroundStyle(palette.secondaryLabel)
        }
        .font(.footnote)
    }

    private func tile(
        _ value: Double, _ label: Text, asPercent: Bool = false, fraction: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if asPercent {
                    Text(
                        value > 1 ? value / 100 : value,
                        format: .percent.precision(.fractionLength(1)))
                } else if fraction {
                    Text(value, format: .number.precision(.fractionLength(1)))
                } else {
                    Text(Int(value), format: .number.notation(.compactName))
                }
            }
            .font(.title3.weight(.bold))
            .fontDesign(.rounded)
            label
                .font(AlohaType.meta)
                .foregroundStyle(palette.secondaryLabel)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AlohaMetrics.space3)
        .background(
            palette.background,
            in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerSmall, style: .continuous))
    }

    /// "2026-03" → "Mar 26". Anything else is shown as it came.
    private func monthLabel(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count >= 2, let year = Int(parts[0]), let month = Int(parts[1]),
            let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))
        else { return key }
        return date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
    }

    private func visibilityTitle(_ key: String) -> Text {
        switch key {
        case "public": Text("Public", comment: "Visibility")
        case "unlisted": Text("Unlisted", comment: "Visibility")
        case "private", "followers": Text("Followers only", comment: "Visibility")
        case "direct": Text("Direct", comment: "Visibility")
        default: Text(verbatim: key)
        }
    }

    // MARK: - Data

    private func load(fresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        do {
            statistics = try await session.client.decode(
                AccountStatistics.self, from: Endpoint.statistics.overview(days: days, fresh: fresh)
            )
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func export() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let response = try await session.client.send(Endpoint.statistics.export(days: days))
            let url = FileManager.default.temporaryDirectory
                .appending(
                    path:
                        "social-statistics-\(Date.now.formatted(.iso8601.year().month().day())).csv"
                )
            try response.data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}

private struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.path() }
}

/// One share button on a sheet: `ShareLink` needs a view to sit in, and a
/// menu item cannot hold one.
private struct ExportShareSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL

    var body: some View {
        VStack(spacing: AlohaMetrics.space4) {
            Image(systemName: "tablecells")
                .font(.largeTitle)
            Text(url.lastPathComponent)
                .font(AlohaType.name)
            ShareLink(item: url) {
                Label {
                    Text("Save or share", comment: "Statistics export action")
                } icon: {
                    Image(systemName: AlohaSymbol.share)
                }
            }
            .buttonStyle(.borderedProminent)
            Button {
                dismiss()
            } label: {
                Text("Done", comment: "Sheet action")
            }
        }
        .padding(AlohaMetrics.space6)
        .presentationDetents([.medium])
    }
}

extension View {
    fileprivate func card(_ palette: AlohaPalette) -> some View {
        self
            .padding(AlohaMetrics.space4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                palette.surfaceRaised,
                in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium, style: .continuous))
    }
}
