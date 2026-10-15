import Foundation
import Darwin

struct AssetPreparedChange: Sendable {
    let previewID: String
    let expiresAt: Date
    let session: UUID
    let operation: AssetLibraryOperation
    let snapshot: UploadFileSnapshot?
    let snapshotLease: AssetSnapshotLease?
}

final class AssetSnapshotLease: Sendable {
    private let descriptor: Int32

    init(_ snapshot: UploadFileSnapshot) throws {
        let descriptor = open(snapshot.url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw AssetLibraryError("Cannot protect the prepared snapshot") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw AssetLibraryError("Prepared snapshot is already in use")
        }
        self.descriptor = descriptor
    }

    deinit { close(descriptor) }

    static func removeExpiredOrphans(now: Date, directory: URL = FileManager.default.temporaryDirectory) {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.lastPathComponent.hasPrefix("asc-mcp-asset-") {
            let identity = String(url.deletingPathExtension().lastPathComponent.dropFirst("asc-mcp-asset-".count))
            guard UUID(uuidString: identity) != nil else { continue }
            let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else { continue }
            defer { close(descriptor) }
            var info = stat()
            guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
                  info.st_uid == getuid(), info.st_mode & 0o077 == 0,
                  now.timeIntervalSince1970 - Double(info.st_mtimespec.tv_sec) > AssetOperationStore.lifetime,
                  flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { continue }
            var current = stat()
            if lstat(url.path, &current) == 0, current.st_ino == info.st_ino, current.st_dev == info.st_dev {
                unlink(url.path)
            }
        }
    }
}

final class AssetJournalLease: Sendable {
    private let descriptor: Int32
    init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { close(descriptor) }
}

