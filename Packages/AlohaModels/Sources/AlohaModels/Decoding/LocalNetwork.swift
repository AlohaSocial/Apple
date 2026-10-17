// SPDX-License-Identifier: MIT

import Foundation

/// Which hosts plain `http` may still reach.
///
/// App Transport Security allows cleartext to the local network only
/// (`NSAllowsLocalNetworking`): a Nextcloud on `192.168.1.10`, a `.local` box,
/// `localhost` while developing. Everywhere else a sign-in, a token and every
/// picture would cross the internet readable, so the app refuses `http` for a
/// public host rather than asking ATS for an exception it should not have.
public enum LocalNetwork {
    /// RFC 1918 private IPv4, link-local (169.254/16), loopback, CGNAT
    /// (100.64/10, which home routers hand out too), `.local` and `localhost`,
    /// unqualified names, and IPv6 loopback, link-local and unique-local.
    public static func isLocal(host rawHost: String) -> Bool {
        var host = rawHost.lowercased()
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return false }

        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return true
        }
        if let octets = ipv4(host) {
            switch (octets[0], octets[1]) {
            case (10, _), (127, _), (192, 168), (169, 254): return true
            case (172, 16...31): return true
            case (100, 64...127): return true
            default: return false
            }
        }
        if host.contains(":") {
            // IPv6: loopback, link-local fe80::/10, unique-local fc00::/7.
            if host == "::1" { return true }
            let first = host.split(separator: ":", omittingEmptySubsequences: false).first ?? ""
            guard let value = UInt16(first, radix: 16) else { return false }
            return (value & 0xFFC0) == 0xFE80 || (value & 0xFE00) == 0xFC00
        }
        // An unqualified name (`nas`, `cloud`) only resolves on a local network.
        return !host.contains(".")
    }

    private static func ipv4(_ host: String) -> [Int]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { Int($0) }.filter { (0...255).contains($0) }
        return octets.count == 4 ? octets : nil
    }
}

extension URL {
    /// This address as the app may load it: `https` stays, `http` to a host
    /// on the local network stays, and `http` to anywhere else is asked for
    /// over `https` — which every server in the fediverse speaks, and which
    /// App Transport Security would insist on anyway. A picture, a video or a
    /// card image is loaded in-app, so this is applied to those; a link that
    /// opens in the browser is left as it was.
    public var securedForLoading: URL {
        guard scheme?.lowercased() == "http", let host = host(),
            !LocalNetwork.isLocal(host: host),
            var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        else { return self }
        components.scheme = "https"
        if components.port == 80 { components.port = nil }
        return components.url ?? self
    }
}

extension LenientURL {
    /// The same address, `securedForLoading`.
    public func securedForLoading() -> LenientURL {
        LenientURL(wrappedValue: wrappedValue?.securedForLoading)
    }
}
