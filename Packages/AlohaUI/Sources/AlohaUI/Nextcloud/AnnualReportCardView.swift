// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import Charts
import SwiftUI

/// One card of the year in review. The same view is drawn on screen and,
/// through `ImageRenderer`, into the picture that is shared — so what a
/// follower sees in the shared image is exactly the card that was on screen.
struct AnnualReportCardView: View {
    @Environment(\.alohaPalette) private var palette
    /// The year on the opening card is the picture, not a label: big, but
    /// still following Dynamic Type rather than a fixed size.
    @ScaledMetric(relativeTo: .largeTitle) private var yearSize: CGFloat = 96

    let card: AnnualReportStory.Card
    let report: AnnualReport
    /// A year in review is one's own activity; follower figures are not, and
    /// a reader who turned "Show numbers" off does not want to be compared
    /// (docs/05 §4).
    let showsCounts: Bool
    /// False when drawn into an image: links and buttons there are pictures
    /// of links, and a `NavigationLink` outside a navigation stack draws as
    /// disabled.
    var isInteractive = true
    var onOpen: (Status) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space4) {
            Text(verbatim: String(report.year))
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(card == .opening)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(AlohaMetrics.space5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            // A wash of the server's accent, so a shared card is recognisably
            // this app's and this server's without a logo on it.
            LinearGradient(
                colors: [palette.accent.opacity(0.28), palette.background],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .background(palette.background)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch card {
        case .opening: opening
        case .numbers: numbers
        case .months: months
        case .hashtags(let hashtags): hashtagList(hashtags)
        case .bestPosts(let posts): bestPosts(posts)
        case .closing: closing
        }
    }

    // MARK: - Cards

    private var opening: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space4) {
            Spacer(minLength: 0)
            Text("Your year", comment: "Annual report opening card title")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(palette.secondaryLabel)
            Text(verbatim: String(report.year))
                .font(.system(size: yearSize, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(palette.accent)
            Text(AnnualReportView.archetypeLine(report.data.archetype))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(palette.label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var numbers: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space5) {
            Spacer(minLength: 0)
            bigFigure(
                Text(report.data.totalStatuses, format: .number),
                Text("posts written", comment: "Annual report figure, under a big number"))
            if showsCounts, report.data.totalFollowers > 0 {
                bigFigure(
                    Text(report.data.totalFollowers, format: .number),
                    Text("new followers", comment: "Annual report figure, under a big number"))
            }
            if let busiest = report.data.busiestMonth {
                bigFigure(
                    Text(AnnualReportView.monthName(busiest.month, short: false)),
                    Text("was your busiest month", comment: "Annual report figure, under a month"))
            }
            Spacer(minLength: 0)
        }
    }

    private func bigFigure(_ value: Text, _ label: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(palette.accent)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            label
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(palette.label)
        }
        .accessibilityElement(children: .combine)
    }

    private var months: some View {
        let series = report.data.timeSeries.sorted { $0.month < $1.month }
        return VStack(alignment: .leading, spacing: AlohaMetrics.space4) {
            Text("Month by month", comment: "Annual report section")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(palette.label)
            Chart {
                ForEach(series) { month in
                    BarMark(
                        x: .value(
                            String(localized: "Month", comment: "Chart axis"),
                            AnnualReportView.monthName(month.month)),
                        y: .value(
                            String(localized: "Posts", comment: "Chart axis"), month.statuses)
                    )
                    .foregroundStyle(palette.accent)
                    .cornerRadius(3)
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(minHeight: 180, maxHeight: 320)
            .accessibilityLabel(Text("Posts per month", comment: "Annual report chart"))
            if let busiest = report.data.busiestMonth {
                Text(
                    "Most of it in \(AnnualReportView.monthName(busiest.month, short: false)).",
                    comment: "Annual report chart caption; the argument is a month name"
                )
                .font(.system(.body, design: .rounded))
                .foregroundStyle(palette.secondaryLabel)
            }
            Spacer(minLength: 0)
        }
    }

    private func hashtagList(_ hashtags: [AnnualHashtag]) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
            Text("What you wrote about", comment: "Annual report section")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(palette.label)
            ForEach(hashtags) { hashtag in
                hashtagRow(hashtag)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func hashtagRow(_ hashtag: AnnualHashtag) -> some View {
        let row = HStack(alignment: .firstTextBaseline) {
            Text(verbatim: "#\(hashtag.name)")
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(palette.hashtag)
                .lineLimit(1)
            Spacer(minLength: AlohaMetrics.space2)
            Text(
                "^[\(hashtag.count) post](inflect: true)",
                comment: "Annual report: how many posts used a hashtag"
            )
            .font(AlohaType.meta)
            .monospacedDigit()
            .foregroundStyle(palette.secondaryLabel)
        }
        if isInteractive {
            NavigationLink(value: Route.hashtag(hashtag.name)) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private func bestPosts(_ posts: [AnnualReportStory.BestPost]) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space4) {
            Text("How far they went", comment: "Annual report section")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(palette.label)
            ForEach(posts, id: \.status.id) { post in
                VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                    Self.kindTitle(post.kind)
                        .font(AlohaType.micro)
                        .foregroundStyle(palette.accent)
                    if isInteractive {
                        Button {
                            onOpen(post.status)
                        } label: {
                            excerpt(post.status)
                        }
                        .buttonStyle(.plain)
                    } else {
                        excerpt(post.status)
                    }
                }
                .padding(AlohaMetrics.space3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    palette.surface.opacity(0.85),
                    in: RoundedRectangle(cornerRadius: AlohaMetrics.cornerMedium))
            }
            Spacer(minLength: 0)
        }
    }

    private func excerpt(_ status: Status) -> some View {
        Text(StatusHTMLParser().plainText(status.displayed.content))
            .font(.subheadline)
            .foregroundStyle(palette.label)
            .lineLimit(4)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var closing: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space4) {
            Spacer(minLength: 0)
            Text(
                "That was \(String(report.year)).",
                comment: "Annual report closing card; the argument is a year"
            )
            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
            .foregroundStyle(palette.label)
            Text(
                "Thank you for writing, reading and passing things on.",
                comment: "Annual report closing card detail"
            )
            .font(.system(.title3, design: .rounded))
            .foregroundStyle(palette.secondaryLabel)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    static func kindTitle(_ kind: AnnualReportStory.BestPost.Kind) -> Text {
        switch kind {
        case .boosted: Text("Boosted most", comment: "Annual report best post")
        case .replied: Text("Most replied to", comment: "Annual report best post")
        case .favourited: Text("Favourited most", comment: "Annual report best post")
        }
    }
}