actor AssetOperationStore {
    static let lifetime: TimeInterval = 600
    static let retention: TimeInterval = 7 * 24 * 60 * 60
    private let root: URL
    private let maximumRecords: Int
    private let now: @Sendable () -> Date
    private var previews: [String: AssetPreparedChange] = [:]
    private var busyApps: Set<String> = []
    private var reservations: [UUID: Int64] = [:]
    private var activeOperations: [String: Int64] = [:]
    private var executionLeases: [String: AssetJournalLease] = [:]
    private var inspectionLeases: [UUID: AssetJournalLease] = [:]

    init(root: URL? = nil, maximumRecords: Int = 1_000, now: @escaping @Sendable () -> Date = { Date() }) {
        self.root = root ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/state/asc-mcp/asset-operations", isDirectory: true)
        self.maximumRecords = maximumRecords
        self.now = now
    }

    deinit { previews.values.forEach { $0.snapshot?.discard() } }

    func reservePreparation(upload: Bool) throws -> UUID {
        expirePreviews()
        AssetSnapshotLease.removeExpiredOrphans(now: now())
        guard previews.count + reservations.count + activeOperations.count < 8 else { throw AssetLibraryError("Too many active preparations; wait for completion or expiry") }
        let bytes: Int64 = upload ? 2 * 1_024 * 1_024 * 1_024 : 0
        let totalBytes = previews.values.reduce(Int64(0)) { $0 + Int64($1.snapshot?.fileSize ?? 0) }
            + reservations.values.reduce(0, +) + activeOperations.values.reduce(0, +)
        guard totalBytes + bytes <= 4 * 1_024 * 1_024 * 1_024 else {
            throw AssetLibraryError("Prepared file snapshots exceed the 4 GiB session limit")
        }
        let token = UUID()
        reservations[token] = bytes
        return token
    }

    func releasePreparation(_ token: UUID) { reservations[token] = nil }

    func prepare(account: String, session: UUID, change: AssetLibraryChange, snapshot: UploadFileSnapshot?, reservation: UUID) throws -> AssetPreparedChange {
        guard let bytes = reservations[reservation], Int64(snapshot?.fileSize ?? 0) <= bytes else {
            throw AssetLibraryError("Preparation has no valid resource reservation")
        }
        let date = now()
        let operation = AssetLibraryOperation(id: UUID().uuidString, account: account, createdAt: date, updatedAt: date, status: "prepared", change: change)
        try save(operation, admitting: true)
        let lease = try snapshot.map(AssetSnapshotLease.init)
        let prepared = AssetPreparedChange(previewID: UUID().uuidString, expiresAt: date.addingTimeInterval(Self.lifetime), session: session, operation: operation, snapshot: snapshot, snapshotLease: lease)
        previews[prepared.previewID] = prepared
        reservations[reservation] = nil
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.lifetime))
            await self?.expirePreviews()
        }
        return prepared
    }

    func consume(_ previewID: String, account: String, session: UUID) throws -> AssetPreparedChange {
        expirePreviews()
        guard let preview = previews[previewID], preview.session == session,
              preview.operation.account == account, preview.expiresAt > now() else {
            throw AssetLibraryError("Preview is missing, expired, already consumed, or belongs to another account/session; prepare a new change")
        }
        let key = account + ":" + preview.operation.change.appID
        guard !busyApps.contains(key) else { throw AssetLibraryError("Another asset mutation is running for this app; inspect it before retrying this preview") }
        guard preview.snapshot == nil || activeOperations.values.filter({ $0 > 0 }).count < 2 else {
            throw AssetLibraryError("Two asset transfers are already running; inspect them before applying another preview")
        }
        guard let lease = try claimApp(account: account, appID: preview.operation.change.appID) else {
            throw AssetLibraryError("Another process is executing or reconciling this application's asset operations")
        }
        var operation = preview.operation
        operation.status = "running"
        operation.updatedAt = now()
        try save(operation)
        previews[previewID] = nil
        busyApps.insert(key)
        activeOperations[operation.id] = Int64(preview.snapshot?.fileSize ?? 0)
        executionLeases[operation.id] = lease
        return AssetPreparedChange(previewID: preview.previewID, expiresAt: preview.expiresAt, session: session, operation: operation, snapshot: preview.snapshot, snapshotLease: preview.snapshotLease)
    }

    func inspectPreview(_ previewID: String, account: String, session: UUID) throws -> AssetPreparedChange {
        expirePreviews()
        guard let preview = previews[previewID], preview.operation.account == account, preview.session == session else {
            throw AssetLibraryError("Preview is unavailable in this account/session")
        }
        return preview
    }

    func finish(_ operation: AssetLibraryOperation) throws {
        defer {
            busyApps.remove(operation.account + ":" + operation.change.appID)
            activeOperations[operation.id] = nil
            executionLeases[operation.id] = nil
        }
        try save(operation)
    }

    func checkpoint(_ operation: AssetLibraryOperation) throws { try save(operation) }

    func isActive(_ id: String) -> Bool { activeOperations[id] != nil }

    func beginInspection(_ operation: AssetLibraryOperation) throws -> UUID? {
        guard let lease = try claimApp(account: operation.account, appID: operation.change.appID) else { return nil }
        let token = UUID()
        inspectionLeases[token] = lease
        return token
    }

    func finishInspection(_ token: UUID) { inspectionLeases[token] = nil }

    func get(id: String, account: String) throws -> AssetLibraryOperation {
        guard UUID(uuidString: id) != nil else { throw AssetLibraryError("Invalid operation_id") }
        let directory = try openDirectory(account: account)
        defer { close(directory) }
        let operation = try read(id + ".json", directory: directory)
        guard operation.account == account, operation.id == id else { throw AssetLibraryError("Operation journal scope mismatch") }
        return operation
    }

    func expirePreviews() {
        for (id, preview) in previews where preview.expiresAt <= now() {
            preview.snapshot?.discard()
            previews[id] = nil
            var operation = preview.operation
            operation.status = "expired"
            operation.updatedAt = now()
            try? save(operation)
        }
    }

    private func openDirectory(account: String) throws -> Int32 {
        guard account.count == 64, account.allSatisfy({ $0.isHexDigit }) else { throw AssetLibraryError("Invalid journal account scope") }
        for url in [root, root.appendingPathComponent(account, isDirectory: true)] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                  info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
                throw AssetLibraryError("Asset journal directory must be a private directory owned by the current user")
            }
        }
        let descriptor = open(root.appendingPathComponent(account).path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw AssetLibraryError("Cannot open private asset journal") }
        return descriptor
    }

    private func claimApp(account: String, appID: String) throws -> AssetJournalLease? {
        let directory = try openDirectory(account: account)
        defer { close(directory) }
        let name = ".app-" + (try AssetLibraryJSON.fingerprint(appID)) + ".lock"
        let descriptor = openat(directory, name, O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw AssetLibraryError("Cannot open the application's private operation lease") }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0, info.st_nlink == 1 else {
            close(descriptor)
            throw AssetLibraryError("Unsafe application operation lease")
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let busy = errno == EWOULDBLOCK || errno == EAGAIN
            close(descriptor)
            if busy { return nil }
            throw AssetLibraryError("Cannot acquire application operation lease")
        }
        return AssetJournalLease(descriptor: descriptor)
    }

    private func save(_ operation: AssetLibraryOperation, admitting: Bool = false) throws {
        let directory = try openDirectory(account: operation.account)
        defer { close(directory) }
        let lock = openat(directory, ".lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw AssetLibraryError("Cannot lock asset journal") }
        defer { flock(lock, LOCK_UN); close(lock) }
        var lockInfo = stat()
        guard fstat(lock, &lockInfo) == 0, lockInfo.st_mode & S_IFMT == S_IFREG,
              lockInfo.st_uid == getuid(), lockInfo.st_mode & 0o077 == 0, lockInfo.st_nlink == 1 else {
            throw AssetLibraryError("Unsafe asset journal lock")
        }
        guard flock(lock, LOCK_EX) == 0 else { throw AssetLibraryError("Cannot lock asset journal") }
        if admitting {
            let names = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(operation.account).path)
                .filter { $0.hasSuffix(".json") }
            var retained = 0
            for name in names {
                guard let previous = try? read(name, directory: directory) else {
                    throw AssetLibraryError("Asset journal contains an unreadable record; resolve it before creating another operation")
                }
                if !previous.unresolved, now().timeIntervalSince(previous.updatedAt) > Self.retention {
                    guard unlinkat(directory, name, 0) == 0 else { throw AssetLibraryError("Cannot prune an expired journal record") }
                } else { retained += 1 }
            }
            guard retained < maximumRecords else { throw AssetLibraryError("Asset journal is full; reconcile unresolved operations before creating new ones") }
        }
        let bytes = try AssetLibraryJSON.encode(operation)
        guard bytes.count <= 2 * 1_024 * 1_024 else { throw AssetLibraryError("Asset operation exceeds the journal record size limit") }
        let temporaryName = "." + UUID().uuidString
        let descriptor = openat(directory, temporaryName, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw AssetLibraryError("Cannot create private journal record") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close(); unlinkat(directory, temporaryName, 0) }
        try handle.write(contentsOf: bytes)
        try handle.synchronize()
        guard renameat(directory, temporaryName, directory, operation.id + ".json") == 0, fsync(directory) == 0 else {
            throw AssetLibraryError("Cannot atomically persist asset operation")
        }
    }

    private func read(_ name: String, directory: Int32) throws -> AssetLibraryOperation {
        guard name.hasSuffix(".json"), UUID(uuidString: String(name.dropLast(5))) != nil else { throw AssetLibraryError("Invalid journal record name") }
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw AssetLibraryError("Asset operation was not found in this account") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              info.st_mode & 0o077 == 0, info.st_size <= 2 * 1_024 * 1_024 else {
            throw AssetLibraryError("Unsafe asset journal record")
        }
        return try JSONDecoder().decode(AssetLibraryOperation.self, from: handle.readToEnd() ?? Data())
    }
}
