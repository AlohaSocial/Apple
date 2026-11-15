// SPDX-License-Identifier: MIT

import Foundation
import Synchronization

/// What actually puts bytes on the wire. The one seam the mock server uses, so
/// every configuration in docs/12 §2 can be exercised without a network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Sends `request` with its body streamed from `file`: a media upload,
    /// which may take far longer than an API call is allowed to.
    func upload(_ request: URLRequest, fromFile file: URL) async throws -> (Data, HTTPURLResponse)
    /// Sends `request` without waiting for connectivity: offline, it fails
    /// at once (`Endpoint.waitsForConnectivity`).
    func sendFailingFast(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Forgets every response it kept, which were fetched with somebody's
    /// token — what signing out asks of it.
    func removeCachedResponses()
    /// `upload(_:fromFile:)`, reporting how much of the body has gone, from
    /// 0 to 1: what a "Save to Nextcloud" bar follows.
    func upload(
        _ request: URLRequest, fromFile file: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (Data, HTTPURLResponse)
    /// Fetches into a temporary file the caller owns and removes, reporting
    /// how much has arrived. For a file too large to hold in memory, such as
    /// a video's original.
    func download(
        _ request: URLRequest, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (URL, HTTPURLResponse)
}

extension HTTPTransport {
    /// Most transports keep nothing.
    public func removeCachedResponses() {}

    /// A transport with no network of its own has nothing to wait for.
    public func sendFailingFast(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await send(request)
    }

    /// A transport with no network of its own — the mock server, a test's
    /// recorder — reads the body back and sees an ordinary request.
    public func upload(
        _ request: URLRequest, fromFile file: URL
    ) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.httpBody = try Data(contentsOf: file)
        return try await send(request)
    }

    /// Without a network of its own there is nothing to watch: done is done.
    public func upload(
        _ request: URLRequest, fromFile file: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (Data, HTTPURLResponse) {
        let answer = try await upload(request, fromFile: file)
        progress(1)
        return answer
    }

    public func download(
        _ request: URLRequest, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (URL, HTTPURLResponse) {
        let (data, response) = try await send(request)
        let file = FileManager.default.temporaryDirectory
            .appending(path: "aloha-download-\(UUID().uuidString)")
        try data.write(to: file)
        progress(1)
        return (file, response)
    }
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    private let uploadSession: URLSession
    /// `session`'s configuration, except that it does not wait for
    /// connectivity. `waitsForConnectivity` belongs to a session rather than
    /// a request, so the requests that must not wait need one of their own.
    private let failFastSession: URLSession

    /// `uploadSession` carries the uploads. A session's resource timeout is
    /// the whole life of a task, and the two minutes an API call gets would
    /// fail a video on a slow uplink however steadily it was going.
    public init(session: URLSession, uploadSession: URLSession = URLSessionTransport.uploads) {
        self.session = session
        self.uploadSession = uploadSession
        // A copy: the cache it names is the same object, so a response kept
        // by one session is still forgotten by `removeCachedResponses()`.
        let configuration = session.configuration
        configuration.waitsForConnectivity = false
        self.failFastSession = URLSession(configuration: configuration)
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
        try await answer {
            try await session.data(for: request, delegate: SameOriginRedirects.shared)
        }
    }

    public func sendFailingFast(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await answer {
            try await failFastSession.data(for: request, delegate: SameOriginRedirects.shared)
        }
    }

    public func upload(
        _ request: URLRequest, fromFile file: URL
    ) async throws -> (Data, HTTPURLResponse) {
        try await answer {
            try await uploadSession.upload(
                for: request, fromFile: file, delegate: SameOriginRedirects.shared)
        }
    }

    /// On the transfer session, which gives a large file as long as it keeps
    /// moving rather than an API call's two minutes.
    public func upload(
        _ request: URLRequest, fromFile file: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (Data, HTTPURLResponse) {
        try await answer {
            try await uploadSession.upload(
                for: request, fromFile: file, delegate: TransferProgress(progress))
        }
    }

    public func download(
        _ request: URLRequest, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (URL, HTTPURLResponse) {
        do {
            let (location, response) = try await uploadSession.download(
                for: request, delegate: TransferProgress(progress))
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            // Moved somewhere of the caller's own: the session's file is
            // its to clean up.
            let file = FileManager.default.temporaryDirectory
                .appending(path: "aloha-download-\(UUID().uuidString)")
            try FileManager.default.moveItem(at: location, to: file)
            return (file, http)
        } catch let error as URLError {
            if error.code == .cancelled { throw APIError.cancelled }
            throw APIError.transport(error)
        }
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

/// URLSession takes `Authorization` off every redirected request, the same
/// server's included, so a server that redirects `…/home/` to `…/home`, or
/// http to https on the same host, answered a signed-in request as though
/// nobody were signed in. The credential is put back when the redirect stays
/// on the original request's origin, or moves it from http to https on the
/// same host; to anywhere else it is never sent.
final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = SameOriginRedirects()

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let original = task.originalRequest else { return request }
        return Self.redirect(request, from: original)
    }

    /// The redirected request, with the original's credential where it may go.
    static func redirect(_ request: URLRequest, from original: URLRequest) -> URLRequest {
        var request = request
        guard let from = original.url, let to = request.url,
            to.isSameOriginOrSecureUpgrade(of: from)
        else {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
            return request
        }
        if request.value(forHTTPHeaderField: "Authorization") == nil,
            let credential = original.value(forHTTPHeaderField: "Authorization")
        {
            request.setValue(credential, forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

/// Reports a transfer's progress, from the task's own `Progress`, which
/// counts the body going up for an upload and the bytes coming down for a
/// download alike. Redirects are followed as `SameOriginRedirects` does.
final class TransferProgress: NSObject, URLSessionTaskDelegate, Sendable {
    private let report: @Sendable (Double) -> Void
    private let observation = Mutex<NSKeyValueObservation?>(nil)

    init(_ report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        let report = report
        let token = task.progress.observe(\.fractionCompleted, options: [.new]) { progress, _ in
            report(min(max(progress.fractionCompleted, 0), 1))
        }
        observation.withLock { $0 = token }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let original = task.originalRequest else { return request }
        return SameOriginRedirects.redirect(request, from: original)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
        observation.withLock {
            $0?.invalidate()
            $0 = nil
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
    ///
    /// It does not wait for a network that is not there. Waiting counts only
    /// against the hour, so an upload started offline would spin, and keep
    /// Post disabled, for that long; failing at once lets the person see why
    /// and try again.
    public static var alohaUploads: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
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
