// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaHTML
import AlohaModels
import SwiftUI

#if os(iOS)
    import SafariServices
#endif

/// How long a post takes to read, said the way a magazine says it.
enum ReadingTime {
    /// Words a minute for reading on a screen: the commonly quoted adult
    /// average, rounded down a little, because an estimate that runs short
    /// is the one that annoys.
    static let wordsPerMinute = 230

    static func words(in text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .localized]) {
            _, _, _, _ in count += 1
        }
        return count
    }

    /// Whole minutes, never fewer than one.
    static func minutes(forWords words: Int) -> Int {
        max(1, Int((Double(words) / Double(wordsPerMinute)).rounded()))
    }

    /// Whether a post is long enough for the reader to be worth offering: a
    /// couple of paragraphs, or a link to read. A three-line post is already
    /// as calm as it gets.
    static func suitsReader(_ status: Status) -> Bool {
        let post = status.displayed
        if post.card?.url != nil { return true }
        // The markup is a fair stand-in for length here: this runs in menus,
        // where a parse per post is not worth it, and only decides whether
        // to offer the item.
        return post.content.count >= longPostCharacters
    }

    static let longPostCharacters = 700
}

/// Reader preferences, for this device: a serif face and a text size on top
/// of Dynamic Type.
///
/// The size is a step up or down from the system's own Dynamic Type size
/// rather than a number of points, so it moves with Dynamic Type instead of
/// overriding it, and an accessibility size stays one.
enum ReaderPreferences {
    static let serifKey = "aloha.reader.serif"
    static let stepKey = "aloha.reader.textStep"
    static let steps = -2...4

    /// The size `step` away from `base`, within the sizes the system has.
    static func size(_ base: DynamicTypeSize, step: Int) -> DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        guard let index = all.firstIndex(of: base) else { return base }
        let clamped = min(max(index + step, all.startIndex), all.index(before: all.endIndex))
        return all[clamped]
    }
}

