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

/// Answers every PROPFIND with one listing, and keeps the requests.
private actor ListingTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    let listing: String

    init(listing: String) { self.listing = listing }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 207, httpVersion: "HTTP/1.1", headerFields: [:])!
        return (Data(listing.utf8), response)
    }
}

@Suite("WebDAV paths")
struct WebDAVPathTests {

    /// Nextcloud writes its hrefs with lower-case escapes and encodes more
    /// than `URL` does; only the decoded paths are the same.
    private let listing = """
        <?xml version="1.0"?>
        <d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
          <d:response>
            <d:href>/nextcloud/remote.php/dav/files/j%c3%b6rg%20m_1/Fotos%20%26%20Clips/</d:href>
            <d:propstat><d:prop>
              <d:resourcetype><d:collection/></d:resourcetype>
            </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
          </d:response>
          <d:response>
            <d:href>/nextcloud/remote.php/dav/files/j%c3%b6rg%20m_1/Fotos%20%26%20Clips/%f0%9f%8c%ba%20Strand.jpg</d:href>
            <d:propstat><d:prop>
              <d:getcontenttype>image/jpeg</d:getcontenttype>
              <d:resourcetype/>
            </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
          </d:response>
        </d:multistatus>
        """

    @Test("The user and every folder are encoded once, and the listing is read back relative")
    func listEncodesOnce() async throws {
        let transport = ListingTransport(listing: listing)
        let client = WebDAVClient(
            credentials: NextcloudLoginFlow.Credentials(
                server: URL(string: "https://cloud.example.test/nextcloud/")!,
                loginName: "jörg m_1", appPassword: "secret"),
            transport: transport)

        let files = try await client.list(path: "/Fotos & Clips/")

        let url = try #require(await transport.requests.first?.url)
        #expect(
            url.path() == "/nextcloud/remote.php/dav/files/j%C3%B6rg%20m_1/Fotos%20&%20Clips")
        #expect(url.path(percentEncoded: false).contains("%") == false)
        // The folder itself is left out; the file is relative to the files
        // root and decoded, as `api/v1/media/from-file` takes it.
        #expect(files.map(\.path) == ["Fotos & Clips/🌺 Strand.jpg"])
        #expect(files.first?.name == "🌺 Strand.jpg")
    }
}

@Suite("Nextcloud user ID")
struct NextcloudUserIDTests {

    private let server = URL(string: "https://cloud.example.test/")!

    /// An email login whose files live under the account's user ID.
    @Test("Files are listed under the user ID, not the login name")
    func listsUnderUserID() async throws {
        let transport = ListingTransport(
            listing: """
                <?xml version="1.0"?>
                <d:multistatus xmlns:d="DAV:">
                  <d:response>
                    <d:href>/remote.php/dav/files/a.jones/</d:href>
                    <d:propstat><d:prop>
                      <d:resourcetype><d:collection/></d:resourcetype>
                    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
                  </d:response>
                  <d:response>
                    <d:href>/remote.php/dav/files/a.jones/beach.jpg</d:href>
                    <d:propstat><d:prop>
                      <d:getcontenttype>image/jpeg</d:getcontenttype>
                      <d:resourcetype/>
                    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
                  </d:response>
                </d:multistatus>
                """)
        let client = WebDAVClient(
            credentials: NextcloudLoginFlow.Credentials(
                server: server, loginName: "alice@example.com", appPassword: "secret",
                userID: "a.jones"),
            transport: transport)

        let files = try await client.list(path: "")

        let url = try #require(await transport.requests.first?.url)
        #expect(url.path() == "/remote.php/dav/files/a.jones")
        #expect(files.map(\.path) == ["beach.jpg"])
    }

    @Test("Credentials stored before the user ID was kept still decode, and fall back to the login")
    func legacyCredentialsDecode() throws {
        let stored = Data(
            #"{"server":"https://cloud.example.test/","loginName":"alice","appPassword":"secret"}"#
                .utf8)
        let credentials = try JSONDecoder().decode(
            NextcloudLoginFlow.Credentials.self, from: stored)
        #expect(credentials.userID == nil)
        #expect(credentials.filesUserID == "alice")
    }

    @Test("The user ID is read from the OCS user endpoint, with the OCS header")
    func readsUserID() async throws {
        let transport = OCSUserTransport(status: 200, id: "a.jones")
        let flow = NextcloudLoginFlow(transport: transport)
        let credentials = NextcloudLoginFlow.Credentials(
            server: server, loginName: "alice@example.com", appPassword: "secret")

        #expect(await flow.userID(for: credentials) == "a.jones")

        let request = try #require(await transport.requests.first)
        #expect(request.url?.path() == "/ocs/v2.php/cloud/user")
        #expect(request.url?.query() == "format=json")
        #expect(request.value(forHTTPHeaderField: "OCS-APIRequest") == "true")
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        #expect(authorization == credentials.basicAuthorization)
    }

    @Test("A server that will not say leaves the user ID unknown")
    func unknownUserID() async {
        let flow = NextcloudLoginFlow(transport: OCSUserTransport(status: 404, id: nil))
        let credentials = NextcloudLoginFlow.Credentials(
            server: server, loginName: "alice", appPassword: "secret")
        #expect(await flow.userID(for: credentials) == nil)
    }

    @Test("Approving the login flow brings back the user ID with the app password")
    func approvalCarriesUserID() async throws {
        let transport = OCSUserTransport(status: 200, id: "a.jones")
        let flow = NextcloudLoginFlow(transport: transport)
        let start = NextcloudLoginFlow.Start(
            loginURL: server.appending(path: "login/v2/flow/abc"),
            pollToken: "token",
            pollEndpoint: server.appending(path: "login/v2/poll"))

        let credentials = try await flow.awaitApproval(start, timeout: 5, interval: 0)

        #expect(credentials.loginName == "alice@example.com")
        #expect(credentials.userID == "a.jones")
        #expect(credentials.filesUserID == "a.jones")
    }
}

/// Answers the login-flow poll with an app password, and the OCS user
/// endpoint with `id` — or with `status` alone when there is no id.
private actor OCSUserTransport: HTTPTransport {
    private(set) var requests: [URLRequest] = []
    let status: Int
    let id: String?

    init(status: Int, id: String?) {
        self.status = status
        self.id = id
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = request.url!
        if url.path().hasSuffix("login/v2/poll") {
            let body = #"""
                {"server":"https://cloud.example.test/","loginName":"alice@example.com","appPassword":"secret"}
                """#
            return (Data(body.utf8), Self.response(url, 200))
        }
        guard let id else { return (Data(), Self.response(url, status)) }
        let body = #"{"ocs":{"meta":{"status":"ok","statuscode":200},"data":{"id":"\#(id)"}}}"#
        return (Data(body.utf8), Self.response(url, status))
    }

    private static func response(_ url: URL, _ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!
    }
}
