// SPDX-License-Identifier: MIT

import AlohaModels
import Foundation
import Testing

@testable import AlohaNetwork

@Suite("Backup endpoints")
struct BackupEndpointTests {

    private let base = URL(string: "https://cloud.example.test/index.php/apps/social/")!

    @Test("Reading the backup is a GET under the API base, with the bearer token")
    func settings() {
        let endpoint = Endpoint.backup.settings
        #expect(endpoint.method == .get)
        #expect(endpoint.authentication == .bearer)
        #expect(
            endpoint.url(base: base)?.absoluteString
                == "https://cloud.example.test/index.php/apps/social/api/v1/social/backup")
    }

    @Test("A change is a PATCH with a JSON body of only the changed keys")
    func update() throws {
        let endpoint = Endpoint.backup.update(SocialBackupChange(enabled: true, frequency: .daily))
        #expect(endpoint.method == .patch)
        #expect(endpoint.path == "api/v1/social/backup")
        guard case .json(let data) = endpoint.body else {
            Issue.record("expected a JSON body")
            return
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["enabled"] as? Bool == true)
        #expect(object?["frequency"] as? String == "daily")
        #expect(object?.count == 2)
    }

    @Test("Backing up now is a POST to run")
    func run() {
        let endpoint = Endpoint.backup.run
        #expect(endpoint.method == .post)
        #expect(endpoint.path == "api/v1/social/backup/run")
    }

    @Test("The 202 answer to run decodes as the whole object")
    func runAnswer() throws {
        let backup = try AlohaJSON.decoder.decode(
            SocialBackup.self,
            from: Data(
                #"{"enabled": true, "frequency": "weekly", "folder": "Aloha Social Backup", "keep": 4, "last_backup_at": null, "last_error": null, "next_backup_at": "2026-11-22T03:00:00Z", "running": true}"#
                    .utf8))
        #expect(backup.running)
        #expect(backup.nextBackupAt != nil)
    }

    @Test("A 404 is what hides the screen: an older or a non-Aloha server")
    func notFound() async throws {
        let client = APIClient(
            accountID: UUID(), apiBase: base, accessToken: "token",
            transport: StatusTransport(status: 404))
        await #expect(throws: APIError.self) {
            _ = try await client.decode(SocialBackup.self, from: Endpoint.backup.settings)
        }
        do {
            _ = try await client.decode(SocialBackup.self, from: Endpoint.backup.settings)
        } catch APIError.notFound {
            // As the row expects.
        } catch {
            Issue.record("expected notFound, got \(error)")
        }
    }
}

private struct StatusTransport: HTTPTransport {
    let status: Int

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
        return (Data(#"{"error":"Not found"}"#.utf8), response)
    }
}
