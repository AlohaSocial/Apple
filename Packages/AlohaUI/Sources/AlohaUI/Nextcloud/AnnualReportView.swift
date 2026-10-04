// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import AlohaNetwork
import Charts
import SwiftUI

/// "Your year": twelve months of what you posted and who arrived, the hashtags
/// you used, and the three posts that travelled furthest.
///
/// Mastodon's `#Wrapstodon`. Nextcloud Social serves it over the API and has no
/// web page of its own for it yet, so this is the first place anybody can read
/// one (docs/05 §9).
///
/// The report is a query rather than a job on this server, so there is nothing
/// to wait for and no spinner that means "generating" — `generate` is still
/// called first, because a server that does need it will act on it and this
/// screen should work against Mastodon too.
public struct AnnualReportView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let session: AccountSession
    private let onAction: (StatusRowAction) -> Void

    @State private var wrapped: WrappedAnnualReports?
    @State private var selectedYear: Int?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadID = UUID()

    public init(session: AccountSession, onAction: @escaping (StatusRowAction) -> Void) {
        self.session = session
        self.onAction = onAction
    }

    private var reports: [AnnualReport] {
        (wrapped?.annualReports ?? []).sorted { $0.year > $1.year }
    }

    private var report: AnnualReport? {
        guard let selectedYear else { return reports.first }
        return reports.first { $0.year == selectedYear }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlohaMetrics.space5) {
                if let errorMessage {
                    VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
                        Label(errorMessage, systemImage: AlohaSymbol.warning)
                            .font(.footnote)
                            .foregroundStyle(palette.destructive)
                        Button {
                            Task { await load() }
                        } label: {
                            Text("Retry", comment: "Annual report retry action")
                        }
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.glass)
                        .disabled(isLoading)
                    }
                }

                if reports.count > 1 { yearPicker }

                if let report {
                    headline(report)
                    monthlyChart(report)
                    hashtags(report)
                    bestPosts(report)
                } else if !isLoading && errorMessage == nil {
                    ContentUnavailableView {
                        Text("No year to look back on yet", comment: "Annual report empty")
                    } description: {
                        Text(
                            "A year you posted in gets a report. Come back once you have written something.",
                            comment: "Annual report empty detail")
                    }
                }
            }
            .padding(AlohaMetrics.space4)
        }
        .background(palette.background)
        .navigationTitle(Text("Your year", comment: "Screen title"))
        .overlay {
            if isLoading && wrapped == nil { ProgressView() }
        }
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var yearPicker: some View {
        if reports.count <= 4 && !dynamicTypeSize.isAccessibilitySize {
            yearSelection.pickerStyle(.segmented).labelsHidden()
        } else {
            yearSelection.pickerStyle(.menu)
        }
    }

    private var yearSelection: some View {
        Picker(selection: Binding(get: { report?.year ?? 0 }, set: { selectedYear = $0 })) {
            ForEach(reports) { report in
                Text(verbatim: String(report.year)).tag(report.year)
            }
        } label: {
            Text("Year", comment: "Annual report year picker")
        }
    }

    private func headline(_ report: AnnualReport) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space2) {
            Text(verbatim: String(report.year))
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(palette.accent)

            Text(Self.archetypeLine(report.data.archetype))
                .font(AlohaType.section)
                .foregroundStyle(palette.label)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)],
                alignment: .leading, spacing: AlohaMetrics.space3) {
                figure(report.data.totalStatuses, Text("Posts", comment: "Annual report figure"))
                figure(
                    report.data.totalFollowers,
                    Text("New followers", comment: "Annual report figure"))
                if let busiest = report.data.busiestMonth {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.monthName(busiest.month))
                            .font(.title3.weight(.semibold))
                        Text("Busiest month", comment: "Annual report figure")
                            .font(AlohaType.micro)
                            .foregroundStyle(palette.secondaryLabel)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AlohaMetrics.space4)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerLarge))
    }

    private func figure(_ value: Int, _ label: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number).font(.title3.weight(.semibold))
            label.font(AlohaType.micro).foregroundStyle(palette.secondaryLabel)
        }
    }

    @ViewBuilder
    private func monthlyChart(_ report: AnnualReport) -> some View {
        let months = report.data.timeSeries.sorted { $0.month < $1.month }
        if months.contains(where: { $0.statuses > 0 || $0.followers > 0 }) {
            VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                Text("Month by month", comment: "Annual report section").font(AlohaType.section)
                Chart {
                    ForEach(months) { month in
                        BarMark(
                            x: .value(
                                String(localized: "Month", comment: "Chart axis"),
                                Self.monthName(month.month)),
                            y: .value(
                                String(localized: "Posts", comment: "Chart axis"), month.statuses)
                        )
                        .foregroundStyle(palette.accent)
                    }
                }
                .frame(height: 180)
                .chartYAxis { AxisMarks(position: .leading) }
                .accessibilityLabel(Text("Month by month", comment: "Annual report section"))

                if months.contains(where: { $0.followers > 0 }) {
                    Text("Who arrived", comment: "Annual report section").font(AlohaType.section)
                    Chart {
                        ForEach(months) { month in
                            LineMark(
                                x: .value(
                                    String(localized: "Month", comment: "Chart axis"),
                                    Self.monthName(month.month)),
                                y: .value(
                                    String(localized: "Followers", comment: "Chart axis"),
                                    month.followers)
                            )
                            .foregroundStyle(palette.boost)
                            .interpolationMethod(.monotone)
                        }
                    }
                    .frame(height: 140)
                    .chartYAxis { AxisMarks(position: .leading) }
                    .accessibilityLabel(Text("Who arrived", comment: "Annual report section"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AlohaMetrics.space4)
            .background(
                palette.surface, in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerLarge))
        }
    }

    @ViewBuilder
    private func hashtags(_ report: AnnualReport) -> some View {
        if !report.data.topHashtags.isEmpty {
            VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                Text("What you wrote about", comment: "Annual report section")
                    .font(AlohaType.section)
                ForEach(report.data.topHashtags) { hashtag in
                    NavigationLink(value: Route.hashtag(hashtag.name)) {
                        HStack {
                            Text(verbatim: "#\(hashtag.name)")
                                .foregroundStyle(palette.hashtag)
                            Spacer()
                            Text(hashtag.count, format: .number)
                                .font(AlohaType.meta)
                                .foregroundStyle(palette.secondaryLabel)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AlohaMetrics.space4)
            .background(
                palette.surface, in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerLarge))
        }
    }

    @ViewBuilder
    private func bestPosts(_ report: AnnualReport) -> some View {
        let top = report.data.topStatuses
        let entries: [(Text, Status)] = [
            (
                Text("Boosted most", comment: "Annual report best post"),
                wrapped?.status(top.byReblogs)
            ),
            (
                Text("Most replied to", comment: "Annual report best post"),
                wrapped?.status(top.byReplies)
            ),
            (
                Text("Liked most", comment: "Annual report best post"),
                wrapped?.status(top.byFavourites)
            ),
        ].compactMap { label, status in status.map { (label, $0) } }

        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
                Text("How far they went", comment: "Annual report section").font(AlohaType.section)
                ForEach(entries, id: \.1.id) { label, status in
                    VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                        label.font(AlohaType.micro).foregroundStyle(palette.secondaryLabel)
                        Button {
                            onAction(.open(status))
                        } label: {
                            Text(StatusHTMLParser().plainText(status.displayed.content))
                                .font(.subheadline)
                                .foregroundStyle(palette.label)
                                .lineLimit(4)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AlohaMetrics.space4)
            .background(
                palette.surface, in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerLarge))
        }
    }

    // MARK: - Words

    /// The archetype in a sentence rather than a bare word: "oracle" on its own
    /// is a label, and the point of the line is to say what the year was like.
    static func archetypeLine(_ archetype: AnnualArchetype) -> String {
        switch archetype {
        case .lurker:
            String(
                localized: "A quiet year — you read more than you wrote.",
                comment: "Annual archetype")
        case .booster:
            String(localized: "A year of passing things on.", comment: "Annual archetype")
        case .pollster:
            String(localized: "A year of asking.", comment: "Annual archetype")
        case .replier:
            String(localized: "A year of answering other people.", comment: "Annual archetype")
        case .oracle:
            String(localized: "A year of writing, and of being read.", comment: "Annual archetype")
        case .unknownCase:
            String(localized: "Your year.", comment: "Annual archetype")
        }
    }

    static func monthName(_ month: Int) -> String {
        let symbols = Calendar.current.shortMonthSymbols
        guard month >= 1, month <= symbols.count else { return String(month) }
        return symbols[month - 1]
    }

    // MARK: - Data

    private func load() async {
        let request = UUID()
        loadID = request
        isLoading = true
        errorMessage = nil
        defer { if loadID == request { isLoading = false } }
        // The server answers instantly and changes nothing; Mastodon needs it.
        _ = try? await session.client.send(
            Endpoint.annualReports.generate(Self.lastCompleteYear))
        guard !Task.isCancelled, loadID == request else { return }
        do {
            let response = try await session.client.decode(
                WrappedAnnualReports.self, from: Endpoint.annualReports.all)
            guard !Task.isCancelled, loadID == request else { return }
            wrapped = response
            if let selectedYear, !response.annualReports.contains(where: { $0.year == selectedYear }) {
                self.selectedYear = nil
            }
            errorMessage = nil
        } catch APIError.notFound {
            guard !Task.isCancelled, loadID == request else { return }
            // A server without the feature is not a broken screen.
            wrapped = WrappedAnnualReports()
            errorMessage = nil
        } catch {
            guard !Task.isCancelled, loadID == request else { return }
            await session.handle(error)
            guard !Task.isCancelled, loadID == request else { return }
            errorMessage = (error as? APIError)?.errorDescription
                ?? String(localized: "Your annual report could not be loaded. Please try again.")
        }
    }

    /// The most recent year there can be a full report for.
    static var lastCompleteYear: Int {
        Calendar.current.component(.year, from: Date()) - 1
    }
}
