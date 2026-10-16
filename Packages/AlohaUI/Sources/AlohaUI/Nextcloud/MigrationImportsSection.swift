// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Where the queued imports have got to: each with its progress, and a
/// finished one dismissable. Polled while any of them is still running —
/// `GET /api/v1/migration/imports` is the list the server's own Migration page
/// polls too.
///
/// Shared by Migration and the Bluesky settings, which narrows it to the kind
/// it starts. `reload` is bumped by whoever just queued something.
struct MigrationImportsSection: View {
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession
    /// Only these kinds, or every kind when `nil`.
    var kinds: Set<String>?
    var reload: Int = 0

    @State private var imports: [MigrationImport] = []
    @State private var errorMessage: String?
    @State private var dismissing: Set<String> = []

    private static let pollInterval: Duration = .seconds(3)

    private var shown: [MigrationImport] {
        guard let kinds else { return imports }
        return imports.filter { kinds.contains($0.kind.rawValue) }
    }

    var body: some View {
        Group {
            if !shown.isEmpty || errorMessage != nil {
                Section {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(palette.destructive)
                    }
                    ForEach(shown) { job in
                        row(job)
                    }
                } header: {
                    Text("Imports", comment: "Migration section")
                }
            }
        }
        .task(id: reload) { await poll() }
    }

    private func row(_ job: MigrationImport) -> some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
            HStack {
                Text(MigrationImportText.title(job.kind))
                    .font(AlohaType.name)
                Spacer()
                statusLabel(job)
            }
            if job.status.isActive {
                if let progress = job.progress {
                    ProgressView(value: progress)
                        .accessibilityValue(
                            Text(progress, format: .percent.precision(.fractionLength(0))))
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }
            if job.total > 0 {
                Text(
                    "\(job.done) of \(job.total) done, \(job.skipped) skipped, \(job.failed) failed",
                    comment: "Migration import progress counts"
                )
                .font(AlohaType.meta)
                .foregroundStyle(palette.secondaryLabel)
            }
            if !job.status.isActive {
                ForEach(job.report.log.prefix(5), id: \.self) { line in
                    Text(line)
                        .font(AlohaType.meta)
                        .foregroundStyle(palette.tertiaryLabel)
                }
            }
        }
        .padding(.vertical, AlohaMetrics.space1)
        .swipeActions(edge: .trailing) {
            if !job.status.isActive {
                Button(role: .destructive) {
                    Task { await dismiss(job) }
                } label: {
                    Label {
                        Text("Clear", comment: "Migration import action")
                    } icon: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        // Every swipe has a button too (docs/12 §3).
        .contextMenu {
            if !job.status.isActive {
                Button(role: .destructive) {
                    Task { await dismiss(job) }
                } label: {
                    Label {
                        Text("Clear", comment: "Migration import action")
                    } icon: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func statusLabel(_ job: MigrationImport) -> some View {
        Group {
            switch job.status {
            case .queued: Text("Waiting", comment: "Migration import status")
            case .running: Text("Running", comment: "Migration import status")
            case .done: Text("Done", comment: "Migration import status")
            case .failed: Text("Failed", comment: "Migration import status")
            case .unknown: Text(verbatim: "")
            }
        }
        .font(AlohaType.meta.weight(.semibold))
        .foregroundStyle(job.status == .failed ? palette.destructive : palette.secondaryLabel)
    }

    /// Reads the list, and again every few seconds while something on it is
    /// still running. Cancelled with the view, or when `reload` changes.
    private func poll() async {
        while !Task.isCancelled {
            do {
                imports = try await session.client.decode(
                    MigrationImportList.self, from: Endpoint.migration.imports
                ).imports
                errorMessage = nil
            } catch APIError.notFound {
                // A server without the queue: nothing to show.
                imports = []
                return
            } catch {
                guard !Task.isCancelled else { return }
                await session.handle(error)
                errorMessage = (error as? APIError)?.errorDescription
                return
            }
            guard shown.contains(where: { $0.status.isActive }) else { return }
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    private func dismiss(_ job: MigrationImport) async {
        guard dismissing.insert(job.id).inserted else { return }
        defer { dismissing.remove(job.id) }
        do {
            imports = try await session.client.decode(
                MigrationImportList.self, from: Endpoint.migration.dismissImport(job.id)
            ).imports
        } catch {
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription
        }
    }
}

/// What a queued import is called on screen.
enum MigrationImportText {
    static func title(_ kind: MigrationImport.Kind) -> String {
        switch kind {
        case .follows: String(localized: "People you follow", comment: "Migration list")
        case .blocks: String(localized: "Blocked accounts", comment: "Migration list")
        case .mutes: String(localized: "Muted accounts", comment: "Migration list")
        case .lists: String(localized: "Your lists", comment: "Migration list")
        case .posts: String(localized: "Posts from an archive", comment: "Migration import")
        case .bookmarks: String(localized: "Bookmarks", comment: "Migration list")
        case .domainBlocks: String(localized: "Blocked servers", comment: "Migration list")
        case .moveIn: String(localized: "Moving here", comment: "Migration import kind")
        case .blueskyFollows:
            String(
                localized: "Following who a Bluesky account follows",
                comment: "Migration import kind")
        case .other(let raw): raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
