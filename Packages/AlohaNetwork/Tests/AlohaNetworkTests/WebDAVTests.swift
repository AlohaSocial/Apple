// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import AlohaNetwork

@Suite("WebDAV multi-status parsing")
struct WebDAVParsingTests {

    private let root = "/remote.php/dav/files/alice/"

    private var body: Data {
        Data(
            """
            <?xml version="1.0"?>
            <d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns" xmlns:nc="http://nextcloud.org/ns">
              <d:response>
                <d:href>/remote.php/dav/files/alice/</d:href>
                <d:propstat><d:prop>
                  <d:resourcetype><d:collection/></d:resourcetype>
                </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
              </d:response>
              <d:response>
                <d:href>/remote.php/dav/files/alice/Photos/</d:href>
                <d:propstat><d:prop>
                  <d:resourcetype><d:collection/></d:resourcetype>
                  <oc:fileid>1234</oc:fileid>
                </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
              </d:response>
              <d:response>
                <d:href>/remote.php/dav/files/alice/holiday%20snap.jpg</d:href>
                <d:propstat><d:prop>
                  <d:getlastmodified>Tue, 16 Sep 2026 10:11:12 GMT</d:getlastmodified>
                  <d:getcontentlength>204800</d:getcontentlength>
                  <d:getcontenttype>image/jpeg</d:getcontenttype>
                  <d:resourcetype/>
                  <oc:fileid>5678</oc:fileid>
                  <nc:has-preview>true</nc:has-preview>
                </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
              </d:response>
            </d:multistatus>
            """.utf8)
    }

    @Test("Directories and files are distinguished")
    func parsesEntries() throws {
        let files = try MultiStatusParser.parse(body, rootPath: root)

        // The root entry is present; the client filters it out by path.
        let named = files.filter { !$0.name.isEmpty }
        #expect(named.count == 2)

        let folder = try #require(named.first { $0.name == "Photos" })
        #expect(folder.isDirectory)

        let photo = try #require(named.first { $0.name == "holiday snap.jpg" })
        #expect(photo.isDirectory == false)
        #expect(photo.size == 204_800)
        #expect(photo.contentType == "image/jpeg")
        #expect(photo.fileID == "5678")
        #expect(photo.hasPreview)
    }

    /// The path is what `POST /api/v1/media/from-file` takes, so it has to be
    /// relative to the user's own files root and percent-decoded.
    @Test("Paths are relative to the files root and decoded")
    func pathsAreRelative() throws {
        let files = try MultiStatusParser.parse(body, rootPath: root)
        let photo = try #require(files.first { $0.name == "holiday snap.jpg" })
        #expect(photo.path == "holiday snap.jpg")

        let folder = try #require(files.first { $0.name == "Photos" })
        #expect(folder.path == "Photos")
    }

    @Test("Modification dates parse from RFC 1123")
    func parsesDates() throws {
        let files = try MultiStatusParser.parse(body, rootPath: root)
        let photo = try #require(files.first { $0.name == "holiday snap.jpg" })
        #expect(photo.modifiedAt != nil)
    }

    @Test("Malformed XML is an error rather than a crash")
    func malformedBody() {
        #expect(throws: (any Error).self) {
            try MultiStatusParser.parse(Data("<not xml".utf8), rootPath: root)
        }
    }

    @Test("Only media the server accepts is offered as an attachment")
    func attachmentFiltering() {
        let accepted = ["image/jpeg", "video/mp4"]

        let photo = NextcloudFile(
            path: "a.jpg", name: "a.jpg", isDirectory: false, contentType: "image/jpeg")
        let document = NextcloudFile(
            path: "a.pdf", name: "a.pdf", isDirectory: false, contentType: "application/pdf")
        let folder = NextcloudFile(path: "Photos", name: "Photos", isDirectory: true)

        #expect(photo.isAttachable(acceptedTypes: accepted))
        #expect(document.isAttachable(acceptedTypes: accepted) == false)
        #expect(folder.isAttachable(acceptedTypes: accepted) == false)
    }
}

@Suite("Nextcloud credentials")
struct NextcloudCredentialTests {

    @Test("An app password is sent as HTTP Basic, which is what WebDAV expects")
    func basicAuthorization() {
        let credentials = NextcloudLoginFlow.Credentials(
            server: URL(string: "https://cloud.example")!,
            loginName: "alice", appPassword: "secret")

        #expect(credentials.basicAuthorization.hasPrefix("Basic "))
        let encoded = credentials.basicAuthorization.dropFirst("Basic ".count)
        let decoded = String(data: Data(base64Encoded: String(encoded))!, encoding: .utf8)
        #expect(decoded == "alice:secret")
    }
}
