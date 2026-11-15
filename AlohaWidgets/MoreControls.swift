// SPDX-License-Identifier: MIT

import AlohaDesign
import AppIntents
import SwiftUI
import WidgetKit

/// Controls for Control Center, the Lock Screen and the Action button that
/// open a screen of the app rather than a composer: posts waiting for their
/// time, search, and the story camera. Each is a link the app already
/// understands (`RouteResolver`), handed over by `ControlLink` exactly as
/// "New post" is, so none of them needs the app group or an account here.
struct MoreControls: WidgetBundle {
    var body: some Widget {
        ScheduledPostsControl()
        SearchControl()
        StoryCameraControl()
    }
}

extension ControlLink {
    /// A link with a query, for the one control that needs more than a host:
    /// the story camera (`alohasocial://story?camera=1`).
    static func intent(_ host: String, query: [URLQueryItem]) -> OpenURLIntent {
        var components = URLComponents()
        components.scheme = "alohasocial"
        components.host = host
        components.queryItems = query
        return OpenURLIntent(components.url ?? URL(filePath: "/"))
    }
}

/// "Scheduled posts": the list of posts waiting for their time, where one can
/// be moved or cancelled before it goes out.
struct ScheduledPostsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "social.aloha.app.control.scheduled") {
            ControlWidgetButton(action: ControlLink.intent("scheduled")) {
                Label {
                    Text("Scheduled posts", comment: "Control Center control")
                } icon: {
                    Image(systemName: "calendar.badge.clock")
                }
            }
        }
        .displayName(
            LocalizedStringResource("Scheduled posts", comment: "Control Center control")
        )
        .description(
            LocalizedStringResource(
                "Open the posts waiting to go out.",
                comment: "Control Center control description"))
    }
}

/// "Search": the search screen, ready for typing.
struct SearchControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "social.aloha.app.control.search") {
            ControlWidgetButton(action: ControlLink.intent("search")) {
                Label {
                    Text("Search", comment: "Control Center control")
                } icon: {
                    Image(systemName: AlohaSymbol.search)
                }
            }
        }
        .displayName(LocalizedStringResource("Search", comment: "Control Center control"))
        .description(
            LocalizedStringResource(
                "Search posts, people and hashtags.",
                comment: "Control Center control description"))
    }
}

/// "Story camera": the story composer with the full-screen camera already
/// up, for a picture or a video taken now. On a server without stories the
/// app opens and nothing more, as "New story" does; on a device without a
/// camera the composer opens on its library canvas.
struct StoryCameraControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "social.aloha.app.control.storyCamera") {
            ControlWidgetButton(
                action: ControlLink.intent(
                    "story", query: [URLQueryItem(name: "camera", value: "1")])
            ) {
                Label {
                    Text("Story camera", comment: "Control Center control")
                } icon: {
                    Image(systemName: "camera.aperture")
                }
            }
        }
        .displayName(LocalizedStringResource("Story camera", comment: "Control Center control"))
        .description(
            LocalizedStringResource(
                "Take a picture or a video for your story.",
                comment: "Control Center control description"))
    }
}
