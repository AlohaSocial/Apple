// SPDX-License-Identifier: MIT

import AlohaHTML
import AlohaModels
import AlohaNetwork
import Foundation
import Observation

#if canImport(Translation)
    import Translation
#endif

/// Two paths, and the server's comes first (docs/10 §6).
///
/// Nextcloud Social implements `POST /api/v1/statuses/{id}/translate` through
/// Nextcloud's own provider, and answers **503** where the server has none —
/// which is the signal to fall through to the device.
@MainActor
@Observable
public final class Translator {
    public struct Result: Sendable, Hashable {
        public var content: String
        public var attribution: String
        public var detectedSourceLanguage: String?
        /// The server answers with the post's HTML translated; the device
        /// translates the plain text it was given.
        public var isHTML: Bool = false
    }

    /// One post's translation state, observed on its own.
    ///
    /// The translations and the set of posts being translated used to be two
    /// dictionaries on this object, and every post on screen read both in
    /// its body — so translating one post, which writes to them twice,
    /// redrew every visible post. A post now reads only its own slot.
    @MainActor
    @Observable
    final class Slot {
        var result: Result?
        var isInFlight = false
    }

    /// Created on first read and kept: a slot is two fields, and a post read
    /// once is likely to be read again while it is on screen.
    @ObservationIgnored private var slots: [String: Slot] = [:]

    public init() {}

    func slot(_ statusID: String) -> Slot {
        if let existing = slots[statusID] { return existing }
        let created = Slot()
        slots[statusID] = created
        return created
    }

    public func translation(for statusID: String) -> Result? { slot(statusID).result }

    /// Whether this post is being translated now.
    public func isTranslating(_ statusID: String) -> Bool { slot(statusID).isInFlight }

    public func clear(_ statusID: String) { slots[statusID]?.result = nil }

    public func translate(_ status: Status, session: AccountSession) async {
        let target = status.displayed
        let slot = slot(target.id)
        guard !slot.isInFlight, slot.result == nil else { return }
        slot.isInFlight = true
        defer { slot.isInFlight = false }

        if session.capabilities.translation {
            do {
                let translated = try await session.client.decode(
                    Translation.self,
                    from: Endpoint.statuses.translate(target.id, to: preferredLanguage))
                slot.result = Result(
                    content: translated.content,
                    attribution: String(
                        localized: "Translated by your server",
                        comment: "Translation attribution"),
                    detectedSourceLanguage: translated.detectedSourceLanguage,
                    isHTML: true)
                return
            } catch APIError.server(let status, _) where status == 503 {
                // The server has no provider today; the device may still manage.
            } catch {
                await session.handle(error)
            }
        }

        // The parser's plain text, not a regex strip: it keeps paragraph
        // breaks and decodes every entity, which a translation needs to read
        // the post as it was written.
        requestOnDevice(target, plainText: await RichTextCache.shared.plainText(for: target))
    }

    private var preferredLanguage: String? {
        Locale.current.language.languageCode?.identifier
    }

    /// Whether the Translate action should appear at all.
    public func canOffer(_ status: Status) -> Bool {
        guard let language = status.displayed.language else { return false }
        let preferred = Locale.preferredLanguages.compactMap {
            Locale(identifier: $0).language.languageCode?.identifier
        }
        return !preferred.contains(language)
    }

    /// Set by `TranslationHost` when the server could not translate. The
    /// framework's session is view-attached, so the request has to be handed
    /// back to a view rather than run from here.
    public private(set) var pendingOnDevice: PendingTranslation?

    public struct PendingTranslation: Sendable, Hashable, Identifiable {
        public var statusID: String
        public var text: String
        public var sourceLanguage: String?
        public var id: String { statusID }
    }

    public func completeOnDevice(statusID: String, content: String) {
        slot(statusID).result = Result(
            content: content,
            attribution: String(
                localized: "Translated on this device", comment: "Translation attribution"),
            detectedSourceLanguage: pendingOnDevice?.sourceLanguage)
        pendingOnDevice = nil
    }

    public func cancelOnDevice() { pendingOnDevice = nil }

    /// Set where neither the server nor the platform can translate, so the
    /// Translate action can say so rather than appearing to do nothing.
    public private(set) var unavailableFor: Set<String> = []

    public func reportOnDeviceUnavailable() {
        if let pending = pendingOnDevice { unavailableFor.insert(pending.statusID) }
        pendingOnDevice = nil
    }

    public func isUnavailable(for statusID: String) -> Bool {
        unavailableFor.contains(statusID)
    }

    private func requestOnDevice(_ status: Status, plainText: String) {
        pendingOnDevice = PendingTranslation(
            statusID: status.id, text: plainText, sourceLanguage: status.language)
    }
}
