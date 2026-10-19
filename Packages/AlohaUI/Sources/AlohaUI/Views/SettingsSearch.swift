// SPDX-License-Identifier: MIT

import Foundation

/// What the Settings search field finds.
///
/// It used to compare the query against English titles and English keyword
/// strings written into the view, so in German "Darstellung" found nothing
/// and "dunkel" found nothing either. Each section's title and keywords are
/// now localised strings, which a translator fills with the words people in
/// their language actually type — keeping the English ones people use anyway,
/// like "cache". Matching ignores case and accents, as the system's own
/// search does.
enum SettingsSection: CaseIterable, Sendable {
    case accounts, appearance, yourAccount, feeds, timeline, nextcloud, media
    case notifications, posting, intelligence, storage, content, soundAndTouch
    case moderation, deleteAccount, about

    var title: String {
        switch self {
        case .accounts: String(localized: "Accounts", comment: "Settings section")
        case .appearance: String(localized: "Appearance", comment: "Settings section")
        case .yourAccount: String(localized: "Your account", comment: "Settings section")
        case .feeds: String(localized: "Feeds", comment: "Settings section")
        case .timeline: String(localized: "Timeline", comment: "Settings section")
        case .nextcloud: String(localized: "Nextcloud", comment: "Settings section")
        case .media: String(localized: "Media", comment: "Settings section")
        case .notifications: String(localized: "Notifications", comment: "Settings section")
        case .posting: String(localized: "Posting", comment: "Settings section")
        case .intelligence: String(localized: "Intelligence", comment: "Settings section")
        case .storage: String(localized: "Storage", comment: "Settings section")
        case .content: String(localized: "Content", comment: "Settings section")
        case .soundAndTouch: String(localized: "Sound & touch", comment: "Settings section")
        case .moderation: String(localized: "Moderation", comment: "Settings section")
        case .deleteAccount: String(localized: "Delete account", comment: "Settings section")
        case .about: String(localized: "About", comment: "Settings section")
        }
    }

    /// The words that should find this section, in the reader's language.
    var keywords: String {
        switch self {
        case .accounts:
            String(
                localized: "account accounts add sign switch remove sign out log out",
                comment:
                    "Settings search keywords for the Accounts section: words, separated by spaces, that people would type to find it. Translate into the words people in your language use; they do not have to match the English one for one."
            )
        case .appearance:
            String(
                localized:
                    "appearance theme dark light density serif icon counts numbers text size compact",
                comment:
                    "Settings search keywords for the Appearance section, separated by spaces. Translate into the words people in your language would type."
            )
        case .yourAccount:
            String(
                localized:
                    "profile edit name bio avatar header fields featured hashtags portfolio channels migration export import move alias authorized apps tokens",
                comment:
                    "Settings search keywords for the Your account section, separated by spaces. Translate into the words people in your language would type."
            )
        case .feeds:
            String(
                localized: "feeds modes home photos video shorts news audio screens timelines",
                comment:
                    "Settings search keywords for the Feeds section, separated by spaces. Translate into the words people in your language would type."
            )
        case .timeline:
            String(
                localized:
                    "timeline feed boosts replies pill position restore numbers swipe for you interests",
                comment:
                    "Settings search keywords for the Timeline section, separated by spaces. Translate into the words people in your language would type."
            )
        case .nextcloud:
            String(
                localized: "nextcloud files push notification server connect",
                comment:
                    "Settings search keywords for the Nextcloud section, separated by spaces. Translate into the words people in your language would type."
            )
        case .media:
            String(
                localized: "media autoplay video sensitive blur mute loop data",
                comment:
                    "Settings search keywords for the Media section, separated by spaces. Translate into the words people in your language would type."
            )
        case .notifications:
            String(
                localized: "notifications push digest quiet hours delivery sounds",
                comment:
                    "Settings search keywords for the Notifications section, separated by spaces. Translate into the words people in your language would type."
            )
        case .posting:
            String(
                localized: "posting compose composer visibility language alt draft",
                comment:
                    "Settings search keywords for the Posting section, separated by spaces. Translate into the words people in your language would type."
            )
        case .intelligence:
            String(
                localized: "intelligence ai writing rewrite summary on-device apple",
                comment:
                    "Settings search keywords for the Intelligence section, separated by spaces. Translate into the words people in your language would type."
            )
        case .storage:
            String(
                localized: "storage cache cached media clear disk",
                comment:
                    "Settings search keywords for the Storage section, separated by spaces. Translate into the words people in your language would type."
            )
        case .content:
            String(
                localized:
                    "content filter filters language translate translation mute block drafts scheduled held review waiting moderator memories recap looking back on this day",
                comment:
                    "Settings search keywords for the Content section, separated by spaces. Translate into the words people in your language would type."
            )
        case .soundAndTouch:
            String(
                localized: "sound touch haptics vibrate vibration audio chime tick senses silent",
                comment:
                    "Settings search keywords for the Sound & touch section, separated by spaces. Translate into the words people in your language would type."
            )
        case .moderation:
            String(
                localized:
                    "moderation moderator reports admin administrator suspend silence trends",
                comment:
                    "Settings search keywords for the Moderation section, separated by spaces. Translate into the words people in your language would type."
            )
        case .deleteAccount:
            String(
                localized: "delete account erase remove deactivate close",
                comment:
                    "Settings search keywords for the Delete account section, separated by spaces. Translate into the words people in your language would type."
            )
        case .about:
            String(
                localized:
                    "about licence license version source code developer contact server peers activity federation keyboard shortcuts year wrapped",
                comment:
                    "Settings search keywords for the About section, separated by spaces. Translate into the words people in your language would type."
            )
        }
    }

    /// Whether `query` finds this section. An empty query finds everything.
    func matches(_ query: String) -> Bool {
        Self.matches(query, in: [title, keywords])
    }

    /// The rule on its own, so it can be tested without a catalog: any of the
    /// texts contains the query, ignoring case and accents — "dunkel" finds
    /// "Dunkel", "resume" finds "résumé".
    static func matches(_ query: String, in texts: [String]) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return texts.contains {
            $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
