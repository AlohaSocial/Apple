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
