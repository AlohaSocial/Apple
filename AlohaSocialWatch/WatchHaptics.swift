// SPDX-License-Identifier: MIT

import WatchKit

/// What a wrist feels when something it asked for went through, or did not.
///
/// A watch is often used without being looked at for long — a tap, the arm
/// goes down — so the outcome of a send, a favourite or a boost is told by
/// a tap on the wrist as well as on the screen. Played when the server has
/// answered, not when the button was pressed: the screen already changed at
/// the press, and the haptic is the part that says whether it held.
enum WatchHaptics {
    static func succeeded() {
        WKInterfaceDevice.current().play(.success)
    }

    static func failed() {
        WKInterfaceDevice.current().play(.failure)
    }
}
