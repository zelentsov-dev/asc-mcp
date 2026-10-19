import Foundation
import Testing
@testable import asc_mcp

@Suite("Bounded Asset DNS Resolution", .serialized, .timeLimit(.minutes(1)))
struct AssetDNSResolverTests {
    @Test("system lookup receives only a validated hostname and a fixed minimal environment")
    func fixedCommand() async throws {
        let output = Data("name: upload.example.test\nip_address: 8.8.8.8\n".utf8)
        let file = try fixtureFile(output)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let recorder = AssetDNSProcessRecorder()
        let addresses = try await AssetDNSResolver.resolve("upload.example.test", timeout: 1) { lookup in
            #expect(lookup.maximumOutputBytes == 64 * 1_024)
            return try await AssetDNSResolver.executeLookup(lookup) { process in
                #expect(process.executableURL?.path == "/usr/bin/dscacheutil")
                #expect(process.arguments == ["-q", "host", "-a", "name", "upload.example.test"])
                #expect(process.environment == ["LC_ALL": "C", "LANG": "C"])
                #expect(process.currentDirectoryURL?.path == "/")
                process.executableURL = URL(fileURLWithPath: "/bin/cat")
                process.arguments = [file.path]
                try process.run()
                recorder.record(process)
            }
        }
        #expect(addresses == ["8.8.8.8"])
        #expect(recorder.processesHaveExited)
    }

    @Test("DNS output normalizes address spellings and deduplicates system records")
    func normalizesRecords() throws {
        let output = """
        name: upload.example.test
        alias: cdn.example.test
        ip_address: 8.8.8.8
        ip_address: 8.8.8.8 1.1.1.1

        name: upload.example.test
        ipv6_address: 2606:4700:4700:0000:0000:0000:0000:1111
        ipv6_address: 2606:4700:4700::1111
        """
        #expect(try AssetDNSResolver.parseAddresses(Data(output.utf8)) == ["1.1.1.1", "2606:4700:4700::1111", "8.8.8.8"])
        let reserved = try AssetDNSResolver.parseAddresses(Data("ipv6_address: 2001:0db8:0000::1\n".utf8))
        #expect(reserved == ["2001:db8::1"])
        #expect(!AssetUploadDestinationPolicy.isPublicAddress(reserved[0]))
    }

    @Test("empty, excessive and malformed DNS output fails closed")
    func invalidRecords() throws {
        let records = [
            "", "name: upload.example.test\n", "ip_address: \n", "ip_address: 8.8.8.8\u{0}\n",
            "ip_address: 8.8.8.8 trailing-data\n", "ipv6_address: 8.8.8.8\n",
            "ipv6_address: fe80::1%en0\n", "unknown_address: 8.8.8.8\n", "malformed line\n",
            String(repeating: "x", count: 64 * 1_024 + 1),
            String(repeating: "name: upload.example.test\n", count: 257),
            (1...33).map { "ip_address: 8.8.8.\($0)\n" }.joined(),
        ]
        for record in records {
            #expect(throws: AssetLibraryError.self) { _ = try AssetDNSResolver.parseAddresses(Data(record.utf8)) }
        }
    }

