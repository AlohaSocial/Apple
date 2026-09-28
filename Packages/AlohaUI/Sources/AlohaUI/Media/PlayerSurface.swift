// SPDX-License-Identifier: MIT

import AVKit
import SwiftUI

/// The one place a video is drawn.
///
/// On macOS 27, SwiftUI's `VideoPlayer` aborts inside `_AVKit_SwiftUI` while
/// instantiating its representable's class metadata — the process died the
/// moment Shorts appeared. `AVPlayerView` itself is fine, so the Mac gets that
/// directly; everything else keeps `VideoPlayer`.
struct PlayerSurface: View {
    let player: AVPlayer
    var showsControls = true

    var body: some View {
        #if os(macOS)
            MacPlayerView(player: player, showsControls: showsControls)
        #else
            VideoPlayer(player: player)
                .disabled(!showsControls)
        #endif
    }
}

#if os(macOS)
    private struct MacPlayerView: NSViewRepresentable {
        let player: AVPlayer
        let showsControls: Bool

        func makeNSView(context: Context) -> AVPlayerView {
            let view = AVPlayerView()
            view.player = player
            view.controlsStyle = showsControls ? .inline : .none
            view.videoGravity = showsControls ? .resizeAspect : .resizeAspectFill
            view.showsFullScreenToggleButton = showsControls
            return view
        }

        func updateNSView(_ view: AVPlayerView, context: Context) {
            if view.player !== player { view.player = player }
            view.controlsStyle = showsControls ? .inline : .none
        }
    }
#endif
