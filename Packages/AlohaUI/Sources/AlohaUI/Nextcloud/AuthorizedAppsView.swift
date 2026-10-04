// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

/// The applications holding a key to your account, and the door out.
public struct AuthorizedAppsView: View {
    @Environment(\.alohaPalette) private var palette

    private let session: AccountSession

    @State private var apps: [AuthorizedApp] = []
    @State private var isLoading = true
    @State private var revoking: AuthorizedApp?
    @State private var errorMessage: String?

    public init(session: AccountSession) {
        self.session = session
    }

    public var body: some View {
        List {
            if let errorMessage {
                errorRow(errorMessage)
            }

            ForEach(apps) { app in
                row(app)
            }

            if apps.isEmpty && !isLoading && errorMessage == nil {
                ContentUnavailableView {
                    Text("No apps", comment: "Empty authorized apps")
                } description: {
                    Text(
                        "No authorized applications were returned by your server.",
                        comment: "Empty authorized apps detail")
                }
            }
        }
        .alohaGround(palette)
        .navigationTitle(Text("Authorized apps", comment: "Screen title"))
        .overlay {
            if isLoading && apps.isEmpty { ProgressView() }
        }
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            revoking.map { Text("Sign \($0.name) out?", comment: "Revoke app confirmation title") }
                ?? Text(verbatim: ""),
            isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let app = revoking { Task { await revoke(app) } }
                revoking = nil
            } label: {
                Text("Revoke access", comment: "Revoke app action")
            }
            Button(role: .cancel) {
                revoking = nil
            } label: {
                Text("Cancel", comment: "Revoke app action")
            }
        } message: {
            Text(
                "This app will lose access to your account. You can authorize it again by signing in.",
                comment: "Revoke app confirmation detail")
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: AlohaMetrics.space2) {
            Image(systemName: AlohaSymbol.warning)
                .accessibilityHidden(true)
            Text(message).font(.footnote)
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Text("Retry", comment: "Authorized apps retry action")
            }
            .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(palette.destructive)
    }

    private func row(_ app: AuthorizedApp) -> some View {
        HStack(alignment: .top, spacing: AlohaMetrics.space3) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.title3)
                .foregroundStyle(palette.accent)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AlohaMetrics.space1) {
                Text(
                    app.name.isEmpty
                        ? String(localized: "Unnamed app", comment: "App without a name") : app.name
                )
                .font(AlohaType.name)
                if let website = app.website {
                    Link(destination: website) {
                        Text(website.host() ?? website.absoluteString)
                            .font(AlohaType.meta)
                            .lineLimit(1)
                    }
                }
                if let signedIn = app.signedIn ?? app.createdAt {
                    Text(
                        "Signed in \(signedIn, format: .relative(presentation: .named))",
                        comment: "Authorized app sign-in time"
                    )
                    .font(AlohaType.meta)
                    .foregroundStyle(palette.secondaryLabel)
                }
                if let lastUsed = app.lastUsedAt {
                    Text(
                        "Last used \(lastUsed, format: .relative(presentation: .named))",
                        comment: "Authorized app last use"
                    )
                    .font(AlohaType.meta)
                    .foregroundStyle(palette.secondaryLabel)
                }
                if !app.scopes.isEmpty {
                    Text(app.scopes.joined(separator: " · "))
                        .font(AlohaType.micro)
                        .foregroundStyle(palette.tertiaryLabel)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Button(role: .destructive) {
                revoking = app
            } label: {
                Text("Revoke", comment: "Authorized app action")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(Text("Revoke \(app.name)", comment: "Authorized app action"))
        }
        .padding(.vertical, AlohaMetrics.space1)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            apps = try await session.client.decode(
                LossyArray<AuthorizedApp>.self, from: Endpoint.authorizedApps.all
            ).elements
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? String(localized: "Authorized apps could not be loaded. Please try again.")
        }
    }

    private func revoke(_ app: AuthorizedApp) async {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps.remove(at: index)
        do {
            _ = try await session.client.send(Endpoint.authorizedApps.revoke(app.id))
        } catch {
            if !apps.contains(where: { $0.id == app.id }) {
                apps.insert(app, at: min(index, apps.count))
            }
            await session.handle(error)
            errorMessage = (error as? APIError)?.errorDescription ?? String(localized: "Access could not be revoked. Please try again.")
        }
    }
}
