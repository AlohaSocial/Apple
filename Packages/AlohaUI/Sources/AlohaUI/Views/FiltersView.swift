// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The words you would rather not read.
///
/// Mastodon's v2 filters, which is what Nextcloud Social's `FilterController`
/// serves and what its own web client edits: a filter is a title, the places it
/// applies, what it does — warn, which leaves the post in place folded away, or
/// hide, which takes it out of the timeline — an optional expiry, and the words
/// that match. The v1 routes exist on the server too, but a filter of three
/// words is three ids in v1 and one in v2, and an editor that mixed the two
/// would delete the wrong row (docs/05 §9).
///
/// The server applies these when it hands statuses over; the app applies them
/// again locally so a new filter takes effect over cached content immediately,
/// which is why saving refreshes the store as well as the list.
public struct FiltersView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession

    @State private var filters: [Filter] = []
    @State private var isLoading = true
    @State private var editing: FilterDraft?
    @State private var errorMessage: String?

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(palette.destructive)
            }

            Section {
                ForEach(filters) { filter in
                    Button {
                        editing = FilterDraft(filter)
                    } label: {
                        FilterRow(filter: filter)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await delete(filter) }
                        } label: {
                            Label {
                                Text("Delete", comment: "Filter action")
                            } icon: {
                                Image(systemName: AlohaSymbol.delete)
                            }
                        }
                    }
                }

                if filters.isEmpty && !isLoading {
                    Text("Nothing filtered yet.", comment: "Empty filters")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryLabel)
                }

                Button {
                    editing = FilterDraft()
                } label: {
                    Label {
                        Text("New filter", comment: "Filters action")
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
            } header: {
                Text("Filters", comment: "Filters section")
            } footer: {
                Text(
                    "A filter matches the words you give it. Warn folds the post away behind its title; hide takes it out of the timeline altogether.",
                    comment: "Filters explanation")
            }
        }
        .navigationTitle(Text("Filtered words", comment: "Screen title"))
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $editing) { draft in
            FilterEditorView(draft: draft, session: session) {
                Task { await load() }
            }
        }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            filters = try await session.client.decode(
                LossyArray<Filter>.self, from: Endpoint.filters.all
            ).elements
            errorMessage = nil
            try? await session.supportStore.replaceFilters(filters, accountID: session.id)
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func delete(_ filter: Filter) async {
        filters.removeAll { $0.id == filter.id }
        do {
            _ = try await session.client.send(Endpoint.filters.delete(filter.id))
            try? await session.supportStore.replaceFilters(filters, accountID: session.id)
        } catch {
            await session.handle(error)
            await load()
        }
    }
}

// MARK: - One row

private struct FilterRow: View {
    @Environment(\.alohaPalette) private var palette

