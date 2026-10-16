// SPDX-License-Identifier: MIT

import SwiftUI

#if canImport(Translation)
    import Translation
#endif

/// The on-device half of translation (docs/10 §6).
///
/// `TranslationSession` can only be vended by a view modifier, so the
/// `Translator` hands a request back here and this runs it. The result goes
/// back to the `Translator`, and the post shows it in place of the original
/// (`RichTextView`), with a way back — no sheet over the timeline. The
/// framework asks for a missing language pair itself.
///
/// Attached once, high in the hierarchy, so any status can be translated
/// without every row carrying a session.
public struct TranslationHost: ViewModifier {
    private let translator: Translator

    #if canImport(Translation) && (os(iOS) || os(macOS))
        @State private var configuration: TranslationSession.Configuration?
    #endif

    public init(translator: Translator) {
        self.translator = translator
    }

    public func body(content: Content) -> some View {
        #if canImport(Translation) && (os(iOS) || os(macOS))
            content
                .onChange(of: translator.pendingOnDevice) { _, pending in
                    guard let pending else { return }
                    let next = TranslationSession.Configuration(
                        source: pending.sourceLanguage.map { Locale.Language(identifier: $0) },
                        target: nil)
                    // The same language pair twice is an equal configuration,
                    // which would not run again; invalidating it does.
                    if configuration == next {
                        configuration?.invalidate()
                    } else {
                        configuration = next
                    }
                }
                .translationTask(configuration) { @concurrent [translator] session in
                    // Off the main actor, where the session lives: handing it
                    // to `translate` from a main-actor closure would send it
                    // across isolation. Only the request and the result cross.
                    guard let pending = await translator.pendingOnDevice else { return }
                    do {
                        let response = try await session.translate(pending.text)
                        await translator.completeOnDevice(
                            statusID: pending.statusID, content: response.targetText)
                    } catch {
                        await translator.reportOnDeviceUnavailable()
                    }
                }
        #else
            // No on-device translation here. The server path still works;
            // where it does not, the post stays readable as it was written
            // and the Translate action says so rather than appearing to do
            // nothing.
            content
                .onChange(of: translator.pendingOnDevice) { _, pending in
                    if pending != nil { translator.reportOnDeviceUnavailable() }
                }
        #endif
    }
}

extension View {
    public func translationHost(_ translator: Translator) -> some View {
        modifier(TranslationHost(translator: translator))
    }
}
