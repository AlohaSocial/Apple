// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI
import UniformTypeIdentifiers

/// Taking your account with you. A copy whenever you like, a move to another
/// server, or bringing one here — posts and pictures included, and never a
/// private key.
///
/// Its own screen rather than a settings section: this is file handling and
/// a second server, and wants the whole page.
public struct MigrationView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(\.openURL) private var openURL

    private let session: AccountSession

    /// What the file importer was opened for.
    enum ImportKind: Identifiable, Hashable {
        case archive
        case list(MigrationListKind)
        case posts
        case instagram
        var id: String {
            switch self {
            case .archive: "archive"
            case .list(let kind): "list.\(kind.rawValue)"
            case .posts: "posts"
            case .instagram: "instagram"
            }
        }
    }

    @State private var pendingImport: ImportKind?
    /// What the open picker is for, held outside `pendingImport` because the
    /// presentation binding drops that as soon as the picker closes.
    @State private var importKind: ImportKind?
    @State private var busy: Set<String> = []
    @State private var exported: [String: URL] = [:]
    @State private var reports: [String: MigrationReport] = [:]
    @State private var fetchMedia = true
    @State private var videoURL = ""
    @State private var aliases: [String] = []
    @State private var newAlias = ""
    @State private var announcement: MigrationAnnouncement?
    @State private var instagramHandles: [String] = []
    @State private var lookup: [MigrationLookup.Entry] = []
    @State private var followed: Set<String> = []
    @State private var didLookup = false
    @State private var errorMessage: String?
    /// Bumped when something is queued, so the imports list reads again.
    @State private var importsReload = 0
    /// What a queued upload said, by import kind, until the list has it.
    @State private var queued: Set<String> = []

    // Moving here
    @State private var oldHandle = ""
    @State private var candidate: MoveInCandidate?
    @State private var bringFollows = true
    @State private var bringPosts = true
    @State private var finishStatus: MoveInFinishStatus?
    @State private var blueskyAfterMove: BlueskyAfterMove = .deactivate

    // Moving away
    @State private var moveStatus: AccountMoveStatus?
    /// Moving away is a Nextcloud session route; without the app password it
    /// cannot be asked, and the screen says how to get one.
    @State private var canMoveAway = false
    @State private var moveTarget = ""
    @State private var moveConfirm = ""
    @State private var isConfirmingMove = false

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        Form {
            if let errorMessage {
                Section {
                    Label {
                        Text(errorMessage)
                    } icon: {
                        Image(systemName: AlohaSymbol.warning)
                    }
                    .font(.footnote)
                    .foregroundStyle(palette.destructive)
                }
            }

            exportSection
            importSection
            MigrationImportsSection(session: session, reload: importsReload)
            moveHereSection
            moveSection
            moveAwaySection
            instagramSection
        }
        .formStyle(.grouped)
        .alohaGround(palette)
        .navigationTitle(Text("Migration", comment: "Screen title"))
        .fileImporter(
            isPresented: Binding(
                get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            allowedContentTypes: allowedTypes
        ) { result in
            // Dismissing the picker clears `pendingImport` before this runs,
            // so the kind it was opened for is held separately.
            guard let kind = importKind else { return }
            importKind = nil
            pendingImport = nil
            if case .success(let url) = result {
                Task { await upload(kind, from: url) }
            }
        }
        .task { await loadMove() }
        .task { await loadMoving() }
        .confirmationDialog(
            Text("Move this account to \(moveTarget)?", comment: "Move away confirmation title"),
            isPresented: $isConfirmingMove, titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await moveAway() }
            } label: {
                Text("Move my followers", comment: "Move away confirmation action")
            }
        } message: {
            Text(
                "Your followers are told to follow the new account instead, and this one stops posting. Their servers do the rest; it cannot be pushed back by undoing it.",
                comment: "Move away confirmation detail")
        }
    }

    private var allowedTypes: [UTType] {
        switch pendingImport {
        case .list: [.commaSeparatedText, .plainText]
        case .archive, .posts, .instagram: [.zip, .archive, .data]
        case nil: [.data]
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        Section {
            exportRow(
                id: "archive",
                title: Text("Everything, as an archive", comment: "Migration export"),
                symbol: "shippingbox", endpoint: Endpoint.migration.exportArchive,
                filename: "social-archive.zip")
            ForEach(MigrationListKind.allCases) { kind in
                exportRow(
                    id: "list.\(kind.rawValue)", title: listTitle(kind), symbol: "tablecells",
                    endpoint: Endpoint.migration.export(kind),
                    filename: "\(kind.rawValue).csv")
            }
        } header: {
            Text("Take a copy", comment: "Migration section")
        } footer: {
            Text(
                "The archive holds your profile, posts, pictures and videos, and the lists below. It never holds your private key.",
                comment: "Migration export explanation")
        }
    }

    private func exportRow(
        id: String, title: Text, symbol: String, endpoint: Endpoint, filename: String
    ) -> some View {
        HStack {
            Label {
                title
            } icon: {
                Image(systemName: symbol)
            }
            Spacer()
            if busy.contains(id) {
                ProgressView()
            } else if let url = exported[id] {
                ShareLink(item: url) {
                    Label {
                        Text("Save", comment: "Migration export action")
                    } icon: {
                        Image(systemName: AlohaSymbol.share)
                    }
                    .font(.footnote.weight(.semibold))
                }
                .alohaGlassButtonStyle()
                .controlSize(.small)
            } else {
                Button {
                    Task { await download(id: id, endpoint: endpoint, filename: filename) }
                } label: {
                    Text("Prepare", comment: "Migration export action")
                        .font(.footnote.weight(.semibold))
                }
                .alohaGlassButtonStyle()
                .controlSize(.small)
            }
        }
    }

    private func listTitle(_ kind: MigrationListKind) -> Text {
        switch kind {
        case .following: Text("People you follow", comment: "Migration list")
        case .followers: Text("People following you", comment: "Migration list")
        case .blocks: Text("Blocked accounts", comment: "Migration list")
        case .mutes: Text("Muted accounts", comment: "Migration list")
        case .lists: Text("Your lists", comment: "Migration list")
        case .bookmarks: Text("Bookmarks", comment: "Migration list")
        case .domainBlocks: Text("Blocked servers", comment: "Migration list")
        }
    }

    /// Fetched into a temporary file, which is what the share sheet wants.
    private func download(id: String, endpoint: Endpoint, filename: String) async {
        guard busy.insert(id).inserted else { return }
        errorMessage = nil
        defer { busy.remove(id) }
        do {
            let response = try await session.client.send(endpoint)
            guard !Task.isCancelled else { return }
            let folder = FileManager.default.temporaryDirectory
                .appending(path: "aloha-export-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: filename)
            try response.data.write(to: url, options: .atomic)
            exported[id] = url
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "The export could not be prepared. Please try again.")
        }
    }

    // MARK: - Import

    private var importSection: some View {
        Section {
            importRow(
                .archive,
                title: Text("An archive from here or elsewhere", comment: "Migration import"),
                symbol: "shippingbox.and.arrow.backward")
            // Followers are other people's decision: they come with the old
            // server's move, not with a file.
            ForEach(MigrationListKind.allCases.filter { $0.importPath != nil }) { kind in
                importRow(.list(kind), title: listTitle(kind), symbol: "tablecells")
            }
            importRow(
                .posts, title: Text("Posts from an archive", comment: "Migration import"),
                symbol: "doc.text")
            Toggle(isOn: $fetchMedia) {
                Text("Fetch the pictures and videos too", comment: "Migration switch")
            }

            HStack(spacing: AlohaMetrics.space2) {
                TextField(
                    String(
                        localized: "Address of a video elsewhere", comment: "Migration video field"),
                    text: $videoURL
                )
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                #endif
                .autocorrectionDisabled()
                Button {
                    Task { await importVideo() }
                } label: {
                    if busy.contains("video") {
                        ProgressView()
                    } else {
                        Text("Bring it here", comment: "Migration video action")
                            .font(.footnote.weight(.semibold))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(busy.contains("video") || URL(string: videoURL)?.host() == nil)
            }
            if let report = reports["video"] { reportView(report) }
        } header: {
            Text("Bring something here", comment: "Migration section")
        } footer: {
            Text(
                "Lists come as the CSV files Mastodon, Pixelfed, GoToSocial and Akkoma export. Posts and pictures are copied, not linked.",
                comment: "Migration import explanation")
        }
    }

    private func importRow(_ kind: ImportKind, title: Text, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
            HStack {
                Label {
                    title
                } icon: {
                    Image(systemName: symbol)
                }
                Spacer()
                if busy.contains(kind.id) {
                    ProgressView()
                } else {
                    Button {
                        importKind = kind
                        pendingImport = kind
                    } label: {
                        Text("Choose file…", comment: "Migration import action")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            if let report = reports[kind.id] {
                reportView(report)
            } else if queued.contains(kind.id) {
                Text(
                    "Queued — the imports below say how far it has got.",
                    comment: "Migration import queued note"
                )
                .font(AlohaType.meta)
                .foregroundStyle(palette.secondaryLabel)
                .padding(.leading, AlohaMetrics.space5)
            }
        }
    }

    private func reportView(_ report: MigrationReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(report.lines, id: \.key) { line in
                HStack {
                    Text(line.key.replacingOccurrences(of: "_", with: " ").capitalized)
                    Spacer()
                    Text(line.value).fontWeight(.semibold)
                }
            }
            ForEach(report.log.prefix(20), id: \.self) { entry in
                Text(entry)
            }
        }
        .font(AlohaType.meta)
        .foregroundStyle(palette.secondaryLabel)
        .padding(.leading, AlohaMetrics.space5)
    }

    private func upload(_ kind: ImportKind, from url: URL) async {
        guard busy.insert(kind.id).inserted else { return }
        let shouldFetchMedia = fetchMedia
        errorMessage = nil
        defer { busy.remove(kind.id) }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        // Archives can be large. Do not block the UI while reading the file.
        let result = await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url)
        }.result
        guard !Task.isCancelled else { return }
        guard case .success(let data) = result else {
            errorMessage = String(
                localized: "That file couldn't be read.", comment: "Migration import failed")
            return
        }
        let filename = url.lastPathComponent
        let endpoint: Endpoint
        switch kind {
        case .archive: endpoint = .migration.importArchive(data, filename: filename)
        case .list(let list):
            guard let queue = Endpoint.migration.queueImport(list, csv: data, filename: filename)
            else { return }
            endpoint = queue
        case .posts:
            endpoint = .migration.importPosts(
                data, filename: filename, fetchMedia: shouldFetchMedia)
        case .instagram: endpoint = .migration.instagramPeople(data, filename: filename)
        }
        do {
            if case .instagram = kind {
                let handles = try await session.client.decode(MigrationHandles.self, from: endpoint)
                instagramHandles = handles.handles
                lookup = []
                didLookup = false
                if !handles.handles.isEmpty, !(await findPeople()) { return }
            } else {
                recordAnswer(try await session.client.send(endpoint).data, for: kind)
            }
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "The import could not be completed. Please try again.")
        }
    }

    /// A list or posts import is queued now and answers `{"import": …}`; an
    /// older server answers what it did at once. Either is shown.
    private func recordAnswer(_ data: Data, for kind: ImportKind) {
        if let answer = try? AlohaJSON.decoder.decode(MigrationQueued.self, from: data),
            answer.job != nil
        {
            reports[kind.id] = nil
            queued.insert(kind.id)
            importsReload += 1
        } else if let report = try? AlohaJSON.decoder.decode(MigrationReport.self, from: data) {
            queued.remove(kind.id)
            reports[kind.id] = report
        }
    }

    private func importVideo() async {
        guard busy.insert("video").inserted else { return }
        let submittedURL = videoURL
        let shouldFetchMedia = fetchMedia
        errorMessage = nil
        defer { busy.remove("video") }
        do {
            reports["video"] = try await session.client.decode(
                MigrationReport.self,
                from: Endpoint.migration.importVideo(
                    url: submittedURL, fetchMedia: shouldFetchMedia))
            if videoURL == submittedURL { videoURL = "" }
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "The video could not be imported. Please try again.")
        }
    }

    // MARK: - Move

    private var moveSection: some View {
        Section {
            if let announcement {
                VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                    Text("Moving here from another server?", comment: "Migration move heading")
                        .font(AlohaType.name)
                    Text(
                        "On the old server, add this account as an alias, then tell it to move to:",
                        comment: "Migration move explanation"
                    )
                    .font(.footnote)
                    .foregroundStyle(palette.secondaryLabel)
                    HStack {
                        Text(announcement.handle)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        Spacer()
                        ShareLink(item: announcement.address) {
                            Image(systemName: "doc.on.doc")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Share the address", comment: "Migration action"))
                    }
                }
                .padding(.vertical, AlohaMetrics.space1)
            }

            ForEach(aliases, id: \.self) { alias in
                HStack {
                    Label {
                        Text(alias)
                    } icon: {
                        Image(systemName: "arrow.triangle.branch")
                    }
                    Spacer()
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await removeAlias(alias) }
                    } label: {
                        Label {
                            Text("Remove alias \(alias)", comment: "Migration action")
                        } icon: {
                            Image(systemName: "minus.circle")
                        }
                    }
                    .disabled(busy.contains("alias") || busy.contains("alias-load"))
                }
            }

            HStack(spacing: AlohaMetrics.space2) {
                TextField(
                    String(localized: "old@server.example", comment: "Migration alias placeholder"),
                    text: $newAlias
                )
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .onSubmit { Task { await addAlias() } }
                Button {
                    Task { await addAlias() }
                } label: {
                    if busy.contains("alias") {
                        ProgressView()
                    } else {
                        Text("Add alias", comment: "Migration action")
                            .font(.footnote.weight(.semibold))
                    }
                }
                .alohaGlassButtonStyle()
                .controlSize(.small)
                .disabled(
                    busy.contains("alias") || busy.contains("alias-load") || !newAlias.contains("@")
                )
            }
        } header: {
            Text("Move", comment: "Migration section")
        } footer: {
            Text(
                "An alias says another account is also you. It is what lets followers be carried across when one account moves to the other.",
                comment: "Migration alias explanation")
        }
    }

    private func loadMove() async {
        guard !busy.contains("alias"), busy.insert("alias-load").inserted else { return }
        defer { busy.remove("alias-load") }
        if let response = try? await session.client.decode(
            MigrationAliases.self, from: Endpoint.migration.aliases)
        {
            guard !Task.isCancelled else { return }
            aliases = response.aliases
        }
        guard !Task.isCancelled else { return }
        announcement = try? await session.client.decode(
            MigrationAnnouncement.self, from: Endpoint.migration.announcement)
    }

    private func addAlias() async {
        guard !busy.contains("alias"), !busy.contains("alias-load") else { return }
        let submittedDraft = newAlias
        let alias = newAlias.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard alias.contains("@") else { return }
        busy.insert("alias")
        errorMessage = nil
        defer { busy.remove("alias") }
        do {
            aliases = try await session.client.decode(
                MigrationAliases.self, from: Endpoint.migration.addAlias(alias)
            ).aliases
            if newAlias == submittedDraft { newAlias = "" }
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "The alias could not be added. Please try again.")
        }
    }

    private func removeAlias(_ alias: String) async {
        guard !busy.contains("alias-load"), busy.insert("alias").inserted else { return }
        errorMessage = nil
        defer { busy.remove("alias") }
        do {
            aliases = try await session.client.decode(
                MigrationAliases.self, from: Endpoint.migration.removeAlias(alias)
            ).aliases
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "The alias could not be removed. Please try again.")
        }
    }

    // MARK: - Moving here

    /// Moving here from nothing but the old account's handle: it is read off
    /// its own server first, so the person sees who they are about to copy;
    /// then the alias is set and following and posts are queued. When the
    /// old server is Aloha Social too, the last step — telling it to move —
    /// can be started from here.
    private var moveHereSection: some View {
        Section {
            HStack(spacing: AlohaMetrics.space2) {
                TextField(
                    String(localized: "old@server.example", comment: "Move here handle field"),
                    text: $oldHandle
                )
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .onSubmit { Task { await inspect() } }
                Button {
                    Task { await inspect() }
                } label: {
                    if busy.contains("inspect") {
                        ProgressView()
                    } else {
                        Text("Look it up", comment: "Move here action")
                            .font(.footnote.weight(.semibold))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(busy.contains("inspect") || !oldHandle.contains("@"))
            }

            if let candidate {
                candidateCard(candidate)
                Toggle(isOn: $bringFollows) {
                    Text("Follow who it follows", comment: "Move here switch")
                }
                .disabled(!candidate.following.readable)
                Toggle(isOn: $bringPosts) {
                    Text("Bring its public posts over", comment: "Move here switch")
                }
                .disabled(!candidate.posts.readable)
                Button {
                    Task { await moveIn(candidate) }
                } label: {
                    if busy.contains("move-in") {
                        ProgressView()
                    } else {
                        Text("Move here from \(candidate.acct)", comment: "Move here action")
                    }
                }
                .disabled(busy.contains("move-in"))

                if candidate.finishable {
                    Picker(selection: $blueskyAfterMove) {
                        Text("Switch it off", comment: "Bluesky after a move")
                            .tag(BlueskyAfterMove.deactivate)
                        Text("Move it here too", comment: "Bluesky after a move")
                            .tag(BlueskyAfterMove.move)
                        Text("Leave it as it is", comment: "Bluesky after a move")
                            .tag(BlueskyAfterMove.keep)
                    } label: {
                        Text("The old account's Bluesky", comment: "Bluesky after a move picker")
                    }
                    Button {
                        Task { await finishMoveIn(candidate) }
                    } label: {
                        Text(
                            "Tell \(candidate.acct) to move its followers",
                            comment: "Move here finish action")
                    }
                    .disabled(busy.contains("finish"))
                }
            }

            if let finishStatus, finishStatus.status != .none {
                finishStatusRow(finishStatus)
            }
        } header: {
            Text("Move here from another account", comment: "Migration section")
        } footer: {
            Text(
                "Follows and posts are copied a few at a time; the imports above say how far it got. The followers themselves come when the old server is told to move.",
                comment: "Move here explanation")
        }
    }

    private func candidateCard(_ candidate: MoveInCandidate) -> some View {
        HStack(alignment: .top, spacing: AlohaMetrics.space3) {
            RemoteImage(url: candidate.avatar) {
                Circle().fill(Monogram.colour(for: candidate.acct, lightness: 0.46))
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name).font(AlohaType.name)
                Text(verbatim: "@\(candidate.acct)")
                    .font(AlohaType.meta)
                    .foregroundStyle(palette.tertiaryLabel)
                readability(
                    candidate.following,
                    Text(
                        "^[\(candidate.following.total) account](inflect: true) followed",
                        comment: "Move here following count"))
                readability(
                    candidate.posts,
                    Text(
                        "^[\(candidate.posts.total) post](inflect: true)",
                        comment: "Move here posts count"))
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A list the old server keeps hidden answers a count and nothing more;
    /// the export file is the way then, and the screen says so.
    private func readability(_ collection: MoveInCandidate.Collection, _ count: Text) -> some View {
        HStack(spacing: AlohaMetrics.space1) {
            count
            if !collection.readable {
                Text(
                    "· hidden there; use its export file",
                    comment: "Move here list not readable")
            }
        }
        .font(AlohaType.meta)
        .foregroundStyle(collection.readable ? palette.secondaryLabel : palette.tertiaryLabel)
    }

    private func finishStatusRow(_ status: MoveInFinishStatus) -> some View {
        Label {
            switch status.status {
            case .pending:
                Text(
                    "Waiting for \(status.acct) to confirm the move.",
                    comment: "Move here finish pending")
            case .done:
                Text(
                    "\(status.acct) has moved its followers here.",
                    comment: "Move here finish done")
            case .failed:
                Text(
                    status.error.isEmpty
                        ? String(
                            localized: "The move did not finish.",
                            comment: "Move here finish failed")
                        : status.error)
            case .none, .unknown:
                EmptyView()
            }
        } icon: {
            Image(systemName: status.status == .failed ? AlohaSymbol.warning : "arrow.right.circle")
        }
        .font(.footnote)
        .foregroundStyle(status.status == .failed ? palette.destructive : palette.secondaryLabel)
    }

    // MARK: - Moving away

    private var moveAwaySection: some View {
        Section {
            if let moveStatus, moveStatus.hasMoved {
                Label {
                    Text(
                        "This account has moved to \(moveStatus.target?.acct ?? moveStatus.movedTo ?? "").",
                        comment: "Move away done")
                } icon: {
                    Image(systemName: "arrow.right.circle.fill")
                }
                Button(role: .destructive) {
                    Task { await undoMove() }
                } label: {
                    Text("Undo the move", comment: "Move away undo action")
                }
                .disabled(busy.contains("move-away"))
            } else if !canMoveAway {
                Text(
                    "Moving away needs your Nextcloud account connected in Settings, because your server asks for it before anything this final.",
                    comment: "Move away needs Nextcloud connection"
                )
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
            } else if let next = moveStatus?.canMoveAt, next > Date() {
                Text(
                    "This account moved recently. It can move again \(next.formatted(.relative(presentation: .named))).",
                    comment: "Move away cool-down"
                )
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
            } else {
                TextField(
                    String(localized: "new@server.example", comment: "Move away target field"),
                    text: $moveTarget
                )
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                TextField(
                    String(
                        localized: "Type \(ownHandle) to confirm",
                        comment: "Move away confirm field"),
                    text: $moveConfirm
                )
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                Picker(selection: $blueskyAfterMove) {
                    Text("Switch it off", comment: "Bluesky after a move")
                        .tag(BlueskyAfterMove.deactivate)
                    Text("Move it too", comment: "Bluesky after a move")
                        .tag(BlueskyAfterMove.move)
                    Text("Leave it as it is", comment: "Bluesky after a move")
                        .tag(BlueskyAfterMove.keep)
                } label: {
                    Text("Your Bluesky account", comment: "Bluesky after a move picker")
                }
                Button(role: .destructive) {
                    isConfirmingMove = true
                } label: {
                    if busy.contains("move-away") {
                        ProgressView()
                    } else {
                        Text("Move away…", comment: "Move away action")
                    }
                }
                .disabled(
                    busy.contains("move-away") || !moveTarget.contains("@")
                        || moveConfirm.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Move away from here", comment: "Migration section")
        } footer: {
            Text(
                "The new account has to name this one as an alias first. Your followers are moved; your posts stay here, and so does your copy.",
                comment: "Move away explanation")
        }
    }

    /// This account as the server checks the confirmation against:
    /// `user@host`, without the leading `@`.
    private var ownHandle: String {
        String(session.snapshot.qualifiedHandle.drop(while: { $0 == "@" }))
    }

    private func loadMoving() async {
        canMoveAway = await session.client.hasNextcloudAuthorization
        if canMoveAway {
            moveStatus = try? await session.client.decode(
                AccountMoveStatus.self, from: Endpoint.migration.moveStatus)
        }
        finishStatus = try? await session.client.decode(
            MoveInFinishStatus.self, from: Endpoint.migration.moveInFinishStatus)
    }

    private func inspect() async {
        let handle = oldHandle.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard handle.contains("@"), busy.insert("inspect").inserted else { return }
        defer { busy.remove("inspect") }
        errorMessage = nil
        do {
            let found = try await session.client.decode(
                MoveInInspection.self, from: Endpoint.migration.inspectMoveIn(handle: handle)
            ).account
            candidate = found
            bringFollows = found.following.readable
            bringPosts = found.posts.readable
        } catch {
            candidate = nil
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "That account could not be looked up.",
                    comment: "Move here inspect failure")
        }
    }

    private func moveIn(_ candidate: MoveInCandidate) async {
        guard busy.insert("move-in").inserted else { return }
        defer { busy.remove("move-in") }
        errorMessage = nil
        do {
            _ = try await session.client.decode(
                MigrationQueued.self,
                from: Endpoint.migration.moveIn(
                    handle: candidate.acct, follows: bringFollows, posts: bringPosts,
                    fetchMedia: fetchMedia))
            importsReload += 1
            // The alias is set at once; the list above shows it now.
            await loadMove()
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "The move could not be started.",
                    comment: "Move here failure")
        }
    }

    /// The old server is asked to register this one, and the person consents
    /// there in the browser; the outcome is read back here afterwards.
    private func finishMoveIn(_ candidate: MoveInCandidate) async {
        guard busy.insert("finish").inserted else { return }
        defer { busy.remove("finish") }
        errorMessage = nil
        do {
            let start = try await session.client.decode(
                MoveInFinishStart.self,
                from: Endpoint.migration.finishMoveIn(
                    handle: candidate.acct, bluesky: blueskyAfterMove))
            if let url = start.authorizeURL,
                ["https", "http"].contains(url.scheme?.lowercased() ?? "")
            {
                openURL(url)
            }
            finishStatus = try? await session.client.decode(
                MoveInFinishStatus.self, from: Endpoint.migration.moveInFinishStatus)
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "The old server could not be asked to move.",
                    comment: "Move here finish failure")
        }
    }

    private func moveAway() async {
        let target = moveTarget.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard target.contains("@"), busy.insert("move-away").inserted else { return }
        defer { busy.remove("move-away") }
        errorMessage = nil
        do {
            moveStatus = try await session.client.decode(
                AccountMoveStatus.self,
                from: Endpoint.migration.moveAway(
                    to: target, confirm: moveConfirm.trimmingCharacters(in: .whitespaces),
                    bluesky: blueskyAfterMove))
            moveTarget = ""
            moveConfirm = ""
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "The account could not be moved.", comment: "Move away failure")
        }
    }

    private func undoMove() async {
        guard busy.insert("move-away").inserted else { return }
        defer { busy.remove("move-away") }
        errorMessage = nil
        do {
            moveStatus = try await session.client.decode(
                AccountMoveStatus.self, from: Endpoint.migration.undoMove)
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "The move could not be undone.", comment: "Move away undo failure")
        }
    }

    // MARK: - Instagram

    private var instagramSection: some View {
        Section {
            HStack {
                Label {
                    Text("Find people from an Instagram archive", comment: "Migration Instagram")
                } icon: {
                    Image(systemName: "person.2.badge.gearshape")
                }
                Spacer()
                if busy.contains(ImportKind.instagram.id) || busy.contains("find") {
                    ProgressView()
                } else {
                    Button {
                        importKind = .instagram
                        pendingImport = .instagram
                    } label: {
                        Text("Choose file…", comment: "Migration import action")
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if !instagramHandles.isEmpty && !didLookup && !busy.contains("find") {
                Button("Try again") { Task { await findPeople() } }
                    .alohaGlassButtonStyle()
            }
            if !instagramHandles.isEmpty && didLookup && !lookup.contains(where: { $0.found })
                && !busy.contains("find")
            {
                Text(
                    "^[\(instagramHandles.count) handle](inflect: true) found in the archive, none of them on the fediverse yet.",
                    comment: "Migration Instagram no matches"
                )
                .font(.footnote)
                .foregroundStyle(palette.secondaryLabel)
            }

            ForEach(lookup.filter(\.found)) { entry in
                HStack(spacing: AlohaMetrics.space3) {
                    if let account = entry.account {
                        AvatarView(account: account, size: 32)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.account?.bestDisplayName ?? entry.handle)
                            .font(AlohaType.name)
                        Text(verbatim: "@\(entry.handle)")
                            .font(AlohaType.meta)
                            .foregroundStyle(palette.tertiaryLabel)
                    }
                    Spacer()
                    if let account = entry.account {
                        Button {
                            Task { await follow(account) }
                        } label: {
                            if busy.contains("follow.\(account.id)") {
                                ProgressView()
                            } else {
                                (followed.contains(account.id)
                                    ? Text("Following", comment: "Migration follow state")
                                    : Text("Follow", comment: "Migration follow action"))
                                    .font(.footnote.weight(.semibold))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(
                            followed.contains(account.id) || busy.contains("follow.\(account.id)"))
                    }
                }
            }
        } header: {
            Text("People you knew elsewhere", comment: "Migration section")
        } footer: {
            Text(
                "The archive is read for the handles people wrote in their profiles. Nothing from it is kept.",
                comment: "Migration Instagram explanation")
        }
    }

    @discardableResult
    private func findPeople() async -> Bool {
        guard busy.insert("find").inserted else { return false }
        let handles = instagramHandles
        errorMessage = nil
        defer { busy.remove("find") }
        do {
            let response = try await session.client.decode(
                MigrationLookup.self, from: Endpoint.migration.findPeople(handles)
            ).entries
            guard !Task.isCancelled, instagramHandles == handles else { return false }
            lookup = response
            didLookup = true
            return true
        } catch {
            guard !Task.isCancelled, instagramHandles == handles else { return false }
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "People could not be looked up. Please try again.")
            return false
        }
    }

    private func follow(_ account: Account) async {
        let key = "follow.\(account.id)"
        guard !followed.contains(account.id), busy.insert(key).inserted else { return }
        defer { busy.remove(key) }
        errorMessage = nil
        do {
            _ = try await session.client.send(Endpoint.accounts.follow(account.id))
            followed.insert(account.id)
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(localized: "The account could not be followed. Please try again.")
        }
    }
}
