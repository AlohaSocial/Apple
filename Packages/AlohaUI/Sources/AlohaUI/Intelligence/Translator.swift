// SPDX-License-Identifier: MIT

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
    }

    public private(set) var translations: [String: Result] = [:]
    public private(set) var inFlight: Set<String> = []

    public init() {}

    public func translation(for statusID: String) -> Result? { translations[statusID] }

    public func clear(_ statusID: String) { translations.removeValue(forKey: statusID) }

    public func translate(_ status: Status, session: AccountSession) async {
        let target = status.displayed
        guard !inFlight.contains(target.id), translations[target.id] == nil else { return }
        inFlight.insert(target.id)
        defer { inFlight.remove(target.id) }

        if session.capabilities.translation {
            do {
                let translated = try await session.client.decode(
                    Translation.self,
                    from: Endpoint.statuses.translate(target.id, to: preferredLanguage))
                translations[target.id] = Result(
                    content: translated.content,
                    attribution: String(
                        localized: "Translated by your server",
                        comment: "Translation attribution"),
                    detectedSourceLanguage: translated.detectedSourceLanguage)
                return
            } catch APIError.server(let status, _) where status == 503 {
                // The server has no provider today; the device may still manage.
            } catch {
                await session.handle(error)
            }
        }

        requestOnDevice(target, plainText: Self.plain(target.content))
    }

    private static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        translations[statusID] = Result(
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
