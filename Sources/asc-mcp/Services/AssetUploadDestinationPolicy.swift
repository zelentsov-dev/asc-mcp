import Foundation
import Darwin

enum AssetUploadDestinationPolicy {
    static func validate(_ operations: [ASCUploadOperation]) async throws {
        _ = try await resolvedDestinations(operations)
    }

    static func resolvedDestinations(_ operations: [ASCUploadOperation]) async throws -> [String: [String]] {
        try await resolvedDestinations(operations, totalTimeout: 30, lookup: AssetDNSResolver.resolve)
    }

    static func resolvedDestinations(_ operations: [ASCUploadOperation], totalTimeout: TimeInterval,
                                     lookup: @Sendable (String, TimeInterval) async throws -> [String]) async throws -> [String: [String]] {
        try Task.checkCancellation()
        guard totalTimeout.isFinite, totalTimeout > 0, totalTimeout <= 30 else { throw AssetLibraryError("Invalid asset DNS time budget") }
        guard !operations.isEmpty, operations.count <= 1_000 else { throw AssetLibraryError("Invalid number of upload operations") }
        var hosts: Set<String> = []
        for operation in operations {
            guard let raw = operation.url, let url = URLComponents(string: raw), url.scheme == "https",
                  let host = url.host?.lowercased(), !host.isEmpty, url.user == nil, url.password == nil,
                  url.fragment == nil, url.port == nil || url.port == 443,
                  ["PUT", "POST"].contains(operation.method ?? "") else {
                throw AssetLibraryError("Apple upload reservation contains an unsafe URL or method")
            }
            guard AssetDNSResolver.validHostname(host), url.percentEncodedHost?.lowercased() == host else {
                throw AssetLibraryError("Upload destinations require a supported public DNS hostname")
            }
            for header in operation.requestHeaders ?? [] {
                guard let name = header.name, let value = header.value,
                      !["authorization", "proxy-authorization", "cookie", "host", "connection", "transfer-encoding"].contains(name.lowercased()),
                      !name.contains("\r"), !name.contains("\n"), !value.contains("\r"), !value.contains("\n") else {
                    throw AssetLibraryError("Apple upload reservation contains a prohibited header")
                }
            }
            hosts.insert(host)
        }
        guard hosts.count <= 16 else { throw AssetLibraryError("Upload reservation exceeds the destination limit") }
        var resolved: [String: [String]] = [:]
        let deadline = ContinuousClock.now.advanced(by: .seconds(totalTimeout))
        for host in hosts.sorted() {
            try Task.checkCancellation()
            let components = ContinuousClock.now.duration(to: deadline).components
            let remaining = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
            guard remaining > 0 else { throw AssetLibraryError("Upload reservation exceeded its total DNS time budget") }
            let addresses = try await lookup(host, min(10, remaining))
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw AssetLibraryError("Upload reservation exceeded its total DNS time budget") }
            var verified: Set<String> = []
            guard addresses.count <= 32 else { throw AssetLibraryError("Upload destination exceeds the address limit") }
            for numeric in addresses {
                guard isPublicAddress(numeric) else { throw AssetLibraryError("Upload destination resolves to a prohibited network address") }
                verified.insert(numeric)
            }
            guard !verified.isEmpty else { throw AssetLibraryError("Upload destination has no verifiable address") }
            resolved[host] = verified.sorted()
        }
        return resolved
    }

    static func isPublicAddress(_ address: String) -> Bool {
        let normalized = address.lowercased()
        if normalized.contains(":") {
            var address = in6_addr()
            guard inet_pton(AF_INET6, normalized, &address) == 1 else { return false }
            if normalized.hasPrefix("::ffff:") { return isPublicAddress(String(normalized.dropFirst(7))) }
            guard !normalized.contains("%"), let first = normalized.split(separator: ":").first,
                  let prefix = UInt16(first, radix: 16) else { return false }
            let bytes = withUnsafeBytes(of: address) { Array($0) }
            if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] < 2 { return false }
            return (prefix & 0xe000) == 0x2000 && !normalized.hasPrefix("2001:db8:")
                && !normalized.hasPrefix("2002:") && !normalized.hasPrefix("3fff:")
        }
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else { return false }
        let octets = components.compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        let a = octets[0], b = octets[1], c = octets[2]
        if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
        if a == 100 && (64...127).contains(b) { return false }
        if a == 169 && b == 254 || a == 172 && (16...31).contains(b) { return false }
        if a == 192 && (b == 168 || b == 0 || b == 2) { return false }
        if a == 198 && (b == 18 || b == 19 || b == 51 && c == 100) { return false }
        if a == 203 && b == 0 && c == 113 { return false }
        return true
    }
}
