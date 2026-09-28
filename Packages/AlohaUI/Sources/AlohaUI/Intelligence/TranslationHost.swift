// SPDX-License-Identifier: MIT

import SwiftUI

#if canImport(Translation)
    import Translation
#endif

/// The on-device half of translation (docs/10 §6).
///
/// `TranslationSession` can only be vended by a view modifier, and its
/// `translate` is `@concurrent` while `ViewModifier.body` is main-actor — so a
/// session obtained there cannot legally be handed to it. Apple's own
/// presentation does the work instead: it is the same on-device translation,
/// it handles the language-pair download that `Translator` cannot, and it needs
/// no session to marshal.
///
/// Attached once, high in the hierarchy, so any status can be translated
/// without every row carrying one.
public struct TranslationHost: ViewModifier {
    private let translator: Translator

    public init(translator: Translator) {
        self.translator = translator
    }

    public func body(content: Content) -> some View {
        #if canImport(Translation) && os(iOS)
            content
                .translationPresentation(
                    isPresented: Binding(
                        get: { translator.pendingOnDevice != nil },
                        set: { if !$0 { translator.cancelOnDevice() } }),
                    text: translator.pendingOnDevice?.text ?? ""
                ) { translated in
                    guard let pending = translator.pendingOnDevice else { return }
                    translator.completeOnDevice(
                        statusID: pending.statusID, content: translated)
                }
        #else
            // Only iOS and iPadOS have the translation presentation. The
            // server path still works everywhere; where it does not, the post
            // stays readable as it was written and the Translate action says so
            // rather than appearing to do nothing.
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
