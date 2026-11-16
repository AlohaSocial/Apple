// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation

// Aloha Social's continuous backup into the account's own Nextcloud Files.
// The Social app's own client API, with the bearer token. A stock Mastodon,
// and an Aloha Social from before backups, answer 404 — which is how the app
// knows to hide the screen.

extension Endpoint {
    public enum backup {
        /// The backup's settings and state, as `SocialBackup`
        /// (`read:accounts`).
        public static var settings: Endpoint { Endpoint(path: "api/v1/social/backup") }

        /// Changes whether it runs and how often (`write:accounts`). Answers
        /// the whole object, or a 422 naming a value that did not validate.
        public static func update(_ change: SocialBackupChange) -> Endpoint {
            let data = (try? JSONEncoder().encode(change)) ?? Data("{}".utf8)
            return Endpoint(method: .patch, path: "api/v1/social/backup", body: .json(data))
        }

        /// Starts one backup now (`write:accounts`). Answers 202 with the
        /// whole object, `running` true.
        public static var run: Endpoint {
            Endpoint(method: .post, path: "api/v1/social/backup/run", body: .empty)
        }
    }
}
