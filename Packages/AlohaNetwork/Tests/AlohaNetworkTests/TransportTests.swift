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
}
