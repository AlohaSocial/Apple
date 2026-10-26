// SPDX-License-Identifier: MIT

import AlohaStore
import AlohaUI
import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Presents the real composer from `AlohaUI` rather than a reduced one, with
/// the shared content pre-attached (docs/09 §6). The same extension serves the
/// iPhone, iPad and the Mac; only the controller that hosts the SwiftUI root
/// differs.
///
/// The extension has a tight memory budget. It builds the app's own
/// `AppEnvironment`, whose services (sync, notifications) stay idle until
/// something starts them, which nothing here does; loading it reads the
/// account list and refreshes each account's server state, as the app does.
/// Shared movies stay on disk (`loadFile`) for the memory budget's sake.
@MainActor
enum ShareExtensionRoot {
    /// The composer for the active account, or the no-account screen. `end`
    /// finishes the extension's request: `true` once posted, `false` when
    /// the person backs out.
    static func make(
        context: NSExtensionContext?, environment: AppEnvironment,
        end: @escaping @MainActor (_ posted: Bool) -> Void
    ) async -> AnyView {
        let payload = await SharePayload.read(from: context)
        await environment.load()

        guard let session = environment.activeSession else {
            return AnyView(NoAccountView { end(false) })
        }
        return AnyView(
            ShareComposerView(session: session, payload: payload) { outcome in
                end(outcome == .posted)
            }
            .environment(environment))
    }
}

#if canImport(UIKit)
    final class ShareViewController: UIViewController {
        private var environment: AppEnvironment?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            Task { await present() }
        }

        private func present() async {
            let environment = AppEnvironment(container: StoreContainer.make())
            self.environment = environment
            let root = await ShareExtensionRoot.make(
                context: extensionContext, environment: environment
            ) { [weak self] posted in self?.end(posted: posted) }

            let host = UIHostingController(rootView: root)
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(host.view)
            host.didMove(toParent: self)
        }

        private func end(posted: Bool) {
            if posted {
                extensionContext?.completeRequest(returningItems: nil)
            } else {
                extensionContext?.cancelRequest(
                    withError: CocoaError(.userCancelled))
            }
        }
    }
#elseif canImport(AppKit)
    /// The Mac's share sheet shows this controller's view in a sheet of its
    /// own, sized by `preferredContentSize`; its toolbar is the system's, so
    /// the composer draws Cancel and Post itself (`composerHost`).
    final class ShareViewController: NSViewController {
        private var environment: AppEnvironment?

        override func loadView() {
            view = NSView(frame: NSRect(origin: .zero, size: Self.size))
            preferredContentSize = Self.size
        }

        /// Wide enough for a post and a row of four thumbnails, tall enough
        /// for the editor not to scroll at once.
        private static let size = NSSize(width: 540, height: 600)

        override func viewDidLoad() {
            super.viewDidLoad()
            Task { await present() }
        }

        private func present() async {
            let environment = AppEnvironment(container: StoreContainer.make())
            self.environment = environment
            let root = await ShareExtensionRoot.make(
                context: extensionContext, environment: environment
            ) { [weak self] posted in self?.end(posted: posted) }

            let host = NSHostingController(rootView: root)
            addChild(host)
            host.view.frame = view.bounds
            host.view.autoresizingMask = [.width, .height]
            view.addSubview(host.view)
        }

        private func end(posted: Bool) {
            if posted {
                extensionContext?.completeRequest(returningItems: nil)
            } else {
                extensionContext?.cancelRequest(
                    withError: CocoaError(.userCancelled))
            }
        }
    }
#endif

/// Shown when the app has no account to post with. It needs its own way out:
/// on the Mac the sheet has no other control, and on iOS a swipe is not
/// something every reader can make.
private struct NoAccountView: View {
    let close: () -> Void

    var body: some View {
        VStack {
            ContentUnavailableView {
                Text("No account yet", comment: "Share extension, no account")
            } description: {
                Text(
                    "Open Aloha Social and add your server first.",
                    comment: "Share extension, no account detail")
            }
            Button {
                close()
            } label: {
                Text("Close", comment: "Share extension, no account action")
            }
            .keyboardShortcut(.cancelAction)
            .padding()
        }
    }
}

