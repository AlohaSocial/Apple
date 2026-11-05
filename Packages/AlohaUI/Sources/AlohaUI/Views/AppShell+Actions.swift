// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import AlohaNetwork
import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// What the shell does with a post row's actions, and with a link that
/// opens the app.
extension ThemedAppShell {
    // MARK: - Actions

    func handle(_ action: StatusRowAction, session: AccountSession) {
        switch action {
        case .open(let status):
            push(.thread(statusID: status.displayed.id))
        case .watch(let status):
            push(.video(statusID: status.displayed.id))
        case .openProfile(let account):
            push(.profile(accountID: account.id))
        case .openMedia(let status, let index):
            mediaPresentation = MediaPresentation(
                statusID: status.id, attachments: status.mediaAttachments, index: index)
        case .reply(let status):
            composing = ComposerPresentation(replyTo: status.displayed)
        case .followLink(let link):
            switch link {
            case .mention(let accountID, let acct, _):
                push(accountID.map { Route.profile(accountID: $0) } ?? .handle(acct))
            case .hashtag(let name, _):
                push(.hashtag(name))
            case .web(let url):
                openURL(url)
            }
        case .openCard(let card):
            if let url = card.url {
                openURL(url)
            }
        case .report(let status):
            reportTarget = ReportTarget(
                account: status.displayed.account,
                status: status.id.isEmpty ? nil : status)
        case .share(let status):
            share(status)

        case .translate(let status):
            Task { await translator.translate(status, session: session) }

        case .edit(let status):
            Task {
                if let source = await StatusActions.source(of: status, session: session) {
                    editing = EditRequest(status: status.displayed, source: source)
                }
            }

        case .delete(let status):
            deleting = status.displayed

        case .redraft(let status):
            Task {
                if let source = await StatusActions.source(of: status, session: session) {
                    composing = ComposerPresentation(
                        redraft: .init(status: status.displayed, source: source))
                }
            }

        case .block(let account):
            confirming = ModerationRequest(account: account, kind: .block)

        case .mute(let account):
            confirming = ModerationRequest(account: account, kind: .mute)

        case .quote(let status):
            composing = ComposerPresentation(quoting: status.displayed)
        case .showDelivery(let status):
            sheet = .delivery(status.displayed)
        case .showEditHistory(let status):
            sheet = .editHistory(status.displayed)
        case .quoteControls(let status):
            sheet = .quoteControls(status.displayed)
        case .tagPeople(let status):
            sheet = .tagPeople(status.displayed)
        case .addToCollection(let status):
            sheet = .addToCollection(status.displayed)
        case .addToList(let account):
            sheet = .addToList(account)

        default:
            Task { await StatusActions.perform(action, session: session) }
        }
    }

    /// The fallback for a `.share` that did not come from a `ShareLink`.
    /// Every button the app draws is a `ShareLink` now (`StatusShareLink`);
    /// this stays correct for anything that still sends the action.
    private func share(_ status: Status) {
        guard let url = status.displayed.url else { return }
        #if canImport(UIKit)
            let activity = UIActivityViewController(
                activityItems: [url], applicationActivities: nil)
            guard
                let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive })?
                    .keyWindow,
                var presenter = window.rootViewController
            else { return }
            // The root is busy while it presents a sheet, and a second
            // presentation from it fails without a word: present from the
            // top of the stack instead.
            while let presented = presenter.presentedViewController { presenter = presented }
            // On iPad the controller is a popover and UIKit raises without an
            // anchor. A centred, arrowless one is honest about having none.
            if let popover = activity.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(
                    x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            presenter.present(activity, animated: true)
        #elseif canImport(AppKit)
            let picker = NSSharingServicePicker(items: [url])
            if let view = NSApplication.shared.keyWindow?.contentView {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
        #endif
    }

    /// Links inside posts and cards open in the browser on every platform.
    /// Without the AppKit branch a tap on a link did nothing on the Mac:
    /// the UIKit-only `open` compiled away and the action fell through
    /// silently, so no web content was reachable from a timeline there.
    private func openURL(_ url: URL) {
        LinkOpening.open(url, with: openURLAction)
    }

    func handle(_ url: URL) {
        // The browser fallback for sign-in comes back this way, and it is not
        // a navigation destination.
        if WebAuthenticator.shared.deliver(url) { return }

        // The composers are presented, not pushed (docs/09 §8): a link asking
        // for one is a request to open the sheet, which is what the
        // quick-compose widget and the Control Center controls do.
        if let presentation = RouteResolver.presentation(for: url) {
            NotificationCenter.default.post(name: presentation.notification, object: nil)
            return
        }

        guard let destination = RouteResolver.destination(for: url) else { return }
        // A Spotlight result or a widget row names its account; the post id
        // in it means nothing under another one.
        if let accountID = destination.accountID { environment.setActiveAccount(accountID) }
        // The same decisions a route from anywhere else gets: a timeline
        // selects its tab, a root destination its tab or row.
        open(destination.route)
    }
}
