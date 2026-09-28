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

    public var id: String { path }

    public init(
        path: String, name: String, isDirectory: Bool, size: Int = 0,
        contentType: String? = nil, modifiedAt: Date? = nil,
        fileID: String? = nil, hasPreview: Bool = false
    ) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.contentType = contentType
        self.modifiedAt = modifiedAt
        self.fileID = fileID
        self.hasPreview = hasPreview
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

/// Browses a Nextcloud's Files over WebDAV.
///
/// Read-only and deliberately narrow: this exists so somebody can pick a file
/// that is already on their server and attach it without it travelling to the
/// phone and back (docs/07 §6). It is not a file manager.
public struct WebDAVClient: Sendable {
    private let credentials: NextcloudLoginFlow.Credentials
    private let transport: any HTTPTransport
    private let logger = Logger(subsystem: "com.nextcloud.alohasocial", category: "webdav")

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
    }

    private var filesRoot: URL {
        credentials.server.appending(path: "remote.php/dav/files/\(encoded(credentials.loginName))")
    }

    /// `PROPFIND` with `Depth: 1` — one directory, not the whole tree.
    public func list(path: String) async throws -> [NextcloudFile] {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var url = filesRoot
        for component in trimmed.split(separator: "/") where !component.isEmpty {
            url = url.appending(path: String(component))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue(credentials.basicAuthorization, forHTTPHeaderField: "Authorization")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.propfindBody.utf8)

        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 401, 403: throw WebDAVError.unauthorised
        case 404: throw WebDAVError.notFound
        case 200, 207: break
        default: throw WebDAVError.transport(response.statusCode)
        }

        let parsed = try MultiStatusParser.parse(data, rootPath: filesRoot.path())
        // The first entry is the directory itself; a listing of it is the rest.
        return parsed.filter { $0.path != trimmed }
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

    private func encoded(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? component
    }

    /// Only the properties the picker draws. Asking for everything makes a
    /// large folder noticeably slower to list.
    static let propfindBody = """
        <?xml version="1.0" encoding="UTF-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns" xmlns:nc="http://nextcloud.org/ns">
          <d:prop>
            <d:getlastmodified/>
            <d:getcontentlength/>
            <d:getcontenttype/>
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
                fileID: fileID, hasPreview: hasPreview)
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
