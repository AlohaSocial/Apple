// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// Connecting the Nextcloud *underneath* a Social account.
///
/// Signing in to Social gives a token issued by Social's own authorisation
/// server; it is not a Nextcloud session, so it cannot read Files or register
/// for push. Nextcloud's Login Flow v2 gives a real app password that can do
/// both — and the person approves it in their own browser, so this app never
/// sees a password.
public struct NextcloudConnectView: View {
    @Environment(\.alohaPalette) private var palette
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let session: AccountSession

    @State private var phase: Phase = .idle
    @State private var errorMessage: String?
    @State private var connectionTask: Task<Void, Never>?
    @State private var connectionID = UUID()
    @State private var isStarting = false
    @State private var isDisconnecting = false

    enum Phase {
        case idle
        case waiting(NextcloudLoginFlow.Start)
        case connected(NextcloudLoginFlow.Credentials)
    }

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        NavigationStack {
            Form {
                switch phase {
                case .idle: introduction
                case .waiting(let start): waiting(start)
                case .connected(let credentials): connected(credentials)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(palette.destructive)
                    }
                }
            }
            .formStyle(.grouped)
            .alohaGround(palette)
            .navigationTitle(Text("Connect your Nextcloud", comment: "Screen title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Close", comment: "Sheet action")
                    }
                    .disabled(isDisconnecting)
                }
            }
            .task { phase = existingPhase }
            .interactiveDismissDisabled(isDisconnecting)
            .onDisappear { cancelConnection(resetPhase: false) }
        }
    }

    private var existingPhase: Phase {
        if let credentials = (try? environment.credentials.nextcloudCredentials(for: session.id))
            ?? nil
        {
            return .connected(credentials)
        }
        return .idle
    }

    // MARK: - Phases

    private var introduction: some View {
        Group {
            Section {
                Label {
                    Text("Attach files already on your Nextcloud", comment: "Nextcloud benefit")
                } icon: {
                    Image(systemName: "folder")
                }
                Label {
                    Text("Get notifications pushed instead of polled", comment: "Nextcloud benefit")
                } icon: {
                    Image(systemName: AlohaSymbol.notificationsFilled)
                }
            } header: {
                Text("What this adds", comment: "Nextcloud connect section")
            } footer: {
                Text(
                    "Signing in to Social gives this app a Social token, which can't read your files or register for push. Connecting your Nextcloud grants an app password that can — you approve it in your own browser, and this app never sees your password.",
                    comment: "Nextcloud connect explanation")
            }

            Section {
                Button {
                    startConnection()
                } label: {
                    if isStarting {
                        ProgressView()
                    } else {
                        Text(
                            "Connect \(session.snapshot.instanceHost)",
                            comment: "Nextcloud connect action")
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(isStarting)
            }
        }
    }

    private func waiting(_ start: NextcloudLoginFlow.Start) -> some View {
        Section {
            HStack(spacing: AlohaMetrics.space3) {
                ProgressView()
                Text("Waiting for you to approve it…", comment: "Nextcloud connect waiting")
                    .font(.subheadline)
            }

            Button {
                openURL(start.loginURL)
            } label: {
                Text("Open the approval page again", comment: "Nextcloud connect action")
            }
            .buttonStyle(.glass)

            Button(role: .cancel) {
                cancelConnection()
            } label: {
                Text("Cancel", comment: "Nextcloud connect action")
            }
        } footer: {
            Text(
                "Approve the connection in your browser, then come back here.",
                comment: "Nextcloud connect instruction")
        }
    }

    private func connected(_ credentials: NextcloudLoginFlow.Credentials) -> some View {
        Group {
            Section {
                LabeledContent {
                    Text(credentials.loginName)
                } label: {
                    Text("Connected as", comment: "Nextcloud connect state")
                }
                LabeledContent {
                    Text(credentials.server.host() ?? "")
                } label: {
                    Text("Server", comment: "Nextcloud connect state")
                }
            } footer: {
                Text(
                    "Files browsing and push notifications are available for this account.",
                    comment: "Nextcloud connected explanation")
            }

            Section {
                Button(role: .destructive) {
                    Task { await disconnect(credentials) }
                } label: {
                    if isDisconnecting {
                        ProgressView()
                    } else {
                        Text("Disconnect", comment: "Nextcloud connect action")
                    }
                }
                .buttonStyle(.glass)
                .disabled(isDisconnecting)
            } footer: {
                Text(
                    "This revokes the app password on your Nextcloud too.",
                    comment: "Nextcloud disconnect explanation")
            }
        }
    }

    // MARK: - Actions

    private func startConnection() {
        guard !isStarting, connectionTask == nil else { return }
        let request = UUID()
        connectionID = request
        isStarting = true
        connectionTask = Task { await begin(request: request) }
    }

    private func cancelConnection(resetPhase: Bool = true) {
        connectionID = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        isStarting = false
        if resetPhase { phase = .idle }
    }

    private func begin(request: UUID) async {
        defer {
            if connectionID == request {
                connectionTask = nil
                isStarting = false
            }
        }
        errorMessage = nil
        let flow = NextcloudLoginFlow(transport: environment.transport)
        guard let server = URL(string: session.capabilities.apiBase.originString) else {
            errorMessage = String(localized: "The server address is invalid.")
            return
        }

        do {
            let start = try await flow.begin(server: server)
            guard !Task.isCancelled, connectionID == request else { return }
            phase = .waiting(start)
            openURL(start.loginURL)

            let credentials = try await flow.awaitApproval(start)
            guard !Task.isCancelled, connectionID == request else { return }
            try environment.credentials.setNextcloudCredentials(credentials, for: session.id)
            await session.setNextcloudConnection(credentials)
            phase = .connected(credentials)

            // Push is the whole point of connecting, so ask for it now rather
            // than waiting for the next launch.
            await environment.registerForNextcloudPush(session: session)
        } catch NextcloudLoginFlow.FlowError.unsupported {
            guard !Task.isCancelled, connectionID == request else { return }
            // A plain Mastodon server, which is a normal answer.
            errorMessage = String(
                localized:
                    "\(session.snapshot.instanceHost) isn't a Nextcloud, so there's nothing to connect.",
                comment: "Nextcloud connect unsupported")
            phase = .idle
        } catch NextcloudLoginFlow.FlowError.timedOut {
            guard !Task.isCancelled, connectionID == request else { return }
            errorMessage = String(
                localized: "That took too long. Try again when you're ready.",
                comment: "Nextcloud connect timeout")
            phase = .idle
        } catch {
            guard !Task.isCancelled, connectionID == request else { return }
            errorMessage = String(
                localized: "Couldn't connect to your Nextcloud.",
                comment: "Nextcloud connect failure")
            phase = .idle
        }
    }

    private func disconnect(_ credentials: NextcloudLoginFlow.Credentials) async {
        guard !isDisconnecting else { return }
        isDisconnecting = true
        errorMessage = nil
        defer { isDisconnecting = false }
        await environment.unregisterNextcloudPush(session: session)
        await NextcloudLoginFlow(transport: environment.transport).revoke(credentials)
        try? environment.credentials.removeNextcloudCredentials(for: session.id)
        await session.setNextcloudConnection(nil)
        phase = .idle
    }
}
