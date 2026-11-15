// SPDX-License-Identifier: MIT

import Foundation
import OSLog

/// One entry in a Nextcloud Files listing.
public struct NextcloudFile: Sendable, Hashable, Identifiable {
    /// The path relative to the user's own files root — which is exactly what
    /// `POST /api/v1/media/from-file` takes.
    public var path: String
    public var name: String
    public var isDirectory: Bool
    public var size: Int
    public var contentType: String?
    public var modifiedAt: Date?
    /// Nextcloud's own file id, used for the preview endpoint.
    public var fileID: String?
    public var hasPreview: Bool
    /// Changes whenever the file's content does. What lets draft sync skip
    /// downloading a file it already has.
    public var etag: String?

    public var id: String { path }

    public init(
        path: String, name: String, isDirectory: Bool, size: Int = 0,
        contentType: String? = nil, modifiedAt: Date? = nil,
        fileID: String? = nil, hasPreview: Bool = false, etag: String? = nil
    ) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.contentType = contentType
        self.modifiedAt = modifiedAt
        self.fileID = fileID
        self.hasPreview = hasPreview
        self.etag = etag
    }

    /// Whether this is worth offering as a post attachment.
    public func isAttachable(acceptedTypes: [String]) -> Bool {
        guard !isDirectory, let contentType else { return false }
        if acceptedTypes.isEmpty {
            return contentType.hasPrefix("image/") || contentType.hasPrefix("video/")
                || contentType.hasPrefix("audio/")
        }
        return acceptedTypes.contains(contentType)
    }
}

/// Reads and writes a Nextcloud's Files over WebDAV.
///
/// Deliberately narrow. Reading exists so somebody can pick a file that is
/// already on their server and attach it without it travelling to the phone
/// and back (docs/07 §6). Writing exists for the few things this app keeps in
/// the person's own files: synced drafts and saved media (docs/14 §7), each
/// in a folder of its own under `Aloha Social/`. It is not a file manager.
public struct WebDAVClient: Sendable {
    private let credentials: NextcloudLoginFlow.Credentials
    private let transport: any HTTPTransport
    private let logger = Logger(subsystem: "social.aloha.app", category: "webdav")

    public init(
        credentials: NextcloudLoginFlow.Credentials,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.credentials = credentials
        self.transport = transport
    }

    public enum WebDAVError: Error, Sendable {
        case unauthorised
        case notFound
        case malformedResponse
        case transport(Int)
        /// A conditional write found the condition false: something is
        /// already at that path (`If-None-Match: *`).
        case alreadyExists
    }

    /// Each segment is appended as it is and encoded once, by `URL`: one
    /// encoded here first would arrive as `%25…`, a login name with a space
    /// or an accent naming a folder that does not exist.
    ///
    /// The path is named by the Nextcloud user ID, not the login name: the
    /// two differ when the server lets people sign in by email address or
    /// through LDAP.
    private var filesRoot: URL {
        credentials.server.appending(path: "remote.php/dav/files")
            .appending(component: credentials.filesUserID)
    }

    /// The URL of a path relative to the user's files root, one component
    /// at a time so each is encoded exactly once.
    func url(for path: String) -> URL {
        var url = filesRoot
        for component in Self.trimmed(path).split(separator: "/") where !component.isEmpty {
            url = url.appending(component: String(component))
        }
        return url
    }

    static func trimmed(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// A request against the user's files, signed with the app password.
    ///
    /// Never answered from the URL cache: a draft read back from a cached
    /// `GET` is a draft from before the last sync, and Nextcloud's WebDAV
    /// answers carry an `ETag` but no `Cache-Control` that would rule out a
    /// heuristic reuse.
    func request(_ method: String, path: String) -> URLRequest {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(credentials.basicAuthorization, forHTTPHeaderField: "Authorization")
        return request
    }

    /// The status codes every WebDAV call shares the meaning of.
    private static func check(_ status: Int) throws {
        switch status {
        case 200..<300: return
        case 401, 403: throw WebDAVError.unauthorised
        case 404: throw WebDAVError.notFound
        case 412: throw WebDAVError.alreadyExists
        default: throw WebDAVError.transport(status)
        }
    }

    /// `PROPFIND` with `Depth: 1` — one directory, not the whole tree.
    public func list(path: String) async throws -> [NextcloudFile] {
        let trimmed = Self.trimmed(path)
        var request = request("PROPFIND", path: path)
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.propfindBody.utf8)

        let (data, response) = try await transport.send(request)
        try Self.check(response.statusCode)

        // Decoded, as each `href` is before it is compared with it: Nextcloud
        // encodes more than `URL` does (`@`, for one), so the encoded forms
        // need not match even when the paths do.
        let parsed = try MultiStatusParser.parse(
            data, rootPath: filesRoot.path(percentEncoded: false))
        // The first entry is the directory itself; a listing of it is the rest.
        return parsed.filter { $0.path != trimmed }
    }

    /// `GET`: one file's bytes, for the small files this app writes itself.
    /// Media is never read this way — it would be held whole in memory.
    public func download(path: String) async throws -> Data {
        let (data, response) = try await transport.send(request("GET", path: path))
        try Self.check(response.statusCode)
        return data
    }

    /// `PUT`, replacing whatever is there. Answers the new `ETag`, when the
    /// server sends one, so the next listing can tell this write from the
    /// next device's.
    @discardableResult
    public func upload(_ data: Data, to path: String, contentType: String) async throws -> String? {
        var request = request("PUT", path: path)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        let (_, response) = try await transport.send(request)
        try Self.check(response.statusCode)
        return Self.etag(of: response)
    }

