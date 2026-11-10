// SPDX-License-Identifier: MIT

// Debug builds only, like the mock API it belongs to.
#if DEBUG
    import Foundation
    import ImageIO
    import Network
    import OSLog
    #if canImport(CoreGraphics)
        import CoreGraphics
    #endif

    /// A real socket for the one thing the in-process mock cannot answer:
    /// video.
    ///
    /// `MockAPIServer` is an `HTTPTransport`, so every request the app makes
    /// through its own client — JSON, images, uploads — is answered inside the
    /// process without a network. AVFoundation has no such seam: an
    /// `AVPlayerItem` opens its own connection, which is why every video in
    /// every tour ended on "this video could not be played" while the poster
    /// above it loaded. This server gives the player somewhere real to go, on
    /// loopback, with the same rules a self-hosted instance applies: media is
    /// served only to a request that carries the account's bearer token.
    ///
    /// Two rungs, because the app has two: `/media/<id>.mp4` for the file and
    /// `/media/hls/<id>/…` for the ladder. Both refuse a request without the
    /// header, so a player that forgets it gets exactly what a real server
    /// would give it.
    public final class MockMediaServer: @unchecked Sendable {
        /// What the tours can ask the server to do wrong, so the fallback
        /// chain and the failure card are exercised rather than assumed.
        public struct Behaviour: OptionSet, Sendable {
            public let rawValue: Int
            public init(rawValue: Int) { self.rawValue = rawValue }

            /// The file answers 401 however good the token is: the ladder
            /// behind it has to play.
            public static let refuseFile = Behaviour(rawValue: 1 << 0)
            /// The ladder answers 401: the file in front of it has to play.
            public static let refuseLadder = Behaviour(rawValue: 1 << 1)
            /// The file accepts the connection and never answers: the stall
            /// deadline has to give up on it.
            public static let stallFile = Behaviour(rawValue: 1 << 2)
            /// Neither rung plays, so the error card must appear.
            public static let refuseEverything: Behaviour = [.refuseFile, .refuseLadder]
        }

        /// Known once the listener reports `.ready`, which is before the
        /// initializer returns — the property starts at zero only so the
        /// connection handler can capture `self` first.
        public private(set) var port: UInt16 = 0
        /// The bearer token the mock API signs in with.
        public let token: String
        private let behaviour: Behaviour
        private let listener: NWListener
        private let queue = DispatchQueue(label: "social.aloha.mock-media")
        private let files: [String: Data]
        private let poster: Data
        /// What the player asked for, so a rung that ends on the failure card
        /// can be read back from Console rather than guessed at.
        private let logger = Logger(
            subsystem: "social.aloha.mock-media", category: "http")

        /// Starts a listener on a free loopback port and waits until it is
        /// ready, so callers have a URL to hand to the fixtures.
        public init?(
            token: String, behaviour: Behaviour = [],
            port: UInt16 = 0
        ) {
            let endpoint =
                port == 0 ? NWEndpoint.Port.any : (NWEndpoint.Port(rawValue: port) ?? .any)
            guard let listener = try? NWListener(using: .tcp, on: endpoint) else { return nil }

            self.behaviour = behaviour
            self.token = token
            self.listener = listener
            self.files = Self.loadFixtures()
            self.poster = Self.makePoster()
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }

            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { state in
                if case .ready = state { ready.signal() }
            }
            listener.start(queue: queue)
            guard ready.wait(timeout: .now() + 5) == .success,
                let assigned = listener.port?.rawValue
            else {
                listener.cancel()
                return nil
            }
            self.port = assigned
        }

        public func stop() { listener.cancel() }

        // MARK: - Fixtures

        /// The resources are copied into the built bundle flat: `hls/master.m3u8`
        /// arrives as `master.m3u8` and `hls/seg0.ts` as `seg0.ts`. Each file is
        /// therefore keyed by both its repository path and its name, so a
        /// lookup can name whichever the mock serves.
        private static func loadFixtures() -> [String: Data] {
            let manager = FileManager.default
            guard let root = Bundle.module.resourceURL,
                let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: nil)
            else { return [:] }

            var loaded: [String: Data] = [:]
            var directory: URL?
            for case let file as URL in enumerator {
                if file.lastPathComponent == "video.mp4" {
                    directory = file.deletingLastPathComponent()
                    break
                }
            }
            guard let directory,
                let files = manager.enumerator(at: directory, includingPropertiesForKeys: nil)
            else { return [:] }
            for case let file as URL in files where file.hasDirectoryPath == false {
                let key = file.path.replacingOccurrences(
                    of: directory.path + "/", with: "")
                if let data = try? Data(contentsOf: file) {
                    loaded[key] = data
                    // `.process` flattens subdirectories in the built bundle
                    // for some toolchains, so `hls/master.m3u8` can arrive as
                    // `master.m3u8`. Keep both keys: the lookup names the
                    // fixture the way it sits in the repository.
                    loaded[file.lastPathComponent] = data
                }
            }
            return loaded
        }

        /// A 4:3 poster in the same warm grey the mock's other images use, so a
        /// screenshot of the player before it starts looks like the rest.
        private static func makePoster() -> Data {
            guard
                let context = CGContext(
                    data: nil, width: 320, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return Data() }
            context.setFillColor(red: 0.45, green: 0.5, blue: 0.6, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
            guard let image = context.makeImage() else { return Data() }
            let data = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    data, "public.png" as CFString, 1, nil)
            else { return Data() }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
            return data as Data
        }

        // MARK: - Connections

        private func accept(_ connection: NWConnection) {
            connection.start(queue: queue)
            read(connection, buffer: Data())
        }

        private func read(_ connection: NWConnection, buffer: Data) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
                [weak self] chunk, _, isComplete, error in
                guard let self else { return }
                var accumulated = buffer
                if let chunk { accumulated.append(chunk) }
                if let error {
                    _ = error
                    connection.cancel()
                    return
                }
                if let headerEnd = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                    let head = String(decoding: accumulated[..<headerEnd.lowerBound], as: UTF8.self)
                    self.answer(head, on: connection)
                    return
                }
                if isComplete || accumulated.count > 32 * 1024 {
                    connection.cancel()
                    return
                }
                self.read(connection, buffer: accumulated)
            }
        }

        private func answer(_ head: String, on connection: NWConnection) {
            let lines = head.components(separatedBy: "\r\n")
            let request = lines.first?.split(separator: " ") ?? []
            guard request.count >= 2 else { return close(connection) }
            let method = String(request[0])
            let path = String(request[1])
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let separator = line.firstIndex(of: ":") else { continue }
                headers[line[..<separator].lowercased()] = String(
                    line[line.index(after: separator)...]
                ).trimmingCharacters(in: .whitespaces)
            }

            // Pictures and the ladder stay open, the way a Mastodon or
            // Nextcloud instance serves derivatives from its own CDN: the
            // app's image loader has no token to attach, and AVFoundation's
            // HLS loader fetches the playlist and every segment itself,
            // dropping the asset's headers — a token-protected ladder could
            // never play. The original file is the account's, and that is the
            // request this server exists to refuse.
            let isDerivative =
                path.hasSuffix(".jpg") || path.hasSuffix(".png") || path.contains("/hls/")
            let authorized = headers["authorization"] == "Bearer \(token)"
            guard authorized || isDerivative else {
                return send(
                    connection, status: 401, reason: "Unauthorized",
                    headers: ["WWW-Authenticate": "Bearer"], body: Data(), method: method)
            }

            logger.notice("\(method, privacy: .public) \(path, privacy: .public)")
            record("\(method) \(path)")

            if path.contains(".mp4") {
                if behaviour.contains(.stallFile) {
                    // Accepting the connection and never answering is what a
                    // host behind a black hole does; the player's stall
                    // deadline is what has to notice.
                    return
                }
                if behaviour.contains(.refuseFile) {
                    return send(
                        connection, status: 401, reason: "Unauthorized", headers: [:],
                        body: Data(), method: method)
                }
                guard let data = files["video.mp4"] else { return notFound(connection, method) }
                return sendMedia(
                    connection, data: data, contentType: "video/mp4", method: method,
                    range: headers["range"])
            }

            if path.contains("/hls/") {
                if behaviour.contains(.refuseLadder) {
                    return send(
                        connection, status: 401, reason: "Unauthorized", headers: [:],
                        body: Data(), method: method)
                }
                let name = path.split(separator: "/").last.map(String.init) ?? ""
                if name.hasSuffix(".m3u8") {
                    // The playlists name their segments relatively, so a
                    // segment request arrives under the same directory. The
                    // built bundle keeps the files flat (see loadFixtures), so
                    // try the bare name as well as the repository's path.
                    let fixture = path.contains("master") ? "master.m3u8" : "index.m3u8"
                    guard let data = files[fixture] ?? files["hls/\(fixture)"] else {
                        return notFound(connection, method)
                    }
                    return send(
                        connection, status: 200, reason: "OK",
                        headers: ["Content-Type": "application/vnd.apple.mpegurl"],
                        body: data, method: method)
                }
                if name.hasSuffix(".ts"), let data = files[name] ?? files["hls/\(name)"] {
                    return send(
                        connection, status: 200, reason: "OK",
                        headers: ["Content-Type": "video/mp2t"], body: data, method: method)
                }
                return notFound(connection, method)
            }

            if path.hasSuffix(".jpg") || path.hasSuffix(".png") {
                return send(
                    connection, status: 200, reason: "OK",
                    headers: ["Content-Type": "image/png"], body: poster, method: method)
            }
            notFound(connection, method)
        }

        private func notFound(_ connection: NWConnection, _ method: String) {
            logger.error("404 \(method, privacy: .public)")
            record("404 \(method)")
            send(
                connection, status: 404, reason: "Not Found", headers: [:], body: Data(),
                method: method)
        }

        /// A whole file, or the slice a `Range` asked for. AVFoundation will
        /// not play a file it cannot seek, so a server that ignores ranges
        /// serves a video that never starts.
        private func sendMedia(
            _ connection: NWConnection, data: Data, contentType: String, method: String,
            range: String?
        ) {
            var headers = ["Content-Type": contentType, "Accept-Ranges": "bytes"]
            var body = data
            var status = 200
            var reason = "OK"

            if let range, let slice = Self.slice(data, for: range) {
                body = slice
                status = 206
                reason = "Partial Content"
                headers["Content-Range"] =
                    "bytes \(range.split(separator: "=").last ?? "")/\(data.count)"
            }
            headers["Content-Length"] = String(body.count)
            send(
                connection, status: status, reason: reason, headers: headers, body: body,
                method: method)
        }

        private static func slice(_ data: Data, for range: String) -> Data? {
            guard range.hasPrefix("bytes=") else { return nil }
            let parts = range.dropFirst("bytes=".count).split(
                separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let start = Int(parts[0]) ?? 0
            let end = parts[1].isEmpty ? data.count - 1 : (Int(parts[1]) ?? data.count - 1)
            guard start <= end, start < data.count else { return nil }
            let upper = Swift.min(end, data.count - 1)
            return data.subdata(in: start..<(upper + 1))
        }

        private func send(
            _ connection: NWConnection, status: Int, reason: String,
            headers: [String: String], body: Data, method: String
        ) {
            var response = "HTTP/1.1 \(status) \(reason)\r\n"
            var all = headers
            all["Connection"] = "close"
            if all["Content-Length"] == nil { all["Content-Length"] = String(body.count) }
            for (name, value) in all.sorted(by: { $0.key < $1.key }) {
                response += "\(name): \(value)\r\n"
            }
            response += "\r\n"
            var payload = Data(response.utf8)
            if method != "HEAD" { payload.append(body) }
            connection.send(
                content: payload,
                completion: .contentProcessed { _ in connection.cancel() })
        }

        /// Request lines also go to a file in the app's container, where a
        /// failed tour can be read back with `simctl get_app_container`; the
        /// simulator's unified log is not always readable from the test host.
        private func record(_ line: String) {
            guard
                let directory = FileManager.default.urls(
                    for: .documentDirectory, in: .userDomainMask
                ).first
            else { return }
            let url = directory.appending(path: "mock-media.log")
            let text = Data((line + "\n").utf8)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(text)
                try? handle.close()
            } else {
                try? text.write(to: url)
            }
        }

        private func close(_ connection: NWConnection) {
            send(
                connection, status: 400, reason: "Bad Request", headers: [:], body: Data(),
                method: "GET")
        }
    }
#endif