extension NSItemProvider {
    /// `loadDataRepresentation` has no async form; this bridges the
    /// completion handler once rather than at every call site.
    func loadData(_ type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
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

    /// The item as a file of the extension's own, never read into memory.
    ///
    /// The URL the provider hands over is only good inside its callback, so
    /// the file is moved (or, where that is refused, copied) out there, into
    /// the extension's temporary directory — the upload runs in this process,
    /// so that is where it has to be.
    func loadFile(_ type: UTType) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                let ext = type.preferredFilenameExtension ?? url.pathExtension
                let kept = FileManager.default.temporaryDirectory
                    .appending(path: "shared-\(UUID().uuidString).\(ext)")
                do {
                    do {
                        try FileManager.default.moveItem(at: url, to: kept)
                    } catch {
                        try FileManager.default.copyItem(at: url, to: kept)
                    }
                    continuation.resume(returning: kept)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// The item in the first representation a server takes, named and typed
    /// for what it is. An image offered only in a type no server stores (a
    /// Mac's TIFF) is re-encoded as JPEG; anything else unusable is skipped.
    ///
    /// A movie stays a file all the way to the upload: a phone video is
    /// easily larger than the whole of the extension's memory allowance
    /// (around 120 MB), and reading it in ended the extension mid-share.
    func loadUpload(
        preferring preferred: [UTType]
    ) async -> ComposerView.PrefilledAttachment? {
        if let type = SharedItemType.pick(from: registeredTypeIdentifiers, preferring: preferred) {
            let upload = SharedItemType.upload(for: type)
            if preferred == SharedItemType.uploadableMovies {
                if let file = await loadFile(type) {
                    return .init(
                        fileURL: file, filename: upload.filename, mimeType: upload.mimeType)
                }
            } else if let data = await loadData(type) {
                return .init(data: data, filename: upload.filename, mimeType: upload.mimeType)
            }
        }
        guard preferred == SharedItemType.uploadableImages,
            let data = await loadData(.image),
            let jpeg = Self.jpeg(from: data)
        else { return nil }
        let upload = SharedItemType.upload(for: .jpeg)
        return .init(data: jpeg, filename: upload.filename, mimeType: upload.mimeType)
    }

    private static func jpeg(from data: Data) -> Data? {
        #if canImport(UIKit)
            UIImage(data: data)?.jpegData(compressionQuality: 0.9)
        #elseif canImport(AppKit)
            NSBitmapImageRep(data: data)?
                .representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        #else
            nil
        #endif
    }
}

/// What arrived in the share sheet.
public struct SharePayload: Sendable {
    public var text: String
    /// In the composer's own terms: bytes for a picture, a file for a movie.
    public var attachments: [ComposerView.PrefilledAttachment]

    public init(text: String = "", attachments: [ComposerView.PrefilledAttachment] = []) {
        self.text = text
        self.attachments = attachments
    }

    static func read(from context: NSExtensionContext?) async -> SharePayload {
        guard let items = context?.inputItems as? [NSExtensionItem] else {
            return SharePayload()
        }

        var text = ""
        var attachments: [ComposerView.PrefilledAttachment] = []

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
                    if let movie = await provider.loadUpload(
                        preferring: SharedItemType.uploadableMovies)
                    {
                        attachments.append(movie)
                        continue
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                    let image = await provider.loadUpload(
                        preferring: SharedItemType.uploadableImages)
                {
                    attachments.append(image)
                }
            }
        }

        return SharePayload(text: text, attachments: attachments)
    }
}

/// Pre-loads the shared content into the app's own composer.
public struct ShareComposerView: View {
    private let session: AccountSession
    private let payload: SharePayload
    private let onFinish: (ComposerOutcome) -> Void

    public init(
        session: AccountSession, payload: SharePayload,
        onFinish: @escaping (ComposerOutcome) -> Void
    ) {
        self.session = session
        self.payload = payload
        self.onFinish = onFinish
    }

    public var body: some View {
        ComposerView(
            session: session,
            prefilledText: payload.text,
            prefilledAttachments: payload.attachments
        )
        // At the root of a hosting controller there is no sheet to dismiss:
        // the composer's ending is the extension's.
        .composerHost(showsInlineActions: Self.drawsOwnActions) { onFinish($0) }
    }

    /// The Mac's share sheet owns its window's toolbar; iOS's extension
    /// sheet shows the composer's navigation bar like the app's sheet does.
    private static var drawsOwnActions: Bool {
        #if os(macOS)
            true
        #else
            false
        #endif
    }
}
