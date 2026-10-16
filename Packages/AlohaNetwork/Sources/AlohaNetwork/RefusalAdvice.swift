// SPDX-License-Identifier: MIT

import Foundation

/// The app's own sentence for an Aloha Social refusal code.
///
/// The server sends a stable `code` beside an English sentence so a client can
/// say it in the person's language, with what they can do next; its own web
/// page does the same (`src/utils/serverError.js`). A code missing here falls
/// back to the server's sentence, so an unknown code is never worse than
/// before. Codes: docs/API.md "Migration error codes" and
/// Atproto-Compatibility §13.5.
enum RefusalAdvice {
    static func text(code: String, parameters: [String: String]) -> String? {
        let limit = parameters["limit"].flatMap { Int($0) }
        switch code {
        case "featured-tags-full":
            if let limit {
                return String(
                    localized:
                        "You can feature at most \(limit) hashtags. Remove one before adding another.",
                    comment: "Refusal: featured hashtag limit, with the limit")
            }
            return String(
                localized: "You can't feature any more hashtags. Remove one before adding another.",
                comment: "Refusal: featured hashtag limit")
        case "shorts-full":
            if let limit {
                return String(
                    localized:
                        "You already have \(limit) shorts live. Delete one, or wait for one to expire.",
                    comment: "Refusal: live 24-hour shorts limit, with the limit")
            }
            return String(
                localized:
                    "You can't post another short yet. Delete one, or wait for one to expire.",
                comment: "Refusal: live 24-hour shorts limit")
        case "import-running", "import-in-progress":
            return String(
                localized: "An import is already running. Wait for it to finish, then try again.",
                comment: "Refusal: an import or move is running")
        case "import-not-found":
            return String(
                localized: "That import isn't there any more.", comment: "Refusal: import not found"
            )
        case "file-too-large":
            return String(
                localized: "That file is larger than your server accepts.",
                comment: "Refusal: upload too large")
        case "no-file", "file-unreadable":
            return String(
                localized: "The file didn't arrive in one piece. Choose it again.",
                comment: "Refusal: upload missing or unreadable")
        case "archive-unreadable", "archive-not-social":
            return String(
                localized:
                    "That isn't an archive Aloha Social exported. Choose the archive the export made.",
                comment: "Refusal: wrong archive for an import")
        case "account-address-invalid":
            return String(
                localized: "That isn't an account address. Check it and try again.",
                comment: "Refusal: account address malformed")
        case "account-not-found":
            return String(
                localized: "No account answers to that address.",
                comment: "Refusal: account not found")
        case "account-not-verifiable":
            return String(
                localized:
                    "That server only answers servers it can verify, and it couldn't verify yours.",
                comment: "Refusal: remote server refused an unverifiable fetch")
        case "alias-self", "move-onto-self":
            return String(
                localized: "That's this account. Enter the other account.",
                comment: "Refusal: alias or move target is the account itself")
        case "confirm-handle":
            return String(
                localized: "Type this account's handle to confirm.",
                comment: "Refusal: move not confirmed with the handle")
        case "move-cooldown":
            return String(
                localized:
                    "This account moved recently. It can move again 30 days after the last move.",
                comment: "Refusal: account move cooldown")
        case "alias-missing":
            return String(
                localized:
                    "The new account doesn't list this one as an alias yet. Add the alias there first.",
                comment: "Refusal: move target lacks the alias")
        case "finish-not-possible":
            return String(
                localized: "Finish the move on your old server.",
                comment: "Refusal: move can't be finished from here")
        case "old-server-refused":
            return String(
                localized: "Your old server refused. Try again later, or finish the move there.",
                comment: "Refusal: old server refused a move step")
        case "video-address-invalid":
            return String(
                localized: "That isn't a video address. Copy the address of the video's page.",
                comment: "Refusal: video import address malformed")
        case "video-here-already":
            return String(
                localized: "That video is on your server already.",
                comment: "Refusal: video import of a local video")
        case "video-unreachable":
            return String(
                localized: "That video couldn't be read. Check the address, or try again later.",
                comment: "Refusal: video import address unreachable")
        case "video-unsupported":
            return String(
                localized: "That address isn't a video that can be brought over.",
                comment: "Refusal: video import of something else")
        case "bluesky-off":
            return String(
                localized: "Bluesky isn't switched on for your server.",
                comment: "Refusal: Bluesky disabled on the server")
        case "handle-invalid", "handle-not-found":
            return String(
                localized: "No Bluesky account answers to that handle.",
                comment: "Refusal: Bluesky handle unknown")
        case "plc-unreachable":
            return String(
                localized: "Bluesky's directory can't be reached right now. Try again later.",
                comment: "Refusal: PLC directory unreachable")
        default:
            return nil
        }
    }
}
