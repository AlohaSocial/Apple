// SPDX-License-Identifier: MIT

import AlohaDesign
import AppIntents
import SwiftUI
import WidgetKit

/// The controls for Control Center, the Lock Screen and the Action button.
/// Each is a link the app already understands (`RouteResolver`), handed over
/// by `ControlLink`, so none of them needs the app group or an account here.
struct AlohaControls: WidgetBundle {
    var body: some Widget {
        NewPostControl()
        NewStoryControl()
        StoryCameraControl()
        OpenMessagesControl()
        ScheduledPostsControl()
        SearchControl()
    }
}

/// The app's own links, as the system intent that opens them.
///
/// `OpenURLIntent` hands the link to the app through the same `onOpenURL` a
/// tapped widget uses, so a control runs nothing in this extension and needs
/// no account, store or network — none of which an extension can reach while
/// the app group is off.
enum ControlLink {
    static func intent(_ host: String, query: [URLQueryItem]? = nil) -> OpenURLIntent {
        OpenURLIntent(url(host, query: query))
    }

    /// `alohasocial://<host>[?query]`. A scheme and a bare host always make a
    /// URL; the fallback is never reached and opens nothing rather than
    /// crashing.
    static func url(_ host: String, query: [URLQueryItem]? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "alohasocial"
        components.host = host
        components.queryItems = query
        return components.url ?? URL(filePath: "/")
    }
}

/// "New post" in Control Center, on the Lock Screen and on the Action button.
struct NewPostControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "social.aloha.app.control.newPost") {
            ControlWidgetButton(action: ControlLink.intent("compose")) {
                Label {
                    Text("New post", comment: "Control Center control")
                } icon: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .displayName(LocalizedStringResource("New post", comment: "Control Center control"))
        .description(
            LocalizedStringResource(
                "Open the composer.", comment: "Control Center control description"))
    }
}

/// "New short": the story composer, on servers that have stories.
struct NewStoryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "social.aloha.app.control.newStory") {
            ControlWidgetButton(action: ControlLink.intent("story")) {
                Label {
                    Text("New short", comment: "Control Center control")
                } icon: {
                    Image(systemName: "camera.circle")
                }
            }
        }
        .displayName(LocalizedStringResource("New short", comment: "Control Center control"))
        .description(
            LocalizedStringResource(
                "Open the short composer.", comment: "Control Center control description"))
    }
}

/// "Short camera": the story composer with the full-screen camera already
/// up, for a picture or a video taken now. On a server without stories the
/// app opens and nothing more, as "New short" does; on a device without a
/// camera the composer opens on its library canvas.
struct StoryCameraControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "social.aloha.app.control.storyCamera") {
            ControlWidgetButton(
                action: ControlLink.intent(
                    "story", query: [URLQueryItem(name: "camera", value: "1")])
            ) {
                Label {
                    Text("Short camera", comment: "Control Center control")
                } icon: {
                    Image(systemName: "camera.aperture")
                }
            }
        }
        .displayName(LocalizedStringResource("Short camera", comment: "Control Center control"))
        .description(
            LocalizedStringResource(
                "Take a photo or a video for your short.",
                comment: "Control Center control description"))
    }
}

/// "Messages" in Control Center, on the Lock Screen and on the Action button.
struct OpenMessagesControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "social.aloha.app.control.messages") {
            ControlWidgetButton(action: ControlLink.intent("conversations")) {
                Label {
                    Text("Messages", comment: "Control Center control")
                } icon: {
                    Image(systemName: AlohaSymbol.directMessage)
                }
            }
        }
        .displayName(LocalizedStringResource("Messages", comment: "Control Center control"))
        .description(
            LocalizedStringResource(
                "Open your direct messages.", comment: "Control Center control description"))
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
