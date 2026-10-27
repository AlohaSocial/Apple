// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaNetwork

/// Keeps apart what was sent as a request and what was streamed from a file,
/// and reads the file while it still exists.
private actor UploadRecordingTransport: HTTPTransport {
    private(set) var sent: [URLRequest] = []
    private(set) var uploaded: [(request: URLRequest, file: URL, body: Data)] = []

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sent.append(request)
        return try Self.answer(request)
    }

    func upload(_ request: URLRequest, fromFile file: URL) async throws -> (Data, HTTPURLResponse) {
        uploaded.append((request, file, try Data(contentsOf: file)))
        return try Self.answer(request)
    }

    private static func answer(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(fileURLWithPath: "/"), statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: [:])
        guard let response else { throw APIError.invalidResponse }
        return (Data(#"{"id": "1", "type": "image"}"#.utf8), response)
    }
}

private actor SendOnlyTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(fileURLWithPath: "/"), statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: [:])
        guard let response else { throw APIError.invalidResponse }
        return (Data("{}".utf8), response)
    }
}

@Suite("Uploads")
struct UploadTests {

    @Test("A media upload is streamed from a file, which is gone afterwards")
    func mediaUploadStreamsFromFile() async throws {
        let transport = UploadRecordingTransport()
        let api = APIClient(
            accountID: UUID(), apiBase: URL(string: "https://cloud.example.test/")!,
            accessToken: "secret", transport: transport)
        let picture = Data(repeating: 0xAB, count: 300_000)
        let endpoint = Endpoint.media.upload(
            data: picture, filename: "a.jpg", mimeType: "image/jpeg", description: "A cat")

        try await api.send(endpoint)

        #expect(await transport.sent.isEmpty)
        let upload = try #require(await transport.uploaded.first)
        #expect(upload.request.httpBody == nil)
        #expect(upload.request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        guard case .multipart(let multipart) = endpoint.body else {
            Issue.record("an upload is multipart")
            return
        }
        #expect(upload.request.value(forHTTPHeaderField: "Content-Type") == multipart.contentType)
        #expect(upload.body == multipart.encoded())
        #expect(!FileManager.default.fileExists(atPath: upload.file.path()))
    }

    @Test("A transport without uploads of its own sees the body as a request's")
    func defaultUploadReadsTheFile() async throws {
        let transport = SendOnlyTransport()
        let api = APIClient(
            accountID: UUID(), apiBase: URL(string: "https://cloud.example.test/")!,
            accessToken: "secret", transport: transport)
        let endpoint = Endpoint.media.upload(
            data: Data(repeating: 1, count: 1024), filename: "a.png", mimeType: "image/png",
            description: nil)

        try await api.send(endpoint)

        let request = try #require(await transport.requests.first)
        guard case .multipart(let multipart) = endpoint.body else {
            Issue.record("an upload is multipart")
            return
        }
        #expect(request.httpBody == multipart.encoded())
    }

    @Test("Uploads get an hour; API calls keep their two minutes")
    func uploadTimeouts() {
        #expect(URLSessionConfiguration.aloha.timeoutIntervalForResource == 120)
        #expect(URLSessionConfiguration.aloha.timeoutIntervalForRequest == 30)
        #expect(URLSessionConfiguration.alohaUploads.timeoutIntervalForResource == 3600)
        #expect(URLSessionConfiguration.alohaUploads.timeoutIntervalForRequest == 120)
        #expect(
            URLSessionTransport.uploads.configuration.timeoutIntervalForResource == 3600)
    }

    @Test("An upload started offline fails at once instead of waiting out the hour")
    func uploadsDoNotWait() {
        #expect(URLSessionConfiguration.alohaUploads.waitsForConnectivity == false)
        #expect(URLSessionConfiguration.aloha.waitsForConnectivity)
    }
}

/// A server inside URLSession: a path with a trailing slash is redirected to
/// the one without, and `/elsewhere` to another host. The redirected request
/// is built as URLSession builds its own, every header but `Authorization`
/// carried over, and every request that arrives is kept for the test to read.
private final class RedirectingProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var arrived: [URLRequest] = []

    static func requests(to host: String) -> [URLRequest] {
        lock.withLock { arrived.filter { $0.url?.host() == host } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.withLock { Self.arrived.append(request) }

        var target: URL?
        if url.path().count > 1, url.path().hasSuffix("/") {
            target = URL(string: String(url.absoluteString.dropLast()))
        } else if url.path() == "/elsewhere" {
            target = URL(string: "https://other.example.test/landing")
        }
        if let target {
            var next = request
            next.url = target
            next.setValue(nil, forHTTPHeaderField: "Authorization")
            let response = HTTPURLResponse(
                url: url, statusCode: 301, httpVersion: "HTTP/1.1",
                headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            return
        }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite("Redirects")
struct RedirectTests {

    private func request(_ url: String) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        return request
    }

    private func redirected(_ from: String, to: String) -> String? {
        SameOriginRedirects.redirect(URLRequest(url: URL(string: to)!), from: request(from))
            .value(forHTTPHeaderField: "Authorization")
    }

    @Test("The token follows a redirect on its own origin, or from http to https on its host")
    func sameOriginKeepsTheToken() {
        let home = "https://cloud.example.test/api/v1/timelines/home"
        #expect(redirected(home + "/", to: home) == "Bearer secret")
        #expect(
            redirected("https://cloud.example.test:443/a", to: "https://CLOUD.example.test/b")
                == "Bearer secret")
        #expect(
            redirected("http://nas.local/api/v1/x", to: "https://nas.local/api/v1/x")
                == "Bearer secret")
    }

    @Test("The token never follows a redirect to another origin")
    func otherOriginsDoNot() {
        #expect(redirected("https://cloud.example.test/a", to: "https://evil.example/a") == nil)
        #expect(
            redirected("https://cloud.example.test/a", to: "https://social.cloud.example.test/a")
                == nil)
        #expect(
            redirected("https://cloud.example.test/a", to: "http://cloud.example.test/a") == nil)
        #expect(
            redirected("https://cloud.example.test/a", to: "https://cloud.example.test:8443/a")
                == nil)
        #expect(redirected("http://nas.local:8080/a", to: "https://nas.local/a") == nil)
        // A header the redirect itself carried to another origin is taken off.
        var carried = URLRequest(url: URL(string: "https://evil.example/a")!)
        carried.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        #expect(
            SameOriginRedirects.redirect(carried, from: request("https://cloud.example.test/a"))
                .value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Through URLSession, a slash redirect keeps the token and a cross-host one drops it")
    func throughURLSession() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectingProtocol.self]
        let transport = URLSessionTransport(
            session: URLSession(configuration: configuration),
            uploadSession: URLSession(configuration: configuration))

        let (_, response) = try await transport.send(
            request("https://redirects.example.test/api/v1/timelines/home/"))
        #expect(response.url?.path() == "/api/v1/timelines/home")
        let arrived = RedirectingProtocol.requests(to: "redirects.example.test")
        #expect(arrived.count == 2)
        #expect(arrived.last?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")

        _ = try await transport.send(request("https://redirects.example.test/elsewhere"))
        let landed = try #require(RedirectingProtocol.requests(to: "other.example.test").last)
        #expect(landed.value(forHTTPHeaderField: "Authorization") == nil)
    }
}
