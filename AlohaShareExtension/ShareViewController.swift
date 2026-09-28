// SPDX-License-Identifier: MIT

import AlohaStore
import AlohaUI
import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
    import UIKit

    /// Presents the real composer from `AlohaUI` rather than a reduced one, with
    /// the shared content pre-attached (docs/09 §6).
    ///
    /// The extension has a tight memory budget, so it builds only the account
    /// list it needs and hands the rest to the same views the app uses.
    final class ShareViewController: UIViewController {
        private var environment: AppEnvironment?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            Task { await presentComposer() }
        }

        @MainActor
        private func presentComposer() async {
            let payload = await SharePayload.read(from: extensionContext)

            let environment = AppEnvironment(container: StoreContainer.make())
            self.environment = environment
            await environment.load()

            guard let session = environment.activeSession else {
                showNoAccount()
                return
            }

            let host = UIHostingController(
                rootView: ShareComposerView(
                    session: session,
                    payload: payload,
                    onFinish: { [weak self] in self?.finish() }
                )
                .environment(environment))

            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }

        private func showNoAccount() {
            let host = UIHostingController(
                rootView: ContentUnavailableView {
                    Text("No account yet", comment: "Share extension, no account")
                } description: {
                    Text(
                        "Open Aloha Social and add your server first.",
                        comment: "Share extension, no account detail")
                })
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }

        private func finish() {
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
#endif

#if canImport(UIKit)
    extension NSItemProvider {
        /// `loadItem(forTypeIdentifier:options:)` has no async overload for the
        /// untyped form, so this bridges the completion handler once rather
        /// than at every call site.
        func loadData(_ type: UTType) async -> Data? {
            await withCheckedContinuation { continuation in
                loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
        }

        /// Returns a `String` rather than an `NSSecureCoding`: the protocol is
        /// not `Sendable`, and handing one across the continuation is a data
        /// race the compiler rightly refuses.
        ///
        /// `loadObject(ofClass:)` rather than the deprecated
        /// `loadItem(forTypeIdentifier:options:)`: the typed form is what
        /// replaced it, and it removes the `as?` guessing the untyped one
        /// forced. Which class to ask for follows the type the caller wants —
        /// a URL arrives as a `URL`, everything else as text.
        func loadText(_ type: UTType) async -> String? {
            if type.conforms(to: .url) {
                return await withCheckedContinuation { continuation in
                    _ = loadObject(ofClass: URL.self) { url, _ in
                        continuation.resume(returning: url?.absoluteString)
                    }
                }
            }
            return await withCheckedContinuation { continuation in
                _ = loadObject(ofClass: String.self) { text, _ in
                    continuation.resume(returning: text)
                }
            }
        }
    }
#endif

/// What arrived in the share sheet.
public struct SharePayload: Sendable {
    public var text: String
    public var attachments: [Attachment]

    public struct Attachment: Sendable {
        public var data: Data
        public var filename: String
        public var mimeType: String

        public init(data: Data, filename: String, mimeType: String) {
            self.data = data
            self.filename = filename
            self.mimeType = mimeType
        }
    }

    public init(text: String = "", attachments: [Attachment] = []) {
        self.text = text
        self.attachments = attachments
    }

    #if canImport(UIKit)
        static func read(from context: NSExtensionContext?) async -> SharePayload {
            guard let items = context?.inputItems as? [NSExtensionItem] else {
                return SharePayload()
            }

            var text = ""
            var attachments: [Attachment] = []

            func append(_ line: String) {
                guard !line.isEmpty else { return }
                text += (text.isEmpty ? "" : "\n") + line
            }

            for item in items {
                for provider in item.attachments ?? [] {
                    if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                        let url = await provider.loadText(UTType.url)
                    {
                        append(url)
                        continue
                    }
                    if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                        let value = await provider.loadText(UTType.plainText)
                    {
                        append(value)
                        continue
                    }
                    if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                        if let data = await provider.loadData(UTType.movie) {
                            attachments.append(
                                Attachment(
                                    data: data, filename: "shared-\(UUID().uuidString).mp4",
                                    mimeType: "video/mp4"))
                            continue
                        }
                    }
                    if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        if let data = await provider.loadData(UTType.image) {
                            attachments.append(
                                Attachment(
                                    data: data, filename: "shared-\(UUID().uuidString).jpg",
                                    mimeType: "image/jpeg"))
                        }
                    }
                }
            }

            return SharePayload(text: text, attachments: attachments)
        }
    #endif
}

/// Pre-loads the shared content into the app's own composer.
public struct ShareComposerView: View {
    private let session: AccountSession
    private let payload: SharePayload
    private let onFinish: () -> Void

    public init(session: AccountSession, payload: SharePayload, onFinish: @escaping () -> Void) {
        self.session = session
        self.payload = payload
        self.onFinish = onFinish
    }

    public var body: some View {
        ComposerView(
            session: session,
            prefilledText: payload.text,
            prefilledAttachments: payload.attachments.map {
                ComposerView.PrefilledAttachment(
                    data: $0.data, filename: $0.filename, mimeType: $0.mimeType)
            }
        )
        .onDisappear { onFinish() }
    }
}
