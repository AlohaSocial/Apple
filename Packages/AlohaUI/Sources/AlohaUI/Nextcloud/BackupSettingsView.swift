// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The Settings row for Backup to Nextcloud, there only when the server
/// answers for it: it asks `api/v1/social/backup` first and draws nothing on
/// a 404, which is what a stock Mastodon and an older Aloha Social say.
struct BackupSettingsRow: View {
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession

    private enum Availability: Equatable {
        case unknown
        case available(SocialBackup?)
        case unavailable
    }

    @State private var availability: Availability = .unknown

    var body: some View {
        Group {
            if case .available(let backup) = availability {
                NavigationLink {
                    BackupSettingsView(session: session, initial: backup)
                } label: {
                    LabeledContent {
                        if let backup { Text(summary(backup)) }
                    } label: {
                        Label {
                            Text("Backup to Nextcloud", comment: "Settings item")
                        } icon: {
                            Image(systemName: "externaldrive.badge.icloud")
                        }
                    }
                }
            }
        }
        .task(id: session.id) { await probe() }
    }

    private func summary(_ backup: SocialBackup) -> String {
        guard backup.enabled else {
            return String(localized: "Off", comment: "Backup state in the Settings row")
        }
        return BackupSettingsView.frequencyName(backup.frequency)
    }

    private func probe() async {
        guard session.capabilities.isNextcloudSocial else {
            availability = .unavailable
            return
        }
        do {
            let backup = try await session.client.decode(
                SocialBackup.self, from: Endpoint.backup.settings)
            availability = .available(backup)
        } catch APIError.notFound {
            availability = .unavailable
        } catch {
            // Offline, or a hiccup: not an answer about whether the server
            // has backups. The screen asks again and says what went wrong.
            if availability == .unknown { availability = .available(nil) }
        }
    }
}

/// Backup to Nextcloud: whether the server writes a backup of this account
/// into the person's own Files, how often, where, how the last one went, and
/// a button for one now (`api/v1/social/backup`, docs/14 §7).
struct BackupSettingsView: View {
    @Environment(\.alohaPalette) private var palette

    let session: AccountSession

    @State private var backup: SocialBackup?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var isStarting = false
    @State private var errorMessage: String?

    init(session: AccountSession, initial: SocialBackup?) {
        self.session = session
        _backup = State(initialValue: initial)
    }

    var body: some View {
        Form {
            if let backup {
                settingsSection(backup)
                statusSection(backup)
                runSection(backup)
            } else if isLoading {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }

            if let errorMessage {
                Section {
                    Label {
                        Text(errorMessage)
                    } icon: {
                        Image(systemName: AlohaSymbol.warning)
                    }
                    .font(.footnote)
                    .foregroundStyle(palette.destructive)
                    if backup == nil {
                        Button {
                            Task { await load() }
                        } label: {
                            Text("Try again", comment: "Backup settings retry")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .alohaGround(palette)
        .navigationTitle(Text("Backup to Nextcloud", comment: "Screen title"))
        .task { await load() }
        .refreshable { await load() }
        // While a backup is being written, the state is checked now and then
        // so the screen says when it is done.
        .task(id: backup?.running == true) {
            guard backup?.running == true else { return }
            while !Task.isCancelled, backup?.running == true {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await load(quietly: true)
            }
        }
    }

    // MARK: - Sections

    private func settingsSection(_ backup: SocialBackup) -> some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { backup.enabled },
                    set: { value in Task { await save(SocialBackupChange(enabled: value)) } })
            ) {
                Text("Back up automatically", comment: "Backup settings switch")
            }
            .disabled(isSaving)

            Picker(
                selection: Binding(
                    get: { backup.frequency },
                    set: { value in Task { await save(SocialBackupChange(frequency: value)) } })
            ) {
                ForEach(SocialBackup.Frequency.allCases, id: \.self) { frequency in
                    Text(Self.frequencyName(frequency)).tag(frequency)
                }
            } label: {
                Text("How often", comment: "Backup frequency picker")
            }
            .disabled(isSaving || !backup.enabled)

            LabeledContent {
                Text(backup.folder)
                    .multilineTextAlignment(.trailing)
            } label: {
                Text("Folder", comment: "Backup folder label")
            }
        } footer: {
            Text(
                "Your server writes a copy of your posts, follows and settings into this folder of your own Nextcloud, and keeps the newest \(backup.keep).",
                comment: "Backup settings explanation. The argument is how many backups are kept.")
        }
    }

    private func statusSection(_ backup: SocialBackup) -> some View {
        Section {
            LabeledContent {
                if let last = backup.lastBackupAt {
                    Text(last, format: .dateTime.day().month().year().hour().minute())
                } else {
                    Text("Never", comment: "No backup has been made yet")
                }
            } label: {
                Text("Last backup", comment: "Backup status label")
            }

            if backup.enabled, let next = backup.nextBackupAt {
                LabeledContent {
                    Text(next, format: .dateTime.day().month().year().hour().minute())
                } label: {
                    Text("Next backup", comment: "Backup status label")
                }
            }

            if let error = backup.lastError {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("The last backup failed", comment: "Backup error heading")
                            .font(.subheadline.weight(.semibold))
                        Text(error)
                            .font(.footnote)
                    }
                } icon: {
                    Image(systemName: AlohaSymbol.warning)
                }
                .foregroundStyle(palette.destructive)
            }
        } header: {
            Text("Status", comment: "Backup settings section")
        }
    }

    private func runSection(_ backup: SocialBackup) -> some View {
        Section {
            Button {
                Task { await runNow() }
            } label: {
                HStack(spacing: AlohaMetrics.space2) {
                    if backup.running || isStarting {
                        ProgressView()
                        Text("Backing up…", comment: "Backup in progress")
                    } else {
                        Text("Back up now", comment: "Backup action")
                    }
                }
            }
            .disabled(backup.running || isStarting)
        }
    }

    static func frequencyName(_ frequency: SocialBackup.Frequency) -> String {
        switch frequency {
        case .daily: String(localized: "Daily", comment: "Backup frequency")
        case .weekly: String(localized: "Weekly", comment: "Backup frequency")
        }
    }

    // MARK: - Requests

    private func load(quietly: Bool = false) async {
        if !quietly { isLoading = true }
        defer { isLoading = false }
        do {
            backup = try await session.client.decode(
                SocialBackup.self, from: Endpoint.backup.settings)
            errorMessage = nil
        } catch {
            guard !quietly else { return }
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "The backup settings couldn't be loaded.",
                    comment: "Backup settings load failure")
        }
    }

    private func save(_ change: SocialBackupChange) async {
        isSaving = true
        defer { isSaving = false }
        do {
            backup = try await session.client.decode(
                SocialBackup.self, from: Endpoint.backup.update(change))
            errorMessage = nil
        } catch {
            await session.handle(error)
            // 422 carries the server's own reason; anything else, ours.
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "That change couldn't be saved.",
                    comment: "Backup settings save failure")
        }
    }

    private func runNow() async {
        isStarting = true
        defer { isStarting = false }
        do {
            backup = try await session.client.decode(SocialBackup.self, from: Endpoint.backup.run)
            errorMessage = nil
        } catch {
            await session.handle(error)
            errorMessage =
                (error as? APIError)?.errorDescription
                ?? String(
                    localized: "The backup couldn't be started.",
                    comment: "Backup start failure")
        }
    }
}
