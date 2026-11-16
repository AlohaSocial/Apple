// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI

/// The switch for syncing drafts through the account's Nextcloud, with what
/// it does and how the last sync went (docs/14 §7). Shown in Settings →
/// Nextcloud once a Nextcloud is connected; before that there is nothing to
/// sync through.
struct DraftSyncSettingsRow: View {
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession

    private var state: DraftSync.State { DraftSync.shared.state(for: session.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
            Toggle(
                isOn: Binding(
                    get: { session.settings.syncsDraftsThroughNextcloud },
                    set: { value in
                        Task {
                            await session.updateSettings { $0.syncsDraftsThroughNextcloud = value }
                            if value { await DraftSync.shared.sync(session) }
                        }
                    })
            ) {
                Label {
                    Text("Sync drafts", comment: "Settings item: sync drafts through Nextcloud")
                } icon: {
                    Image(systemName: "doc.on.doc")
                }
            }

            Text(
                "Keeps your drafts in the Aloha Social/Drafts folder of your Nextcloud, so a post started on one device can be finished on another. Pictures already uploaded go with them.",
                comment: "Settings explanation for syncing drafts through Nextcloud"
            )
            .font(.footnote)
            .foregroundStyle(palette.secondaryLabel)

            if session.settings.syncsDraftsThroughNextcloud {
                status
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if state.isSyncing {
            HStack(spacing: AlohaMetrics.space2) {
                ProgressView().controlSize(.small)
                Text("Syncing drafts…", comment: "Draft sync in progress")
                    .foregroundStyle(palette.secondaryLabel)
            }
        } else if let error = state.lastError {
            Label {
                Text(error)
            } icon: {
                Image(systemName: AlohaSymbol.warning)
            }
            .foregroundStyle(palette.destructive)
        } else if let last = state.lastSyncedAt {
            Text(
                "Last synced \(last.formatted(.relative(presentation: .named)))",
                comment:
                    "Draft sync status. The argument is a relative time, such as '2 minutes ago'."
            )
            .foregroundStyle(palette.secondaryLabel)
        }
    }
}
