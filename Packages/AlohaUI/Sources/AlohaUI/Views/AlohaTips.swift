// SPDX-License-Identifier: MIT

import AlohaDesign
import SwiftUI
import TipKit

/// The gestures the app has that nothing on screen announces.
///
/// Each one is said once, where the gesture works, and retires itself the
/// moment the person uses it: a tip about something already known is noise.
enum AlohaTips {
    /// Started once per launch, from the shell. Tips are switched off in the
    /// screen tours, where a popover would sit over the element under test.
    static func configure() {
        #if DEBUG
            if MockMode.isEnabled {
                Tips.hideAllTipsForTesting()
                return
            }
        #endif
        try? Tips.configure([.displayFrequency(.daily)])
    }
}

struct SwipeActionsTip: Tip {
    var title: Text {
        Text("Swipe a post", comment: "Tip title: swipe actions on timeline posts")
    }

    var message: Text? {
        Text(
            "Swipe from either edge to reply, favourite, boost or bookmark. You choose which in Settings.",
            comment: "Tip detail: swipe actions on timeline posts")
    }

    var image: Image? { Image(systemName: "hand.draw") }
}

struct ShortsDoubleTapTip: Tip {
    var title: Text {
        Text("Double-tap to favourite", comment: "Tip title: double-tap a short")
    }

    var message: Text? {
        Text(
            "Double-tap anywhere on a short to favourite it without looking for the button.",
            comment: "Tip detail: double-tap a short")
    }

    var image: Image? { Image(systemName: AlohaSymbol.favourite) }
}

struct PhotosDoubleTapTip: Tip {
    var title: Text {
        Text("Double-tap to favourite", comment: "Tip title: double-tap a photo")
    }

    var message: Text? {
        Text(
            "Double-tap a photo to favourite it.",
            comment: "Tip detail: double-tap a photo")
    }

    var image: Image? { Image(systemName: AlohaSymbol.favourite) }
}

struct TimelineSourceTip: Tip {
    var title: Text {
        Text("Choose whose posts", comment: "Tip title: the timeline source switch")
    }

    var message: Text? {
        Text(
            "Tap the title to switch between the people you follow, your server, and everyone it knows.",
            comment: "Tip detail: the timeline source menu in the screen title")
    }

    var image: Image? { Image(systemName: "person.2") }
}