/// A calm page for one long post or one shared link: the words in a single
/// reading column, a little larger and further apart than in the timeline,
/// with how long they take to read, and the link — if there is one — as a
/// card that opens the article in Safari's own Reader.
///
/// It builds on what the app already has rather than beside it: the post's
/// text is the timeline's own rich text (`RichTextView`) with reader metrics,
/// as News mode uses; the link is the card the server built. The article
/// itself is not fetched and re-laid out here — Safari's Reader does that
/// properly, and a second, worse extractor in the app would be a promise it
/// could not keep.
struct ReaderView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.dynamicTypeSize) private var systemSize
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let status: Status
    let session: AccountSession
    /// A link in the post: the shell opens mentions, hashtags and fediverse
    /// posts in the app and anything else in the browser.
    var followLink: ((RichText.Link) -> Void)?

    @AppStorage(ReaderPreferences.serifKey) private var serif = true
    @AppStorage(ReaderPreferences.stepKey) private var step = 1
    @State private var isSpoilerRevealed = false
    @State private var words: Int?
    #if os(iOS)
        @State private var article: ArticleLink?
    #endif

    private var post: Status { status.displayed }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AlohaMetrics.space5) {
                    byline
                    if post.hasContentWarning && !isSpoilerRevealed {
                        warning
                    } else {
                        RichTextView(status: status, isSelectable: true) { link in
                            if let followLink {
                                followLink(link)
                            } else if case .web(let url) = link {
                                LinkOpening.open(url, with: openURL)
                            }
                        }
                        .environment(\.alohaMetrics, metrics)
                        if let card = post.card, let url = card.url {
                            articleCard(card, url: url)
                        }
                    }
                }
                .padding(.horizontal, AlohaMetrics.space5)
                .padding(.vertical, AlohaMetrics.space5)
                // One comfortable column: past about seventy characters a
                // line the eye loses its way back to the next one.
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .dynamicTypeSize(ReaderPreferences.size(systemSize, step: step))
            .alohaGround(palette)
            .navigationTitle(Text("Reader", comment: "Reader view title"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", comment: "Sheet action")
                    }
                }
                ToolbarItem(placement: .primaryAction) { preferencesMenu }
            }
            .task(id: post.content) {
                let text = StatusHTMLParser().plainText(post.content)
                words = ReadingTime.words(in: text)
            }
        }
        #if os(iOS)
            .fullScreenCover(item: $article) { link in
                SafariReader(url: link.url).ignoresSafeArea()
            }
        #endif
        #if os(macOS)
            .frame(minWidth: 560, idealWidth: 680, minHeight: 600, idealHeight: 760)
        #endif
    }

    /// The reader's own metrics: serif or not, as chosen here, and more air
    /// between the lines than a timeline row can spend.
    private var metrics: AlohaMetrics {
        AlohaMetrics(density: .spacious, lineSpacing: 6, useSerifBody: serif)
    }

    private var byline: some View {
        HStack(spacing: AlohaMetrics.space3) {
            AvatarView(account: post.account, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: post.account.bestDisplayName)
                    .font(.headline)
                    .foregroundStyle(palette.label)
                HStack(spacing: AlohaMetrics.space1) {
                    Text(post.createdAt, format: .dateTime.day().month().year())
                    if let words, words > 0 {
                        Text(verbatim: "·").accessibilityHidden(true)
                        Text(
                            "\(ReadingTime.minutes(forWords: words)) min read",
                            comment: "Reader view: estimated reading time in minutes")
                    }
                }
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var warning: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
            Label {
                Text(verbatim: post.spoilerText)
            } icon: {
                Image(systemName: AlohaSymbol.warning)
            }
            .font(.headline)
            .foregroundStyle(palette.label)
            Button {
                isSpoilerRevealed = true
                RevealedContent.shared.setSpoiler(post.id, revealed: true)
            } label: {
                Text("Show post", comment: "Reader view: reveal a post behind a content warning")
            }
            .buttonStyle(.bordered)
        }
        .onAppear {
            isSpoilerRevealed = RevealedContent.shared.isSpoilerRevealed(post.id)
        }
    }

    private func articleCard(_ card: Card, url: URL) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space3) {
            Divider()
            if let provider = card.providerName, !provider.isEmpty {
                Text(verbatim: provider.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryLabel)
            } else if let host = url.host() {
                Text(verbatim: host)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryLabel)
            }
            if !card.title.isEmpty {
                Text(verbatim: card.title)
                    .font(.system(.title3, design: serif ? .serif : .default).weight(.semibold))
                    .foregroundStyle(palette.label)
            }
            if !card.description.isEmpty {
                Text(verbatim: card.description)
                    .font(.system(.body, design: serif ? .serif : .default))
                    .foregroundStyle(palette.secondaryLabel)
                    .lineSpacing(4)
            }
            HStack(spacing: AlohaMetrics.space3) {
                Button {
                    readArticle(url)
                } label: {
                    Label {
                        Text("Read article", comment: "Reader view: open the linked article")
                    } icon: {
                        Image(systemName: "safari")
                    }
                }
                .buttonStyle(.borderedProminent)
                Button {
                    openURL(url)
                } label: {
                    Text("Open in browser", comment: "Reader view: open the link in the browser")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func readArticle(_ url: URL) {
        #if os(iOS)
            let scheme = url.scheme?.lowercased()
            if scheme == "https" || scheme == "http" {
                article = ArticleLink(url: url)
                return
            }
        #endif
        openURL(url)
    }

    private var preferencesMenu: some View {
        Menu {
            Toggle(isOn: $serif) {
                Text("Serif", comment: "Reader view: serif typeface switch")
            }
            ControlGroup {
                Button {
                    step = max(step - 1, ReaderPreferences.steps.lowerBound)
                } label: {
                    Label {
                        Text("Smaller text", comment: "Reader view: decrease text size")
                    } icon: {
                        Image(systemName: "textformat.size.smaller")
                    }
                }
                .disabled(step <= ReaderPreferences.steps.lowerBound)
                Button {
                    step = min(step + 1, ReaderPreferences.steps.upperBound)
                } label: {
                    Label {
                        Text("Larger text", comment: "Reader view: increase text size")
                    } icon: {
                        Image(systemName: "textformat.size.larger")
                    }
                }
                .disabled(step >= ReaderPreferences.steps.upperBound)
            }
        } label: {
            Label {
                Text("Text options", comment: "Reader view: typography menu")
            } icon: {
                Image(systemName: "textformat.size")
            }
        }
    }
}

#if os(iOS)
    /// A link to open in Safari's Reader, by identity for the cover.
    private struct ArticleLink: Identifiable {
        let id = UUID()
        let url: URL
    }

    /// Safari's in-app browser, opening straight into Reader where the page
    /// has an article Reader can find.
    private struct SafariReader: UIViewControllerRepresentable {
        let url: URL

        func makeUIViewController(context: Context) -> SFSafariViewController {
            let configuration = SFSafariViewController.Configuration()
            configuration.entersReaderIfAvailable = true
            return SFSafariViewController(url: url, configuration: configuration)
        }

        func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
    }
#endif
