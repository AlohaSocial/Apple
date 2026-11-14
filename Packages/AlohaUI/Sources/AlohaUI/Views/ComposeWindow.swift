// SPDX-License-Identifier: MIT

import AlohaDesign
import AlohaModels
import SwiftUI

#if os(macOS)
    /// What a compose window was opened for: the account, and the post it
    /// answers, quotes or redrafts, or the text it starts with.
    ///
    /// The window's value, so it is `Codable` and carries whole posts rather
    /// than ids: a reply window has to show what it answers without asking the
    /// server first, and must not depend on the main window still holding it.
    /// Every request is a fresh identity — two New Posts are two windows, not
    /// the first one brought forward.
    public struct ComposeWindowRequest: Codable, Hashable, Identifiable {
        public var id = UUID()
        /// Whose post this is. `nil` is the active account at the moment the
        /// window opens.
        public var accountID: UUID?
        public var replyTo: Status?
        public var quoting: Status?
        public var redraft: Redraft?
        public var draftText: String

        public struct Redraft: Codable, Hashable {
            public var status: Status
            public var source: StatusSource
        }

        public init(accountID: UUID? = nil, draftText: String = "") {
            self.accountID = accountID
            self.draftText = draftText
        }

        /// What the shell would have put up as a sheet.
        init(_ presentation: ComposerPresentation, accountID: UUID?) {
            self.accountID = accountID
            self.replyTo = presentation.replyTo
            self.quoting = presentation.quoting
            self.redraft = presentation.redraft.map {
                Redraft(status: $0.status, source: $0.source)
            }
            self.draftText = presentation.draftText
        }
    }

    /// The composer in a window of its own on the Mac (docs/09 §2).
    ///
    /// A sheet put the whole main window behind the post being written, so a
    /// reply could not be written while reading the thread it answers. Mail
    /// opens a message in a window; so does this, and the timeline stays
    /// usable beside it. Declared by the Mac app as
    /// `WindowGroup(for: ComposeWindowRequest.self)`; the shell opens one
    /// wherever another platform would present the sheet.
    ///
    /// Closing the window is one more way out of the composer, and it keeps
    /// what was written exactly as the sheet's other ways out do: the
    /// composer saves its draft whenever it goes without posting.
    public struct ComposeWindow: View {
        @Environment(AppEnvironment.self) private var environment
        @Environment(\.dismissWindow) private var dismissWindow

        private let request: ComposeWindowRequest?
        /// The account this window settled on when it first drew. The
        /// composer belongs to it even if the main window switches account
        /// while it is open.
        @State private var accountID: UUID?

        public init(request: ComposeWindowRequest?) {
            self.request = request
        }

        public var body: some View {
            content
                .alohaTheme(
                    environment.theme, metrics: environment.metrics,
                    accent: environment.serverAccent
                )
                .frame(minWidth: 520, idealWidth: 680, minHeight: 440, idealHeight: 640)
                // The window can be the first thing to open — a Dock menu
                // item or a service in an app with every window closed — and
                // the accounts are the process's to load, once.
                .task { await environment.loadIfNeeded() }
                .onChange(of: environment.isLoading, initial: true) { _, isLoading in
                    guard !isLoading, accountID == nil else { return }
                    accountID = request?.accountID ?? environment.activeSession?.id
                }
        }

        @ViewBuilder
        private var content: some View {
            if environment.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let request, let session {
                composer(request, session: session)
                    // The composer's own ending closes this window: `dismiss`
                    // belongs to a presentation, and there is none here.
                    .composerHost { _ in dismissWindow() }
                    .id(session.id)
            } else {
                ContentUnavailableView {
                    Text("No account to post from", comment: "Compose window without an account")
                } description: {
                    Text(
                        "Sign in in the main window, then start a new post.",
                        comment: "Compose window without an account, detail")
                }
            }
        }

        private var session: AccountSession? {
            guard let accountID else { return nil }
            return environment.sessions.first { $0.id == accountID }
        }

        @ViewBuilder
        private func composer(
            _ request: ComposeWindowRequest, session: AccountSession
        )
            -> some View
        {
            if let redraft = request.redraft {
                ComposerView(session: session, redrafting: redraft.status, source: redraft.source)
            } else {
                ComposerView(
                    session: session, replyTo: request.replyTo, quoting: request.quoting,
                    prefilledText: request.draftText)
            }
        }
    }
#endif
