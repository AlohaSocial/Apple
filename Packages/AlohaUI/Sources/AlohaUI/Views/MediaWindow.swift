// SPDX-License-Identifier: MIT

import AlohaModels
import SwiftUI

#if os(visionOS)
    /// What a media window shows: a post's pictures and videos, the one to
    /// start on, and whose post it is. Whole attachments rather than ids, so
    /// the window draws at once and outlives the timeline that opened it.
    public struct MediaWindowRequest: Codable, Hashable, Identifiable {
        public var id = UUID()
        public var accountID: UUID?
        public var statusID: String
        public var attachments: [MediaAttachment]
        public var index: Int

        init(_ presentation: MediaPresentation, accountID: UUID?) {
            self.accountID = accountID
            self.statusID = presentation.statusID
            self.attachments = presentation.attachments
            self.index = presentation.index
        }
    }

    /// The media viewer in a window of its own on visionOS, so a video can be
    /// parked in space while reading goes on in the main window (docs/09 §3).
    ///
    /// The same viewer every platform uses, ornament controls and all; only
    /// where it is presented differs. Declared by the app as
    /// `WindowGroup(for: MediaWindowRequest.self)`; the shell opens one where
    /// another platform puts up its full-screen cover.
    public struct MediaWindow: View {
        @Environment(AppEnvironment.self) private var environment

        private let request: MediaWindowRequest?

        public init(request: MediaWindowRequest?) {
            self.request = request
        }

        public var body: some View {
            Group {
                if let request, !environment.isLoading {
                    let session =
                        environment.sessions.first { $0.id == request.accountID }
                        ?? environment.activeSession
                    MediaViewer(
                        attachments: request.attachments,
                        startIndex: request.index,
                        statusID: request.statusID,
                        apiBase: session?.capabilities.apiBase
                            ?? URL(string: "https://invalid.invalid/")!,
                        // The person's setting, as in the cover it replaces.
                        autoplay: session?.settings.autoplayVideo ?? true,
                        session: session)
                } else {
                    ProgressView()
                }
            }
            .alohaTheme(
                environment.theme, metrics: environment.metrics,
                accent: environment.serverAccent
            )
            // A window restored at launch can draw before the accounts have
            // loaded; the load is the process's, once.
            .task { await environment.loadIfNeeded() }
        }
    }
#endif

#if os(macOS)
    /// What a Mac media window shows: a post's pictures and videos, the one to
    /// start on, and whose post it is. Whole attachments rather than ids, so
    /// the window draws at once and outlives the timeline that opened it.
    ///
    /// The Mac's own copy of the visionOS request beside it, kept apart so the
    /// two platforms' windows can change without each other.
    public struct MediaWindowRequest: Codable, Hashable, Identifiable {
        public var id = UUID()
        public var accountID: UUID?
        public var statusID: String
        public var attachments: [MediaAttachment]
        public var index: Int

        init(_ presentation: MediaPresentation, accountID: UUID?) {
            self.accountID = accountID
            self.statusID = presentation.statusID
            self.attachments = presentation.attachments
            self.index = presentation.index
        }
    }

    /// The media viewer in a real window on the Mac (docs/09 §2): resizable,
    /// able to go full screen, and beside the timeline rather than a sheet
    /// locked to it. ← and → move between the post's pictures and Esc closes
    /// the window — the viewer's own keys, which need the focus the window
    /// gives it (`MediaViewer`). Declared by the Mac app as
    /// `WindowGroup(for: MediaWindowRequest.self)`.
    public struct MediaWindow: View {
        @Environment(AppEnvironment.self) private var environment

        private let request: MediaWindowRequest?

        public init(request: MediaWindowRequest?) {
            self.request = request
        }

        public var body: some View {
            let session = environment.session(for: request?.accountID)
            Group {
                if let request, !environment.isLoading,
                    let apiBase = session?.capabilities.apiBase
                {
                    MediaViewer(
                        attachments: request.attachments,
                        startIndex: request.index,
                        statusID: request.statusID,
                        apiBase: apiBase,
                        // The person's setting, as in the sheet it replaces.
                        autoplay: session?.settings.autoplayVideo ?? true,
                        session: session)
                } else {
                    ProgressView()
                        .frame(minWidth: 640, minHeight: 480)
                }
            }
            .navigationTitle(Text("Media", comment: "Mac media window title"))
            .environment(\.windowAccountID, session?.id)
            .alohaTheme(
                environment.theme, metrics: environment.metrics,
                accent: environment.serverAccent(for: session)
            )
            // A window restored at launch can draw before the accounts have
            // loaded; the load is the process's, once.
            .task { await environment.loadIfNeeded() }
        }
    }
#endif