    let filter: Filter

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: AlohaMetrics.space2) {
                Text(
                    filter.title.isEmpty
                        ? String(localized: "Untitled", comment: "Filter with no title")
                        : filter.title
                )
                .font(AlohaType.name)
                .foregroundStyle(palette.label)
                Spacer()
                Text(actionName)
                    .font(AlohaType.micro)
                    .foregroundStyle(palette.secondaryLabel)
            }

            if !filter.keywords.isEmpty {
                Text(filter.keywords.map(\.keyword).joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                    .lineLimit(2)
            }

            HStack(spacing: AlohaMetrics.space2) {
                if !contexts.isEmpty {
                    Text(contexts)
                        .font(AlohaType.micro)
                        .foregroundStyle(palette.tertiaryLabel)
                }
                if let expiresAt = filter.expiresAt {
                    Text(
                        filter.isExpired()
                            ? String(localized: "Expired", comment: "Filter expiry badge")
                            : String(
                                localized:
                                    "Until \(expiresAt.formatted(date: .abbreviated, time: .shortened))",
                                comment: "Filter expiry badge")
                    )
                    .font(AlohaType.micro)
                    .foregroundStyle(
                        filter.isExpired() ? palette.destructive : palette.tertiaryLabel)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var actionName: String {
        switch filter.filterAction {
        case .hide: String(localized: "Hide", comment: "Filter action name")
        case .blur: String(localized: "Blur", comment: "Filter action name")
        default: String(localized: "Warn", comment: "Filter action name")
        }
    }

    private var contexts: String {
        filter.context.filter { !$0.isUnknown }.map(FilterContextName.of).joined(separator: " · ")
    }
}

enum FilterContextName {
    static func of(_ context: FilterContext) -> String {
        switch context {
        case .home: String(localized: "Home", comment: "Filter context")
        case .notifications: String(localized: "Notifications", comment: "Filter context")
        case .public: String(localized: "Public timelines", comment: "Filter context")
        case .thread: String(localized: "Conversations", comment: "Filter context")
        case .account: String(localized: "Profiles", comment: "Filter context")
        case .unknownCase: ""
        }
    }
}

// MARK: - The editor

/// A filter as the editor holds it, before it is a filter. `id` absent means a
/// new one; `Identifiable` so a sheet can carry it.
struct FilterDraft: Identifiable, Hashable {
    /// The sheet's identity, not the filter's — a new draft needs one too.
    let id = UUID()
    var filterID: String?
    var title: String
    var contexts: Set<FilterContext>
    var action: FilterAction
    var expiry: FilterExpiry
    var keywords: [Keyword]

    struct Keyword: Identifiable, Hashable {
        let id = UUID()
        var serverID: String?
        var text: String
        var wholeWord: Bool
    }

    init() {
        filterID = nil
        title = ""
        contexts = [.home, .public]
        action = .warn
        expiry = .never
        keywords = [Keyword(serverID: nil, text: "", wholeWord: false)]
    }

    init(_ filter: Filter) {
        filterID = filter.id
        title = filter.title
        contexts = Set(filter.context.filter { !$0.isUnknown })
        action = filter.filterAction.isUnknown ? .warn : filter.filterAction
        expiry = FilterExpiry(until: filter.expiresAt)
        keywords = filter.keywords.map {
            Keyword(serverID: $0.id, text: $0.keyword, wholeWord: $0.wholeWord)
        }
        if keywords.isEmpty {
            keywords = [Keyword(serverID: nil, text: "", wholeWord: false)]
        }
    }
}

/// How long a filter lasts. The server takes seconds from now, so a filter
/// being edited keeps whatever is left of its original span rather than being
/// silently renewed.
enum FilterExpiry: Hashable, CaseIterable, Identifiable {
    case never
    case thirtyMinutes
    case oneHour
    case sixHours
    case oneDay
    case oneWeek
    /// What the filter already had, where it is not one of the offered spans.
    case keep(Date)

    static var allCases: [FilterExpiry] {
        [.never, .thirtyMinutes, .oneHour, .sixHours, .oneDay, .oneWeek]
    }

    init(until date: Date?) {
        guard let date else {
            self = .never
            return
        }
        self = .keep(date)
    }

    var id: String {
        switch self {
        case .never: "never"
        case .thirtyMinutes: "30m"
        case .oneHour: "1h"
        case .sixHours: "6h"
        case .oneDay: "1d"
        case .oneWeek: "1w"
        case .keep(let date): "keep-\(date.timeIntervalSince1970)"
        }
    }

    /// Seconds from now, or `nil` for a filter that never expires.
    var seconds: TimeInterval? {
        switch self {
        case .never: nil
        case .thirtyMinutes: 1800
        case .oneHour: 3600
        case .sixHours: 21600
        case .oneDay: 86400
        case .oneWeek: 604_800
        case .keep(let date): max(60, date.timeIntervalSinceNow)
        }
    }

    var name: String {
        switch self {
        case .never: String(localized: "Never", comment: "Filter expiry")
        case .thirtyMinutes: String(localized: "30 minutes", comment: "Filter expiry")
        case .oneHour: String(localized: "1 hour", comment: "Filter expiry")
        case .sixHours: String(localized: "6 hours", comment: "Filter expiry")
        case .oneDay: String(localized: "1 day", comment: "Filter expiry")
        case .oneWeek: String(localized: "1 week", comment: "Filter expiry")
        case .keep(let date):
            String(
                localized: "Until \(date.formatted(date: .abbreviated, time: .shortened))",
                comment: "Filter expiry")
        }
    }
}

struct FilterEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession
    let onSaved: () -> Void

    @State private var draft: FilterDraft
    /// Keywords the editor removed, which have to be sent with `_destroy`
    /// rather than simply left out — the server leaves what it is not told
    /// about alone.
    @State private var removed: [FilterDraft.Keyword] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    private static let editableContexts: [FilterContext] = [
        .home, .notifications, .public, .thread, .account,
    ]

    init(draft: FilterDraft, session: AccountSession, onSaved: @escaping () -> Void) {
        self.session = session
        self.onSaved = onSaved
        _draft = State(initialValue: draft)
    }

    private var isNew: Bool { draft.filterID == nil }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.contexts.isEmpty
            && draft.keywords.contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var expiryChoices: [FilterExpiry] {
        if case .keep = draft.expiry { return [draft.expiry] + FilterExpiry.allCases }
        return FilterExpiry.allCases
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(palette.destructive)
                }

                Section {
                    TextField(
                        text: $draft.title,
                        prompt: Text("What this filter is for", comment: "Filter title prompt")
                    ) {
                        Text("Title", comment: "Filter field")
                    }
                } footer: {
                    Text(
                        "The title is what you see where a post was folded away, so make it something you will recognise.",
                        comment: "Filter title explanation")
                }

                Section {
                    ForEach($draft.keywords) { $keyword in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField(
                                text: $keyword.text,
                                prompt: Text("Word or phrase", comment: "Filter keyword prompt")
                            ) {
                                Text("Word", comment: "Filter field")
                            }
                            #if os(iOS)
                                .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()

                            Toggle(isOn: $keyword.wholeWord) {
                                Text("Whole word only", comment: "Filter keyword option")
                                    .font(.footnote)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                remove(keyword)
                            } label: {
                                Label {
                                    Text("Remove", comment: "Filter keyword action")
                                } icon: {
                                    Image(systemName: AlohaSymbol.delete)
                                }
                            }
                        }
                    }

                    Button {
                        draft.keywords.append(.init(serverID: nil, text: "", wholeWord: false))
                    } label: {
                        Label {
                            Text("Add a word", comment: "Filter action")
                        } icon: {
                            Image(systemName: "plus")
                        }
                    }
                } header: {
                    Text("Words", comment: "Filter section")
                } footer: {
                    Text(
                        "Whole word only stops “art” matching “start”. Leave it off for a phrase.",
                        comment: "Filter whole word explanation")
                }

                Section {
                    ForEach(Self.editableContexts, id: \.self) { context in
                        Toggle(isOn: binding(for: context)) {
                            Text(FilterContextName.of(context))
                        }
                    }
                } header: {
                    Text("Where it applies", comment: "Filter section")
                } footer: {
                    if draft.contexts.isEmpty {
                        Text("Pick at least one.", comment: "Filter context validation")
                            .foregroundStyle(palette.destructive)
                    }
                }

                Section {
                    Picker(selection: $draft.action) {
                        Text("Fold it away", comment: "Filter action choice").tag(FilterAction.warn)
                        Text("Hide it completely", comment: "Filter action choice").tag(
                            FilterAction.hide)
                    } label: {
                        Text("When it matches", comment: "Filter field")
                    }

                    Picker(selection: $draft.expiry) {
                        ForEach(expiryChoices) { choice in
                            Text(choice.name).tag(choice)
                        }
                    } label: {
                        Text("Expires after", comment: "Filter field")
                    }
                } footer: {
                    Text(
                        "A hidden post leaves no trace in the timeline — you will not know it was there. A folded one shows its title and opens when you ask.",
                        comment: "Filter action explanation")
                }
            }
            .navigationTitle(
                isNew
                    ? Text("New filter", comment: "Screen title")
                    : Text("Edit filter", comment: "Screen title")
            )
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel", comment: "Sheet action")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save", comment: "Sheet action")
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
    }

    private func binding(for context: FilterContext) -> Binding<Bool> {
        Binding(
            get: { draft.contexts.contains(context) },
            set: { isOn in
                if isOn {
                    draft.contexts.insert(context)
                } else {
                    draft.contexts.remove(context)
                }
            })
    }

    private func remove(_ keyword: FilterDraft.Keyword) {
        draft.keywords.removeAll { $0.id == keyword.id }
        // Only one the server knows about needs telling.
        if keyword.serverID != nil { removed.append(keyword) }
        if draft.keywords.isEmpty {
            draft.keywords = [.init(serverID: nil, text: "", wholeWord: false)]
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let title = draft.title.trimmingCharacters(in: .whitespaces)
        let contexts = Self.editableContexts.filter { draft.contexts.contains($0) }
        var drafts: [Endpoint.filters.KeywordDraft] = draft.keywords
            .map { ($0, $0.text.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.1.isEmpty }
            .map { .init(id: $0.0.serverID, keyword: $0.1, wholeWord: $0.0.wholeWord) }
        drafts += removed.map {
            .init(id: $0.serverID, keyword: $0.text, wholeWord: $0.wholeWord, destroy: true)
        }

        let endpoint =
            if let filterID = draft.filterID {
                Endpoint.filters.update(
                    filterID, title: title, context: contexts, action: draft.action,
                    expiresIn: draft.expiry.seconds, keywords: drafts)
            } else {
                Endpoint.filters.create(
                    title: title, context: contexts, action: draft.action,
                    expiresIn: draft.expiry.seconds, keywords: drafts)
            }

        do {
            _ = try await session.client.send(endpoint)
            onSaved()
            dismiss()
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
