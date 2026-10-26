// SPDX-License-Identifier: MIT

import Foundation

/// What actually puts bytes on the wire. The one seam the mock server uses, so
/// every configuration in docs/12 §2 can be exercised without a network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Sends `request` with its body streamed from `file`: a media upload,
    /// which may take far longer than an API call is allowed to.
    func upload(_ request: URLRequest, fromFile file: URL) async throws -> (Data, HTTPURLResponse)
    /// Forgets every response it kept, which were fetched with somebody's
    /// token — what signing out asks of it.
    func removeCachedResponses()
}

extension HTTPTransport {
    /// Most transports keep nothing.
    public func removeCachedResponses() {}

    /// A transport with no network of its own — the mock server, a test's
    /// recorder — reads the body back and sees an ordinary request.
    public func upload(
        _ request: URLRequest, fromFile file: URL
    ) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.httpBody = try Data(contentsOf: file)
        return try await send(request)
    }
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    private let uploadSession: URLSession

    /// `uploadSession` carries the uploads. A session's resource timeout is
    /// the whole life of a task, and the two minutes an API call gets would
    /// fail a video on a slow uplink however steadily it was going.
    public init(session: URLSession, uploadSession: URLSession = URLSessionTransport.uploads) {
        self.session = session
        self.uploadSession = uploadSession
    }

    public init(configuration: URLSessionConfiguration = .aloha) {
        self.init(session: URLSession(configuration: configuration))
    }

    /// One for the process: an upload leaves nothing to cache, so nothing is
    /// gained by a session per transport.
    public static let uploads = URLSession(configuration: .alohaUploads)

    public func removeCachedResponses() {
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await answer { try await session.data(for: request) }
    }

    public func upload(
        _ request: URLRequest, fromFile file: URL
    ) async throws -> (Data, HTTPURLResponse) {
        try await answer { try await uploadSession.upload(for: request, fromFile: file) }
    }

    private func answer(
        _ task: () async throws -> (Data, URLResponse)
    ) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await task()
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            return (data, http)
        } catch let error as URLError {
            if error.code == .cancelled { throw APIError.cancelled }
            throw APIError.transport(error)
        }
    }
}

extension URLSessionConfiguration {
    public static var aloha: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        // A request made as the app comes back from the background should wait
        // for the radio rather than fail and make the person pull to refresh.
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpAdditionalHeaders = ["User-Agent": AlohaUserAgent.value]
        configuration.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
        return configuration
    }

    /// For media. An upload may take as long as it keeps moving: an hour in
    /// all, and two minutes without a byte either way, which also covers a
    /// server that transcodes before it answers (`api/v1/media`). A stalled
    /// upload still fails within those two minutes.
    public static var alohaUploads: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.httpAdditionalHeaders = ["User-Agent": AlohaUserAgent.value]
        configuration.urlCache = nil
        return configuration
    }
}

public enum AlohaUserAgent {
    public static let value = "AlohaSocial/1.0 (+https://github.com/AlohaSocial/Apple)"
}
