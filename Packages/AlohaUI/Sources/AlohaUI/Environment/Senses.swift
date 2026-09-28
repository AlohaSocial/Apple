// SPDX-License-Identifier: MIT

import Foundation
import Observation
import SwiftUI

#if os(iOS) || os(visionOS)
    import UIKit
#endif
#if os(watchOS)
    import WatchKit
#endif
#if canImport(AudioToolbox) && !os(watchOS)
    import AudioToolbox
#endif

/// Sound and touch, per device.
///
/// Nextcloud Social's `services/senses.js` and `SensesSettings.vue`: a tick on
/// a like, a chime for a direct message, a tap in the hand. Nothing goes to the
/// server — both switches are about the device in front of the reader — so they
/// live in `UserDefaults` beside the theme rather than in the account.
///
/// **Sound is off until it is turned on**, which is the web's rule and the
/// right one for an app somebody opens on a train. Touch follows the system:
/// Reduce Motion turns it off whatever this says, because a haptic is motion
/// somebody asked not to have.
@MainActor
@Observable
public final class Senses {
    public var soundsEnabled: Bool {
        didSet { UserDefaults.standard.set(soundsEnabled, forKey: Self.soundKey) }
    }

    public var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: Self.hapticKey) }
    }

    /// One per app. A cue belongs to the device, not to an account or a
    /// window, and the places worth one — a like button, the composer, an
    /// arriving message — are scattered enough that threading an instance
    /// through them all would be its own kind of noise.
    public static let shared = Senses()

    private static let soundKey = "aloha.senses.sound"
    private static let hapticKey = "aloha.senses.haptics"

    public init() {
        // Sound off by default; touch on, because a phone taps for everything
        // else already and its absence reads as a broken button.
        soundsEnabled = UserDefaults.standard.bool(forKey: Self.soundKey)
        hapticsEnabled =
            UserDefaults.standard.object(forKey: Self.hapticKey) as? Bool ?? true
    }

    /// The moments worth a sound or a tap. Nothing else gets one: a cue for
    /// every scroll is a cue for nothing.
    public enum Cue: Sendable, Hashable, CaseIterable {
        /// A soft tick.
        case like
        /// A breath of air as a post goes out.
        case post
        /// Two notes, for a direct message arriving.
        case directMessage
        /// A boost or a reaction — the same tick as a like, one step lighter.
        case interact
        /// Something did not work.
        case failure

        var systemSoundID: UInt32 {
            switch self {
            case .like, .interact: 1103  // Tink
            case .post: 1004  // SentMessage
            case .directMessage: 1003  // ReceivedMessage
            case .failure: 1053
            }
        }
    }

    /// Plays whichever of the two the reader has asked for. Safe to call from
    /// anywhere; does nothing at all when both are off.
    public func feel(_ cue: Cue) {
        if soundsEnabled { play(cue) }
        if hapticsEnabled { buzz(cue) }
    }

    /// The sound on its own, for the Listen button in Settings — somebody
    /// should be able to hear what they are turning on before they turn it on.
    public func play(_ cue: Cue) {
        #if canImport(AudioToolbox) && !os(watchOS)
            AudioServicesPlaySystemSound(SystemSoundID(cue.systemSoundID))
        #endif
    }

    private func buzz(_ cue: Cue) {
        #if os(iOS)
            // Reduce Motion is the system's word for "no more movement than
            // necessary", and a haptic is movement.
            guard !UIAccessibility.isReduceMotionEnabled else { return }
            switch cue {
            case .failure:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            case .post:
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            default:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        #elseif os(watchOS)
            switch cue {
            case .failure: WKInterfaceDevice.current().play(.failure)
            case .post: WKInterfaceDevice.current().play(.success)
            case .directMessage: WKInterfaceDevice.current().play(.notification)
            default: WKInterfaceDevice.current().play(.click)
            }
        #endif
    }
}
