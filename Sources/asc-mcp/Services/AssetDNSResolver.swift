import Foundation
import Darwin

struct AssetDNSLookup: Sendable {
    let host: String
    let timeout: TimeInterval
    let maximumOutputBytes = 64 * 1_024
    let executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
    var arguments: [String] { ["-q", "host", "-a", "name", host] }
}

private actor AssetDNSResolutionBudget {
    private var active = 0

    func acquire() throws {
        guard active < 2 else { throw AssetLibraryError("Two asset DNS lookups are already running; inspect active operations before retrying") }
        active += 1
    }

    func release() { active -= 1 }
}

/// Resolves upload hostnames through a cancellable macOS system lookup process.
/// Requires `/usr/bin/dscacheutil`; callers must supply the remaining DNS time budget.
enum AssetDNSResolver {
    private static let budget = AssetDNSResolutionBudget()

    static func validateExecutableAvailability() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/dscacheutil") else {
            throw AssetLibraryError("Asset uploads require the system /usr/bin/dscacheutil executable")
        }
    }

    static func resolve(_ host: String, timeout: TimeInterval) async throws -> [String] {
        try await resolve(host, timeout: timeout, execute: executeLookup)
    }

    static func resolve(_ host: String, timeout: TimeInterval,
                        execute: @Sendable (AssetDNSLookup) async throws -> Data) async throws -> [String] {
        try Task.checkCancellation()
        guard validHostname(host), timeout.isFinite, timeout > 0, timeout <= 10 else {
            throw AssetLibraryError("Asset DNS lookup requires a supported hostname and a finite time budget")
        }
        try await budget.acquire()
        do {
            try Task.checkCancellation()
            let output = try await execute(AssetDNSLookup(host: host, timeout: timeout))
            try Task.checkCancellation()
            let addresses = try parseAddresses(output)
            await budget.release()
            return addresses
        } catch {
            await budget.release()
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw AssetLibraryError("Cannot verify upload DNS within its time, response, or address limits; no transfer was attempted")
        }
    }

    static func executeLookup(_ lookup: AssetDNSLookup) async throws -> Data {
        try await executeLookup(lookup, launch: { try $0.run() })
    }

    static func executeLookup(_ lookup: AssetDNSLookup,
                              launch: @escaping @Sendable (Process) throws -> Void) async throws -> Data {
        try Task.checkCancellation()
        guard validHostname(lookup.host), lookup.timeout.isFinite, lookup.timeout > 0, lookup.timeout <= 10 else {
            throw AssetLibraryError("Asset DNS lookup requires a supported hostname and a finite time budget")
        }
        try validateExecutableAvailability()
        let command = AssetPinnedUploadCommand(configuration: Data(), maximumOutputBytes: lookup.maximumOutputBytes,
                                               timeout: lookup.timeout)
        return try await AssetPinnedUploadProcess.run(command) { process in
            process.executableURL = lookup.executableURL
            process.arguments = lookup.arguments
            try launch(process)
        }
    }

    static func parseAddresses(_ output: Data) throws -> [String] {
        guard output.count <= 64 * 1_024, let text = String(data: output, encoding: .utf8),
              !text.unicodeScalars.contains(where: { $0.value == 0 || $0.value == 127 }) else {
            throw AssetLibraryError("Asset DNS response exceeded its format or byte limits")
        }
        var addresses: Set<String> = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count <= 256 else { throw AssetLibraryError("Asset DNS response has too many records") }
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { throw AssetLibraryError("Asset DNS response contains an unknown record") }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if key == "name" || key == "alias" { continue }
            guard key == "ip_address" || key == "ipv6_address" else {
                throw AssetLibraryError("Asset DNS response contains an unsupported address family")
            }
            let values = value.split(whereSeparator: { $0.isWhitespace })
            guard !values.isEmpty else { throw AssetLibraryError("Asset DNS response contains an empty address") }
            for address in values {
                addresses.insert(try canonicalAddress(String(address), family: key == "ip_address" ? AF_INET : AF_INET6))
                guard addresses.count <= 32 else { throw AssetLibraryError("Upload destination exceeds the address limit") }
            }
        }
        guard !addresses.isEmpty else { throw AssetLibraryError("Upload destination has no verifiable address") }
        return addresses.sorted()
    }

    static func validHostname(_ host: String) -> Bool {
        let characters = Set("abcdefghijklmnopqrstuvwxyz0123456789-".utf8)
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return host.utf8.count <= 253 && host.utf8.contains(where: { (97...122).contains($0) })
            && labels.count >= 2 && labels.allSatisfy { label in
                !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-"
                    && label.utf8.allSatisfy { characters.contains($0) }
            } && !host.hasSuffix(".localhost") && !host.hasSuffix(".local")
    }

    private static func canonicalAddress(_ value: String, family: Int32) throws -> String {
        var storage = in6_addr()
        guard !value.contains("%"), value.utf8.count <= Int(INET6_ADDRSTRLEN),
              value.withCString({ inet_pton(family, $0, &storage) }) == 1 else {
            throw AssetLibraryError("Asset DNS returned a malformed numeric address")
        }
        var output = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(family, &storage, &output, socklen_t(output.count)) != nil else {
            throw AssetLibraryError("Asset DNS address could not be normalized")
        }
        return String(decoding: output.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
