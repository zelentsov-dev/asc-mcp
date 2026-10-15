import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Asset upload commit and poster outcomes")
struct AssetUploadExecutionTests {
    @Test("Reservation transfer commit use protected bytes and only uploaded=true", arguments: [AssetLibraryKind.image, .video])
    func upload(_ kind: AssetLibraryKind) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("fixture.bin")
        try Data([1, 2, 3, 4]).write(to: source)
        let (snapshot, sha) = try AssetMediaInspector.snapshot(path: source.path, directory: directory)
        defer { snapshot.discard() }
        let api = TestHTTPTransport(responses: [
            .init(statusCode: 201, body: body(kind, state: "AWAITING_UPLOAD", upload: true)),
            .init(statusCode: 200, body: body(kind, state: "UPLOAD_COMPLETE")),
            .init(statusCode: 200, body: body(kind, state: "PREPARE_FOR_SUBMISSION", poster: "COMPLETE"))
        ])
        let transfer = TestHTTPTransport(responses: [.init(statusCode: 200, body: "")])
        let worker = try await makeWorker(api: api, upload: transfer, root: directory.appendingPathComponent("journal"))
        var operation = try await operation(worker, kind: kind, sha: sha)
        try await worker.executeUpload(snapshot, operation: &operation)
        #expect(operation.status == "succeeded")
        #expect(operation.resourceIDs["asset_id"] == "asset")
        let requests = await api.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["POST", "PATCH", "GET"])
        let commit = try JSONDecoder().decode(JSONValue.self, from: #require(requests[1].httpBody))
        let attributes = try #require(commit.objectValue?["data"]?.objectValue?["attributes"]?.objectValue)
        #expect(attributes.count == 1 && attributes["uploaded"]?.boolValue == true)
        let uploadRequest = try #require(await transfer.recordedRequests().first)
        #expect(uploadRequest.httpBody == Data([1, 2, 3, 4]))
        #expect(uploadRequest.value(forHTTPHeaderField: "Authorization") == nil)
        let saved = try await worker.store.get(id: operation.id, account: operation.account)
        #expect(saved.resourceIDs["asset_id"] == "asset")
        let journal = String(decoding: try AssetLibraryJSON.encode(saved), as: UTF8.self)
        #expect(!journal.contains("SIGNED_TRANSFER_SECRET"))
    }

    @Test("Failed poster cannot become success during processing or reconciliation")
    func failedPoster() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"appAssetLibraries","id":"library"}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"appAssetLibraries","id":"library"}}"#),
            .init(statusCode: 200, body: #"{"data":[{"type":"appAssetLibraryVideos","id":"asset"}]}"#),
            .init(statusCode: 200, body: body(.video, state: "PREPARE_FOR_SUBMISSION", poster: "FAILED"))
        ])
        let worker = try await makeWorker(api: api, upload: TestHTTPTransport(responses: []), root: directory)
        var value = try await operation(worker, kind: .video, sha: "digest")
        value.completedSteps = ["reserve_asset", "transfer_bytes", "commit_upload"]
        value.resourceIDs["asset_id"] = "asset"
        let asset = try JSONDecoder().decode(AssetLibraryDocument.self, from: Data(body(.video, state: "PREPARE_FOR_SUBMISSION", poster: "FAILED").utf8)).data
        #expect(throws: AssetLibraryError.self) { try worker.evaluateProcessing(asset, change: value.change, operation: &value) }
        #expect(value.status != "succeeded")
        do { try await worker.reconcile(&value); Issue.record("Failed poster reconciliation unexpectedly completed") }
        catch { #expect(value.status != "succeeded") }
        #expect(worker.operationResult(value).isError == true)
    }

    @Test("Poster processing pending is distinct from failed and ready", arguments: ["PROCESSING", "FAILED", "COMPLETE"])
    func posterUpdateRecovery(_ state: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"appAssetLibraries","id":"library"}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"appAssetLibraries","id":"library"}}"#),
            .init(statusCode: 200, body: #"{"data":[{"type":"appAssetLibraryVideos","id":"asset"}]}"#),
            .init(statusCode: 200, body: body(.video, state: "PREPARE_FOR_SUBMISSION", poster: state))
        ])
        let worker = try await makeWorker(api: api, upload: TestHTTPTransport(responses: []), root: directory)
        var change = AssetLibraryChange(action: .updateVideoPoster, appID: "app", kind: .video, assetID: "asset", previewFrameTimeCode: "00:00:01:00")
        change.expectedSpecIDs = ["spec"]
        var operation = AssetLibraryOperation(id: UUID().uuidString, account: try await worker.accountScope(), createdAt: Date(), updatedAt: Date(), status: "requires_reconciliation", change: change, pendingStep: "update_video_poster")
        do {
            try await worker.reconcile(&operation)
            #expect(state != "FAILED")
            #expect(operation.status == (state == "COMPLETE" ? "succeeded" : "processing_pending"))
        } catch {
            #expect(state == "FAILED")
            #expect(operation.status == "requires_reconciliation")
        }
    }

    private func makeWorker(api: TestHTTPTransport, upload: TestHTTPTransport, root: URL) async throws -> AssetsWorker {
        let client = await HTTPClient(jwtService: try TestFactory.makeJWTService(), baseURL: "https://api.appstoreconnect.apple.com", transport: api, maxRetries: 1)
        return AssetsWorker(httpClient: client, companiesManager: try TestFactory.makeCompaniesManager(), uploadService: UploadService(assetTestTransport: upload), store: AssetOperationStore(root: root), validateUploadDestinations: { _ in [:] })
    }

    private func operation(_ worker: AssetsWorker, kind: AssetLibraryKind, sha: String) async throws -> AssetLibraryOperation {
        let change = AssetLibraryChange(action: kind == .image ? .uploadImage : .uploadVideo, appID: "app", kind: kind,
                                       category: "APP_SCREENSHOTS_AND_PREVIEWS", referenceName: "fixture", expectedSpecIDs: ["spec"],
                                       fileSHA256: sha, fileName: "fixture.bin", fileSize: 4, baseline: ["library": "library"])
        return AssetLibraryOperation(id: UUID().uuidString, account: try await worker.accountScope(), createdAt: Date(), updatedAt: Date(), status: "running", change: change)
    }

    private func body(_ kind: AssetLibraryKind, state: String, upload: Bool = false, poster: String? = nil) -> String {
        var attributes: [String: Any] = ["fileName": "fixture.bin", "fileSize": 4, "category": "APP_SCREENSHOTS_AND_PREVIEWS", "referenceName": "fixture", "state": state, "specId": "spec", "previewFrameTimeCode": "00:00:01:00"]
        if upload { attributes["uploadOperations"] = [["method": "PUT", "url": "https://upload.example.test/part?token=SIGNED_TRANSFER_SECRET", "offset": 0, "length": 4]] }
        if let poster { attributes["previewFrameImage"] = ["state": poster] }
        let json: [String: Any] = ["data": ["type": kind.resourceType, "id": "asset", "attributes": attributes]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: json), as: UTF8.self)
    }
}
