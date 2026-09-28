// SPDX-License-Identifier: MIT

import AlohaNetwork
import AuthenticationServices
import Foundation
import OSLog

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Runs the OAuth web step, with a fallback that does not depend on
/// `ASWebAuthenticationSession` being willing to present.
///
/// Two things went wrong here before. The presentation anchor was
/// `keyWindow`, which — while the sign-in **sheet** is up — is the sheet's own
/// window, so this asked AuthenticationServices to attach a sheet to a sheet.
/// And `start()`'s `false` return was ignored, so a refusal hung the
/// continuation for ever instead of failing.
@MainActor
public final class WebAuthenticator {
    public static let shared = WebAuthenticator()

    private let contextProvider = AnchorProvider()
    private var pending: (state: String, continuation: CheckedContinuation<URL, any Error>)?
    private var session: ASWebAuthenticationSession?
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "webauth")

    private init() {}

    public enum AuthenticationError: Error, Sendable {
        case couldNotPresent
        case cancelled
        case superseded
    }

    public func authenticate(url: URL, state: String) async throws -> URL {
        // A second attempt replaces the first rather than leaking it.
        if let pending {
            pending.continuation.resume(throwing: AuthenticationError.superseded)
            self.pending = nil
        }
        session?.cancel()
        session = nil

        return try await withCheckedThrowingContinuation { continuation in
            self.pending = (state, continuation)

            // **Explicitly `@Sendable`**: the completion is delivered on a
            // background XPC queue, and an actor-isolated closure called from
            // there trips Swift's runtime isolation check and traps.
            let completion: @Sendable (URL?, (any Error)?) -> Void = { callback, error in
                Task { @MainActor in
                    WebAuthenticator.shared.finish(callback: callback, error: error)
                }
            }

            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: RouteResolver.scheme,
                completionHandler: completion)
            // Not ephemeral: reusing an existing Nextcloud session is the
            // difference between one tap and typing a password.
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = contextProvider
            self.session = session

            if !session.start() {
                // It refused — most often because there is no usable anchor.
                // The browser still works, and the callback comes back through
                // the app's URL scheme.
                logger.notice("web authentication session refused to start; using the browser")
                self.session = nil
                openInBrowser(url)
            }
        }
    }

    /// Called from the shell when an `alohasocial://oauth-callback` arrives,
    /// which is how the browser fallback completes.
    @discardableResult
    public func deliver(_ callback: URL) -> Bool {
        guard pending != nil, callback.host() == "oauth-callback" else { return false }
        finish(callback: callback, error: nil)
        return true
    }

    /// Called when the sign-in sheet goes away. Without it, abandoning the
    /// browser half-way leaves the continuation parked for the life of the app.
    public func cancel() {
        session?.cancel()
        session = nil
        guard let pending else { return }
        self.pending = nil
        pending.continuation.resume(throwing: AuthenticationError.cancelled)
    }

    /// Whether a flow is in progress, so the sheet can say it is waiting on the
    /// browser rather than looking stuck.
    public var isAwaitingCallback: Bool { pending != nil }

    private func finish(callback: URL?, error: (any Error)?) {
        guard let pending else { return }
        self.pending = nil
        session = nil

        if let callback {
            pending.continuation.resume(returning: callback)
        } else {
            pending.continuation.resume(throwing: error ?? AuthenticationError.cancelled)
        }
    }

    private func openInBrowser(_ url: URL) {
        #if canImport(UIKit)
            UIApplication.shared.open(url)
        #elseif canImport(AppKit)
            NSWorkspace.shared.open(url)
        #endif
    }
}

/// Supplies the window to present over.
///
/// Never the sign-in sheet, and never a fabricated window: both are ways to
/// crash inside AuthenticationServices.
private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
            let scenes = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            if let window = scene?.keyWindow ?? scene?.windows.first { return window }
            // A window belonging to the scene rather than `UIWindow()`, which
            // is both deprecated and sceneless — and a sceneless anchor is one
            // of the two ways this used to crash.
            if let scene { return ASPresentationAnchor(windowScene: scene) }
            // Unreachable: this is called to present a sheet over the app's own
            // sign-in screen, so there is always a window scene. Saying so
            // plainly beats fabricating the anchor the docblock above warns
            // about (docs/12 §1).
            preconditionFailure("no window scene to present the sign-in sheet over")
        #elseif canImport(AppKit)
            // `keyWindow` is the sheet while the sign-in sheet is up, and
            // attaching a sheet to a sheet is what crashed. Prefer a real
            // top-level window: one that is visible and is not itself attached
            // to a parent.
            let candidates = NSApplication.shared.windows.filter {
                $0.isVisible && $0.parent == nil && !($0 is NSPanel)
            }
            if let main = NSApplication.shared.mainWindow, candidates.contains(main) {
                return main
            }
            if let first = candidates.first { return first }
            // Returning a bare `NSWindow()` here is what made this crash rather
            // than fail; `start()` answering false is the honest outcome, and
            // the caller falls back to the browser.
            return ASPresentationAnchor()
        #else
            return ASPresentationAnchor()
        #endif
    }
}
