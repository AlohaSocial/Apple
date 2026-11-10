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

        /// Serves video over a real loopback socket, because AVFoundation will
        /// not ask the in-process mock for anything. Signing in then happens
        /// against `http://localhost:<port>`, which is the same origin as the
        /// media — so the player sends the account's bearer token, exactly as
        /// it would to a real instance that protects its files.
        public static let mediaLaunchArgument = "-AlohaMockMedia"

        private static var mediaServer: MockMediaServer?

        public static var isMediaMode: Bool {
            CommandLine.arguments.contains(mediaLaunchArgument)
        }

        /// Starts the media socket once, before the first transport is built.
        public static func startMediaServerIfNeeded() {
            guard isMediaMode, mediaServer == nil else { return }
            var behaviour: MockMediaServer.Behaviour = []
            if CommandLine.arguments.contains("-AlohaMockMediaRefuseFile") {
                behaviour.insert(.refuseFile)
            }
            if CommandLine.arguments.contains("-AlohaMockMediaRefuseLadder") {
                behaviour.insert(.refuseLadder)
            }
            if CommandLine.arguments.contains("-AlohaMockMediaStallFile") {
                behaviour.insert(.stallFile)
            }
            mediaServer = MockMediaServer(token: "mock-access-token", behaviour: behaviour)
        }

        /// The host the mock's fixtures point at: the socket when there is one,
        /// the made-up domain otherwise.
        public static var activeHost: String {
            mediaServer.map { "localhost:\($0.port)" } ?? host
        }

        public static var activeScheme: String {
            mediaServer == nil ? "https" : "http"
        }

        public static var origin: String { "\(activeScheme)://\(activeHost)" }

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
            startMediaServerIfNeeded()
            return MockAPIServer(
                configuration: isFailing ? .timelinesUnavailable : .nextcloudSocialWithRewrite,
                host: activeHost, scheme: activeScheme, statusCount: 40)
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
            if CommandLine.arguments.contains("-AlohaMockResetPhotoLayout") {
                UserDefaults.standard.removeObject(forKey: "aloha.photosLayout")
            }
            // First-run hints, so a tour can dismiss one and prove that it
            // stays dismissed across a relaunch without deleting the app.
            if CommandLine.arguments.contains("-AlohaMockResetHints") {
                for key in UserDefaults.standard.dictionaryRepresentation().keys
                where key.hasPrefix("aloha.hint.") {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
            // Screen tours skip the optional first-account choice; its own test
            // requests it explicitly so launch behaviour is independent of test order.
            if CommandLine.arguments.contains("-AlohaMockModeSelection") {
                UserDefaults.standard.removeObject(forKey: "aloha.chosenModes")
            } else {
                UserDefaults.standard.set(
                    FeedMode.offered.map(\.rawValue), forKey: "aloha.chosenModes")
            }
            guard !startsSignedOut else { return }
            TermsGate.recordAcceptance()
            for session in environment.sessions {
                await session.updateSettings { $0.enabledModes = FeedMode.defaultEnabled }
            }
            guard environment.sessions.isEmpty else { return }

            let apiBase = URL(string: "\(origin)/")!
            let probe = ServerProbe(transport: environment.transport)
            guard let outcome = try? await probe.discover(.init(host: activeHost)) else { return }

            let detector = CapabilityDetector(transport: environment.transport)
            let capabilities = await detector.detect(
                apiBase: apiBase, accessToken: "mock-access-token",
                instance: outcome.instance, nodeInfo: outcome.nodeInfo)

            // Two accounts, because a switcher with one account in it has
            // never actually switched anything.
            let people = [
                Account(
                    id: "1", username: "alice", acct: "alice", displayName: "Alice",
                    avatar: URL(string: "\(origin)/avatars/alice.png")),
                Account(
                    id: "2", username: "bob", acct: "bob", displayName: "Bob",
                    avatar: URL(string: "\(origin)/avatars/bob.png")),
            ]

            for account in people {
                do {
                    _ = try await environment.addAccount(
                        instanceHost: activeHost, apiBase: apiBase, account: account,
                        capabilities: capabilities,
                        token: account.id == "2"
                            ? MockAPIServer.secondAccountToken : "mock-access-token")
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
