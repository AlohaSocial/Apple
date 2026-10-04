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

    private let session: AccountSession

    /// What the file importer was opened for.
    enum ImportKind: Identifiable, Hashable {
        case archive
        case list(Endpoint.migration.ListKind)
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
    @State private var errorMessage: String?

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
            moveSection
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
            ForEach(Endpoint.migration.ListKind.allCases, id: \.self) { kind in
                exportRow(
                    id: "list.\(kind.rawValue)", title: listTitle(kind), symbol: "tablecells",
                    endpoint: Endpoint.migration.exportList(kind),
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
                .buttonStyle(.glass)
                .controlSize(.small)
            } else {
                Button {
                    Task { await download(id: id, endpoint: endpoint, filename: filename) }
                } label: {
                    Text("Prepare", comment: "Migration export action")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
    }

    private func listTitle(_ kind: Endpoint.migration.ListKind) -> Text {
        switch kind {
        case .following: Text("People you follow", comment: "Migration list")
        case .followers: Text("People following you", comment: "Migration list")
        case .blocks: Text("Blocked accounts", comment: "Migration list")
        case .mutes: Text("Muted accounts", comment: "Migration list")
        case .lists: Text("Your lists", comment: "Migration list")
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
            errorMessage = (error as? APIError)?.errorDescription
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
            ForEach(Endpoint.migration.ListKind.allCases, id: \.self) { kind in
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
            if let report = reports[kind.id] { reportView(report) }
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
        case .list(let list): endpoint = .migration.importList(list, csv: data, filename: filename)
        case .posts:
            endpoint = .migration.importPosts(data, filename: filename, fetchMedia: shouldFetchMedia)
        case .instagram: endpoint = .migration.instagramPeople(data, filename: filename)
        }
        do {
            if case .instagram = kind {
                let handles = try await session.client.decode(MigrationHandles.self, from: endpoint)
                instagramHandles = handles.handles
                lookup = []
                if !handles.handles.isEmpty { await findPeople() }
            } else {
                reports[kind.id] = try await session.client.decode(
                    MigrationReport.self, from: endpoint)
            }
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
                ?? String(localized: "The import could not be completed. Please try again.")
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
                from: Endpoint.migration.importVideo(url: submittedURL, fetchMedia: shouldFetchMedia))
            if videoURL == submittedURL { videoURL = "" }
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
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
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(busy.contains("alias") || busy.contains("alias-load") || !newAlias.contains("@"))
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
            MigrationAliases.self, from: Endpoint.migration.aliases) {
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
            errorMessage = (error as? APIError)?.errorDescription
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
            errorMessage = (error as? APIError)?.errorDescription
                ?? String(localized: "The alias could not be removed. Please try again.")
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

            if !instagramHandles.isEmpty && lookup.isEmpty && !busy.contains("find") {
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
                            (followed.contains(account.id)
                                ? Text("Following", comment: "Migration follow state")
                                : Text("Follow", comment: "Migration follow action"))
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(followed.contains(account.id))
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

    private func findPeople() async {
        busy.insert("find")
        defer { busy.remove("find") }
        do {
            lookup = try await session.client.decode(
                MigrationLookup.self, from: Endpoint.migration.findPeople(instagramHandles)
            ).entries
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }

    private func follow(_ account: Account) async {
        do {
            _ = try await session.client.send(Endpoint.accounts.follow(account.id))
            followed.insert(account.id)
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}
