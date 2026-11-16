// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AppIntents
import Foundation
import Photos
import UniformTypeIdentifiers

// iPhone, iPad and Vision Pro: the Mac app carries no photo-library usage
// description or sandbox entitlement, and a Mac's last photo is rarely what
// somebody means anyway.
#if os(iOS) || os(visionOS)

    /// "Post my last photo": the newest picture in the photo library, with a
    /// caption, as a post — after saying what will go out and asking first.
    ///
    /// The picture goes the composer's way (`MediaUploads`): without its
    /// location, as HEIC where the server takes it, spatial if it is spatial.
    public struct PostLastPhotoIntent: AppIntent {
        public static let title = LocalizedStringResource(
            "Post my last photo", comment: "App Intent title")
        public static let description = IntentDescription(
            LocalizedStringResource(
                "Posts the newest photo in your library, with a caption, after asking.",
                comment: "App Intent description"))
        public static let openAppWhenRun = false
        /// The same as any post: an unlocked phone, not a voice.
        public static let authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

        @Parameter(title: LocalizedStringResource("Caption", comment: "App Intent parameter"))
        public var caption: String?

        /// Left empty, the account's own default visibility.
        @Parameter(title: LocalizedStringResource("Visibility", comment: "App Intent parameter"))
        public var visibility: VisibilityAppEnum?

        /// Left empty, the account the app has active.
        @Parameter(title: LocalizedStringResource("Account", comment: "App Intent parameter"))
        public var account: SignedInAccountEntity?

        public init() {}

        public func perform() async throws -> some IntentResult & ProvidesDialog {
            guard let context = await IntentContext.current(accountID: account?.id) else {
                throw IntentError.noAccount
            }
            let photo = try await LatestPhoto.fetch()
            let text = caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let visibility = visibility?.modelValue ?? context.defaultVisibility
            let taken =
                photo.date.map {
                    $0.formatted(.relative(presentation: .named))
                } ?? String(localized: "recently", comment: "When a photo was taken, unknown")

            // Before anything leaves the device: which picture, which words,
            // which account. Nothing is uploaded on a "no".
            if text.isEmpty {
                try await requestConfirmation(
                    actionName: .post,
                    dialog: IntentDialog(
                        LocalizedStringResource(
                            "Post your last photo, taken \(taken), as \(context.handle)?",
                            comment:
                                "Confirmation before posting the newest photo without a caption"
                        )))
            } else {
                try await requestConfirmation(
                    actionName: .post,
                    dialog: IntentDialog(
                        LocalizedStringResource(
                            "Post your last photo, taken \(taken), as \(context.handle)? \(PostStatusIntent.preview(of: text))",
                            comment: "Confirmation before posting the newest photo with its caption"
                        )))
            }

            let file = IntentFile(data: photo.data, filename: photo.filename, type: photo.type)
            let mediaIDs = try await MediaUploads.upload(
                [file], client: context.client, limits: context.limits)
            let draft = StatusPost(
                text: text, visibility: visibility, mediaIDs: mediaIDs,
                idempotencyKey: PostStatusIntent.idempotencyKey(
                    accountID: context.accountID, text: text, visibility: visibility,
                    mediaDigests: [PostStatusIntent.digest(of: photo.data)]))
            _ = try await context.client.decode(Status.self, from: Endpoint.composing.post(draft))
            return .result(
                dialog: IntentDialog(
                    LocalizedStringResource("Posted.", comment: "App Intent result")))
        }
    }

    /// The newest picture in the library, as the bytes Photos keeps for it —
    /// usually a HEIC, with its location still in it until the upload takes it
    /// out.
    enum LatestPhoto {
        struct Photo: Sendable {
            let data: Data
            let filename: String
            let type: UTType?
            let date: Date?
        }

        static func fetch() async throws -> Photo {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            // Limited access is the library the person chose to share, and its
            // newest picture is a fair answer.
            guard status == .authorized || status == .limited else {
                throw IntentError.noPhotoAccess
            }
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 1
            guard let asset = PHAsset.fetchAssets(with: .image, options: options).firstObject else {
                throw IntentError.noPhoto
            }
            let date = asset.creationDate
            let requestOptions = PHImageRequestOptions()
            requestOptions.isNetworkAccessAllowed = true
            requestOptions.deliveryMode = .highQualityFormat
            requestOptions.version = .current
            let result: (Data, String?)? = await withCheckedContinuation { continuation in
                PHImageManager.default().requestImageDataAndOrientation(
                    for: asset, options: requestOptions
                ) { @Sendable data, uti, _, _ in
                    // Sendable, so it carries no main-actor isolation into
                    // whichever queue Photos answers on.
                    continuation.resume(returning: data.map { ($0, uti) })
                }
            }
            guard let (data, uti) = result else { throw IntentError.noPhoto }
            let type = uti.flatMap(UTType.init)
            let ext = type?.preferredFilenameExtension ?? "heic"
            return Photo(
                data: data, filename: "photo-\(UUID().uuidString).\(ext)", type: type, date: date)
        }
    }

#endif
