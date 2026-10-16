// SPDX-License-Identifier: MIT

import Foundation

/// What actually puts bytes on the wire. The one seam the mock server uses, so
/// every configuration in docs/12 §2 can be exercised without a network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    public init(configuration: URLSessionConfiguration = .aloha) {
        self.init(session: URLSession(configuration: configuration))
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
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
}

public enum AlohaUserAgent {
    public static let value = "AlohaSocial/1.0 (+https://github.com/AlohaSocial/Apple)"
}