    @Test("unsafe hostnames fail without executing a child", arguments: [
        "localhost", "upload.local", "upload.localhost", "127.0.0.1", "::1", "upload.example.test.",
        "-upload.example.test", "upload..test", "upload.example.test\n", "upload.example.test;id",
        "https://upload.example.test/?secret=value", "upload.exámple.test"
    ])
    func rejectsHostname(_ host: String) async {
        let recorder = AssetDNSProcessRecorder()
        await #expect(throws: AssetLibraryError.self) {
            _ = try await AssetDNSResolver.resolve(host, timeout: 1) { _ in
                recorder.recordLookup()
                return Data("ip_address: 8.8.8.8\n".utf8)
            }
        }
        #expect(recorder.lookupCount == 0)
    }

    @Test("reservation host and public-address limits are checked before transfer")
    func reservationLimits() async throws {
        let recorder = AssetDNSProcessRecorder()
        let hosts = (1...17).map { "upload\($0).example.test" }
        let many = try operations(hosts)
        await #expect(throws: AssetLibraryError.self) {
            _ = try await AssetUploadDestinationPolicy.resolvedDestinations(many, totalTimeout: 1) { _, _ in
                recorder.recordLookup()
                return ["8.8.8.8"]
            }
        }
        #expect(recorder.lookupCount == 0)
        let one = try operations(["upload.example.test"])
        for addresses in [["8.8.8.8", "127.0.0.1"], [], (1...33).map { "8.8.8.\($0)" }] {
            await #expect(throws: AssetLibraryError.self) {
                _ = try await AssetUploadDestinationPolicy.resolvedDestinations(one, totalTimeout: 1) { _, _ in addresses }
            }
        }
    }

    @Test("all reservation lookups share one deadline")
    func totalDeadline() async throws {
        let recorder = AssetDNSProcessRecorder()
        let uploads = try operations(["a.example.test", "b.example.test"])
        await #expect(throws: AssetLibraryError.self) {
            _ = try await AssetUploadDestinationPolicy.resolvedDestinations(uploads, totalTimeout: 0.02) { _, timeout in
                #expect(timeout > 0 && timeout <= 0.02)
                recorder.recordLookup()
                try await Task.sleep(for: .milliseconds(40))
                return ["8.8.8.8"]
            }
            recorder.recordTransfer()
        }
        #expect(recorder.lookupCount == 1)
        #expect(recorder.transferCount == 0)
    }

    @Test("a stuck resolver is killed and reaped before a transfer can begin")
    func processTimeout() async throws {
        let recorder = AssetDNSProcessRecorder()
        let uploads = try operations(["upload.example.test"])
        await #expect(throws: AssetLibraryError.self) {
            _ = try await AssetUploadDestinationPolicy.resolvedDestinations(uploads, totalTimeout: 0.05) { host, timeout in
                try await AssetDNSResolver.resolve(host, timeout: timeout) { lookup in
                    try await AssetDNSResolver.executeLookup(lookup) { process in try startSleeper(process, recorder: recorder) }
                }
            }
            recorder.recordTransfer()
        }
        #expect(recorder.processCount == 1)
        #expect(recorder.processesHaveExited)
        #expect(recorder.transferCount == 0)
        #expect(try await successfulLookup() == ["8.8.8.8"])
    }

    @Test("cancelling DNS kills and reaps the child before returning")
    func processCancellation() async throws {
        let recorder = AssetDNSProcessRecorder()
        let uploads = try operations(["upload.example.test"])
        let task = Task {
            _ = try await AssetUploadDestinationPolicy.resolvedDestinations(uploads, totalTimeout: 10) { host, timeout in
                try await AssetDNSResolver.resolve(host, timeout: timeout) { lookup in
                    try await AssetDNSResolver.executeLookup(lookup) { process in try startSleeper(process, recorder: recorder) }
                }
            }
            recorder.recordTransfer()
        }
        defer { task.cancel() }
        try await waitForProcesses(1, recorder: recorder)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(recorder.processesHaveExited)
        #expect(recorder.transferCount == 0)
        #expect(try await successfulLookup() == ["8.8.8.8"])
    }

    @Test("a cancelled caller never starts a lookup")
    func cancelledBeforeStart() async throws {
        let recorder = AssetDNSProcessRecorder()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await AssetDNSResolver.resolve("upload.example.test", timeout: 1) { _ in
                recorder.recordLookup()
                return Data()
            }
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(recorder.lookupCount == 0)
    }

    @Test("concurrent resolver children have a global bounded budget")
    func processBudget() async throws {
        let recorder = AssetDNSProcessRecorder()
        let tasks = (0..<2).map { _ in
            Task {
                try await AssetDNSResolver.resolve("upload.example.test", timeout: 10) { lookup in
                    try await AssetDNSResolver.executeLookup(lookup) { process in try startSleeper(process, recorder: recorder) }
                }
            }
        }
        defer { tasks.forEach { $0.cancel() } }
        try await waitForProcesses(2, recorder: recorder)
        await #expect(throws: AssetLibraryError.self) { _ = try await successfulLookup() }
        tasks.forEach { $0.cancel() }
        for task in tasks { await #expect(throws: CancellationError.self) { _ = try await task.value } }
        #expect(recorder.processesHaveExited)
        #expect(try await successfulLookup() == ["8.8.8.8"])
    }

    private func successfulLookup() async throws -> [String] {
        try await AssetDNSResolver.resolve("upload.example.test", timeout: 1) { _ in Data("ip_address: 8.8.8.8\n".utf8) }
    }

    private func startSleeper(_ process: Process, recorder: AssetDNSProcessRecorder) throws {
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        try process.run()
        recorder.record(process)
    }

    private func waitForProcesses(_ count: Int, recorder: AssetDNSProcessRecorder) async throws {
        for _ in 0..<200 {
            if recorder.processCount == count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Expected the bounded fake DNS children to launch")
    }

    private func operations(_ hosts: [String]) throws -> [ASCUploadOperation] {
        let object = hosts.map { ["method": "PUT", "url": "https://\($0)/file?signature=test-only"] }
        return try JSONDecoder().decode([ASCUploadOperation].self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func fixtureFile(_ data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("asc-dns-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = directory.appendingPathComponent("output.txt")
        try data.write(to: file)
        return file
    }
}

private final class AssetDNSProcessRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [Process] = []
    private var lookups = 0
    private var transfers = 0

    var processCount: Int { locked { processes.count } }
    var processesHaveExited: Bool { locked { !processes.isEmpty && processes.allSatisfy { !$0.isRunning } } }
    var lookupCount: Int { locked { lookups } }
    var transferCount: Int { locked { transfers } }

    func record(_ process: Process) { locked { processes.append(process) } }
    func recordLookup() { locked { lookups += 1 } }
    func recordTransfer() { locked { transfers += 1 } }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
