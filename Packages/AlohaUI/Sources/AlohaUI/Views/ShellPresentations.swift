// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

/// What the composer was opened for.
///
/// A `Bool` plus a separate `replyTo` looked equivalent and was not: the sheet
/// closure could run before the reply target landed, so "Reply" opened an empty
/// new post and the answer was published as a top-level status. Presenting by
/// item keeps the two inseparable.
struct ComposerPresentation: Identifiable {
    let id = UUID()
    var replyTo: Status?
    /// A quote post: the composer opens with this post attached.
    var quoting: Status?
}

/// The smaller sheets a status or an account can put up: one enum, so the
/// shell carries one `@State` for all of them.
enum ShellSheet: Identifiable {
    case delivery(Status)
    case editHistory(Status)
    case quoteControls(Status)
    case tagPeople(Status)
    case addToCollection(Status)
    case addToList(Account)

    var id: String {
        switch self {
        case .delivery(let status): "delivery.\(status.id)"
        case .editHistory(let status): "history.\(status.id)"
        case .quoteControls(let status): "quotes.\(status.id)"
        case .tagPeople(let status): "tag.\(status.id)"
        case .addToCollection(let status): "collection.\(status.id)"
        case .addToList(let account): "list.\(account.id)"
        }
    }
}

/// What the shell can present, gathered in one place.
///
/// Split out because the combined modifier chain became a single expression the
/// type checker could not finish — and because "what can this screen put in
/// front of me" is worth reading on its own.
struct ShellSheets: ViewModifier {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.mediaTransition) private var mediaTransition

    @Binding var isPresentingSignIn: Bool
    @Binding var composing: ComposerPresentation?
    @Binding var reportTarget: ReportTarget?
    @Binding var editing: EditRequest?
    @Binding var mediaPresentation: MediaPresentation?
    @Binding var sheet: ShellSheet?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresentingSignIn) { SignInView() }
            .sheet(item: $composing) { request in
                if let session = environment.activeSession {
                    ComposerView(
                        session: session, replyTo: request.replyTo, quoting: request.quoting)
                }
            }
            .sheet(item: $sheet) { sheet in
                if let session = environment.activeSession {
                    switch sheet {
                    case .delivery(let status):
                        DeliverySheet(status: status, session: session)
                    case .editHistory(let status):
                        EditHistorySheet(status: status, session: session)
                    case .quoteControls(let status):
                        QuoteControlsSheet(status: status, session: session)
                    case .tagPeople(let status):
                        TagPeopleSheet(status: status, session: session)
                    case .addToCollection(let status):
                        CollectionPickerSheet(status: status, session: session)
                    case .addToList(let account):
                        ListMembershipSheet(account: account, session: session)
                    }
                }
            }
            .sheet(item: $reportTarget) { target in
                if let session = environment.activeSession {
                    ReportView(session: session, account: target.account, status: target.status)
                }
            }
            .sheet(item: $editing) { request in
                if let session = environment.activeSession {
                    ComposerView(
                        session: session, editing: request.status, source: request.source)
                }
            }
            .fullScreenCoverIfAvailable(item: $mediaPresentation) { presentation in
                MediaViewer(
                    attachments: presentation.attachments,
                    startIndex: presentation.index,
                    statusID: presentation.statusID,
                    apiBase: environment.activeSession?.capabilities.apiBase
                        ?? URL(string: "https://invalid.invalid/")!,
                    autoplay: environment.activeSession?.settings.autoplayVideo ?? true
                )
                // The photograph grows out of the cell that was tapped and
                // shrinks back into it, rather than cutting.
                .mediaTransitionDestination(
                    id: presentation.attachments[safe: presentation.index]?.id
                        ?? presentation.statusID,
                    in: mediaTransition)
            }
    }
}

/// Deleting, blocking and muting all federate and none can be taken back, so
/// each is confirmed rather than fired straight from a menu tap.
struct ShellAlerts: ViewModifier {
    @Environment(AppEnvironment.self) private var environment

    @Binding var deleting: Status?
    @Binding var confirming: ModerationRequest?

    func body(content: Content) -> some View {
        content
            .alert(
                Text("Delete this post?", comment: "Delete confirmation title"),
                isPresented: Binding(
                    get: { deleting != nil }, set: { if !$0 { deleting = nil } })
            ) {
                Button(role: .destructive) {
                    if let status = deleting, let session = environment.activeSession {
                        Task { await StatusActions.delete(status, session: session) }
                    }
                    deleting = nil
                } label: {
                    Text("Delete", comment: "Delete confirmation action")
                }
                Button(role: .cancel) {
                    deleting = nil
                } label: {
                    Text("Cancel", comment: "Delete confirmation action")
                }
            } message: {
                Text("This can't be undone.", comment: "Delete confirmation detail")
            }
            .alert(
                confirming.map { Text($0.title) } ?? Text(verbatim: ""),
                isPresented: Binding(
                    get: { confirming != nil }, set: { if !$0 { confirming = nil } })
            ) {
                Button(role: .destructive) {
                    if let request = confirming, let session = environment.activeSession {
                        Task { await StatusActions.moderate(request, session: session) }
                    }
                    confirming = nil
                } label: {
                    Text("Confirm", comment: "Moderation confirmation action")
                }
                Button(role: .cancel) {
                    confirming = nil
                } label: {
                    Text("Cancel", comment: "Moderation confirmation action")
                }
            } message: {
                if let request = confirming { Text(request.detail) }
            }
    }
}
