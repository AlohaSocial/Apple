// SPDX-License-Identifier: MIT

import AlohaModels
import AlohaNetwork
import AlohaStore
import Foundation

/// A launch mode that boots straight into a populated timeline against
/// `MockAPIServer`, skipping OAuth and the terms gate.
///
/// Exists because no amount of reading finds the bugs that only appear when
/// the app is actually driven — and OAuth cannot be automated. DEBUG only.
#if DEBUG
    public enum MockMode {
        public static let launchArgument = "-AlohaMockServer"
        public static let host = "cloud.example.test"

        public static var isEnabled: Bool {
            CommandLine.arguments.contains(launchArgument)
        }

        /// Mock server, but no account and no accepted terms — the first-run
        /// screens, which are otherwise only reachable through real OAuth.
        public static var startsSignedOut: Bool {
            CommandLine.arguments.contains("-AlohaMockNoAccount")
        }

        /// Everything the server refuses, so the offline and error strips can
        /// be seen rather than assumed.
        public static var isFailing: Bool {
            CommandLine.arguments.contains("-AlohaMockFailing")
        }

        public static func makeTransport() -> any HTTPTransport {
            MockAPIServer(
                configuration: isFailing ? .timelinesUnavailable : .nextcloudSocialWithRewrite,
                host: host, statusCount: 40)
        }

        /// Seeds one signed-in account so the shell lands on Home.
        @MainActor
        public static func seedIfNeeded(_ environment: AppEnvironment) async {
            // The theme is persisted in `UserDefaults`, which survives a
            // relaunch of the same install. A tour that chose a theme left it
            // chosen for whatever ran next, so the screenshots of every other
            // screen depended on test order — and the one test that asserts the
            // system theme follows the system only passed when nothing had
            // chosen one first. The mock always starts from the same place.
            environment.theme = .system
            guard !startsSignedOut else { return }
            TermsGate.recordAcceptance()
            guard environment.sessions.isEmpty else { return }

            let apiBase = URL(string: "https://\(host)/")!
            let probe = ServerProbe(transport: environment.transport)
            guard let outcome = try? await probe.discover(.init(host: host)) else { return }

            let detector = CapabilityDetector(transport: environment.transport)
            let capabilities = await detector.detect(
                apiBase: apiBase, accessToken: "mock-access-token",
                instance: outcome.instance, nodeInfo: outcome.nodeInfo)

            // Two accounts, because a switcher with one account in it has
            // never actually switched anything.
            let people = [
                Account(
                    id: "1", username: "alice", acct: "alice", displayName: "Alice",
                    avatar: URL(string: "https://\(host)/avatars/alice.png")),
                Account(
                    id: "2", username: "bob", acct: "bob", displayName: "Bob",
                    avatar: URL(string: "https://\(host)/avatars/bob.png")),
            ]

            for account in people {
                do {
                    _ = try await environment.addAccount(
                        instanceHost: host, apiBase: apiBase, account: account,
                        capabilities: capabilities, token: "mock-access-token")
                } catch {
                    // Loud on purpose: a silent seed failure looked like a
                    // working app that happened to have no account.
                    print("MockMode: seeding failed — \(error)")
                }
            }
            // The first one added is the one to read as.
            if let first = environment.sessions.first {
                environment.setActiveAccount(first.id)
            }
        }
    }
#endif