    /// `DELETE`. Something already gone is what was asked for.
    public func delete(path: String) async throws {
        let (_, response) = try await transport.send(request("DELETE", path: path))
        if response.statusCode == 404 { return }
        try Self.check(response.statusCode)
    }

    /// `MKCOL` for each folder along `path` that is not there yet, so
    /// `Aloha Social/Drafts` can be asked for in one call on a Nextcloud
    /// that has neither. `405 Method Not Allowed` is WebDAV's answer for a
    /// folder that already exists, which is the outcome wanted.
    public func createFolder(path: String) async throws {
        var built = ""
        for component in Self.trimmed(path).split(separator: "/") where !component.isEmpty {
            built += built.isEmpty ? String(component) : "/\(component)"
            let (_, response) = try await transport.send(request("MKCOL", path: built))
            if response.statusCode == 405 { continue }
            try Self.check(response.statusCode)
        }
    }

    /// Nextcloud sends both `ETag` and `OC-ETag`; either will do, quoted or
    /// not — the value is only ever compared with another of its kind.
    static func etag(of response: HTTPURLResponse) -> String? {
        let raw =
            response.value(forHTTPHeaderField: "OC-ETag")
            ?? response.value(forHTTPHeaderField: "ETag")
        return raw.map(normalisedETag)
    }

    /// A weak-validator prefix and the quotes are spelling, not identity: a
    /// listing and a `PUT` answer can write the same tag differently.
    static func normalisedETag(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("W/") { value.removeFirst(2) }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    /// A thumbnail for the picker. Nextcloud's own preview endpoint, so a
    /// 200 MB video costs a few kilobytes to show.
    public func previewURL(for file: NextcloudFile, size: Int = 256) -> URL? {
        guard let fileID = file.fileID, file.hasPreview else { return nil }
        var components = URLComponents(
            url: credentials.server.appending(path: "index.php/core/preview"),
            resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "fileId", value: fileID),
            URLQueryItem(name: "x", value: String(size)),
            URLQueryItem(name: "y", value: String(size)),
            URLQueryItem(name: "a", value: "1"),
        ]
        return components?.url
    }

    public var authorizationHeader: String { credentials.basicAuthorization }

    /// Only the properties the picker draws. Asking for everything makes a
    /// large folder noticeably slower to list.
    static let propfindBody = """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns" xmlns:nc="http://nextcloud.org/ns">
          <d:prop>
            <d:getlastmodified/>
            <d:getcontentlength/>
            <d:getcontenttype/>
            <d:getetag/>
            <d:resourcetype/>
            <oc:fileid/>
            <nc:has-preview/>
          </d:prop>
        </d:propfind>
        """
}

/// Parses a WebDAV `207 Multi-Status` body.
///
/// Hand-written for the same reason the HTML parser is: `XMLParser` is the
/// platform's own and needs no dependency, and the document shape here is
/// small and fixed.
enum MultiStatusParser {

    static func parse(_ data: Data, rootPath: String) throws -> [NextcloudFile] {
        let delegate = Delegate(rootPath: rootPath)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        guard parser.parse() else { throw WebDAVClient.WebDAVError.malformedResponse }
        return delegate.files
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        private let rootPath: String
        private(set) var files: [NextcloudFile] = []

        private var element = ""
        private var text = ""
        private var href = ""
        private var isDirectory = false
        private var size = 0
        private var contentType: String?
        private var modifiedAt: Date?
        private var fileID: String?
        private var hasPreview = false
        private var etag: String?

        init(rootPath: String) {
            self.rootPath = rootPath
        }

        func parser(
            _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
            qualifiedName: String?, attributes: [String: String]
        ) {
            element = name
            text = ""
            if name == "response" {
                href = ""
                isDirectory = false
                size = 0
                contentType = nil
                modifiedAt = nil
                fileID = nil
                hasPreview = false
                etag = nil
            }
            if name == "collection" { isDirectory = true }
        }

        func parser(_ parser: XMLParser, foundCharacters characters: String) {
            text += characters
        }

        func parser(
            _ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
            qualifiedName: String?
        ) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)

            switch name {
            case "href": href = value
            case "getcontentlength": size = Int(value) ?? 0
            case "getcontenttype": contentType = value.isEmpty ? nil : value
            case "getlastmodified": modifiedAt = Self.rfc1123.date(from: value)
            case "fileid": fileID = value.isEmpty ? nil : value
            case "has-preview": hasPreview = value == "true"
            case "getetag": etag = value.isEmpty ? nil : WebDAVClient.normalisedETag(value)
            case "response":
                if let file = makeFile() { files.append(file) }
            default: break
            }
            text = ""
        }

        private func makeFile() -> NextcloudFile? {
            guard let decoded = href.removingPercentEncoding else { return nil }
            guard decoded.hasPrefix(rootPath) else { return nil }

            var relative = String(decoded.dropFirst(rootPath.count))
            while relative.hasPrefix("/") { relative.removeFirst() }
            while relative.hasSuffix("/") { relative.removeLast() }

            let name = relative.split(separator: "/").last.map(String.init) ?? ""
            guard !relative.isEmpty || !name.isEmpty else {
                // The root itself, which the caller filters out.
                return NextcloudFile(path: "", name: "", isDirectory: true)
            }

            return NextcloudFile(
                path: relative, name: name, isDirectory: isDirectory, size: size,
                contentType: contentType, modifiedAt: modifiedAt,
                fileID: fileID, hasPreview: hasPreview, etag: etag)
        }

        static let rfc1123: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            return formatter
        }()
    }
}
