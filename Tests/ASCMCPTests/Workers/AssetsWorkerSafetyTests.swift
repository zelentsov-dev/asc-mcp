import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Asset Library mutation safety")
struct AssetsWorkerSafetyTests {
    @Test("Preparation is read-only and application executes the bound update exactly once")
    func referenceUpdate() async throws {
        let transport = TestHTTPTransport(responses: inventory() + inventory() + [response(asset("new")), response(asset("new"))])
        let (worker, root) = try await worker(transport)
        defer { try? FileManager.default.removeItem(at: root) }
        let preview = try await worker.handleTool(.init(name: "assets_prepare_change", arguments: rename))
        #expect(preview.isError != true)
        #expect(await transport.recordedRequests().allSatisfy { $0.httpMethod == "GET" })
        let id = try #require(preview.structuredContent?.objectValue?["preview_id"]?.stringValue)
        let result = try await worker.handleTool(.init(name: "assets_apply_change", arguments: ["preview_id": .string(id)]))
        #expect(result.isError != true)
        #expect(result.structuredContent?.objectValue?["operation"]?.objectValue?["status"] == .string("succeeded"))
        let repeated = try await worker.handleTool(.init(name: "assets_apply_change", arguments: ["preview_id": .string(id)]))
        #expect(repeated.isError == true)
        let writes = await transport.recordedRequests().filter { $0.httpMethod != "GET" }
        #expect(writes.count == 1)
        let body = try #require(writes.first?.httpBody)
        let json = try JSONDecoder().decode(JSONValue.self, from: body)
        #expect(json.objectValue?["data"]?.objectValue?["attributes"]?.objectValue?.keys.sorted() == ["referenceName"])
    }

    @Test("State drift invalidates preview before PATCH")
    func changedState() async throws {
        let transport = TestHTTPTransport(responses: inventory() + inventory(name: "changed elsewhere"))
        let (worker, root) = try await worker(transport)
        defer { try? FileManager.default.removeItem(at: root) }
        let preview = try await worker.handleTool(.init(name: "assets_prepare_change", arguments: rename))
        let id = try #require(preview.structuredContent?.objectValue?["preview_id"]?.stringValue)
        let result = try await worker.handleTool(.init(name: "assets_apply_change", arguments: ["preview_id": .string(id)]))
        #expect(result.isError == true)
        #expect(await transport.recordedRequests().allSatisfy { $0.httpMethod == "GET" })
    }

    @Test("Ownership mismatch blocks preparation before mutation")
    func foreignAsset() async throws {
        let transport = TestHTTPTransport(responses: Array(inventory().prefix(5)) + [response(#"{"data":[]}"#)])
        let (worker, root) = try await worker(transport)
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try await worker.handleTool(.init(name: "assets_prepare_change", arguments: rename))
        #expect(result.isError == true)
        #expect(await transport.recordedRequests().allSatisfy { $0.httpMethod == "GET" })
    }

    @Test("Apply rejects extra parameters and arbitrary actions without network access")
    func parameterSubstitution() async throws {
        let transport = TestHTTPTransport(responses: [])
        let (worker, root) = try await worker(transport)
        defer { try? FileManager.default.removeItem(at: root) }
        for input in [
            CallTool.Parameters(name: "assets_apply_change", arguments: ["preview_id": .string("id"), "asset_id": .string("other")]),
            .init(name: "assets_prepare_change", arguments: ["app_id": .string("app"), "action": .string("http_request"), "url": .string("https://example.org")])
        ] { #expect(try await worker.handleTool(input).isError == true) }
        #expect(await transport.requestCount() == 0)
    }

    @Test("A lost mutation result reconciles by GET without replaying PATCH")
    func uncertainPatch() async throws {
        let transport = TestHTTPTransport(responses: inventory() + inventory() + [
            .init(statusCode: 503, body: #"{"errors":[{"status":"503","title":"Unavailable"}]}"#)
        ] + ownedInventory(name: "new"))
        let (worker, root) = try await worker(transport)
        defer { try? FileManager.default.removeItem(at: root) }
        let preview = try await worker.handleTool(.init(name: "assets_prepare_change", arguments: rename))
        let id = try #require(preview.structuredContent?.objectValue?["preview_id"]?.stringValue)
        let result = try await worker.handleTool(.init(name: "assets_apply_change", arguments: ["preview_id": .string(id)]))
        #expect(result.isError != true)
        #expect(result.structuredContent?.objectValue?["operation"]?.objectValue?["status"] == .string("succeeded"))
        #expect(await transport.recordedRequests().filter { $0.httpMethod == "PATCH" }.count == 1)
    }

    @Test("Incomplete inventory and escaping pagination links fail closed")
    func incompleteInventory() async throws {
        for body in [#"{"data":[],"meta":{"paging":{"total":1}}}"#,
                     #"{"data":[{"type":"appAssetLibraryImages","id":"image"}],"links":{"next":"https://evil.example/v1/appAssetLibraries/library/images?cursor=2"}}"#] {
            let transport = TestHTTPTransport(responses: [response(body)])
            let (worker, root) = try await worker(transport)
            defer { try? FileManager.default.removeItem(at: root) }
            await #expect(throws: (any Error).self) {
                try await worker.all("/v1/appAssetLibraries/library/images", type: "appAssetLibraryImages")
            }
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("Private and reserved network destinations are rejected", arguments: ["127.0.0.1", "10.0.0.1", "172.16.0.1", "169.254.169.254", "192.168.0.1", "100.64.0.1", "::1", "fe80::1", "fc00::1", "::ffff:127.0.0.1", "2001:db8::1"])
    func networkAddresses(_ value: String) { #expect(!AssetUploadDestinationPolicy.isPublicAddress(value)) }

    @Test("Upload policy rejects unsafe URLs and authentication headers before DNS")
    func networkPolicy() async throws {
        for url in ["http://uploads.example.test/file", "file:///tmp/file", "https://localhost/file", "https://host.local/file", "https://user:password@uploads.example.test/file", "https://uploads.example.test:8443/file", "https://uploads.example.test/file#fragment"] {
            let operation = ASCUploadOperation(method: "PUT", url: url, length: 1, offset: 0, requestHeaders: [])
            await #expect(throws: AssetLibraryError.self) { try await AssetUploadDestinationPolicy.validate([operation]) }
        }
        let raw = #"[{"method":"PUT","url":"https://uploads.example.test/file","length":1,"offset":0,"requestHeaders":[{"name":"Authorization","value":"Bearer fixture-token"}]}]"#
        let operations = try JSONDecoder().decode([ASCUploadOperation].self, from: Data(raw.utf8))
        await #expect(throws: AssetLibraryError.self) { try await AssetUploadDestinationPolicy.validate(operations) }
    }

    private var rename: [String: Value] {
        ["app_id": .string("app"), "action": .string("update_reference_name"), "asset_kind": .string("image"), "asset_id": .string("image"), "reference_name": .string("new")]
    }

    private func worker(_ transport: TestHTTPTransport) async throws -> (AssetsWorker, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("asc-asset-worker-test-" + UUID().uuidString)
        let client = await HTTPClient(jwtService: try TestFactory.makeJWTService(), baseURL: "https://api.appstoreconnect.apple.com", transport: transport, maxRetries: 1)
        return (AssetsWorker(httpClient: client, companiesManager: try TestFactory.makeCompaniesManager(), uploadService: UploadService(), store: AssetOperationStore(root: root)), root)
    }

    private func response(_ body: String) -> TestHTTPTransport.Response { .init(statusCode: 200, body: body) }
    private func asset(_ name: String) -> String {
        #"{"data":{"type":"appAssetLibraryImages","id":"image","attributes":{"state":"PREPARE_FOR_SUBMISSION","referenceName":""# + name + #""}}}"#
    }
    private var library: String { #"{"data":{"type":"appAssetLibraries","id":"library"}}"# }
    private func ownedInventory(name: String = "old") -> [TestHTTPTransport.Response] {
        [response(library), response(library), response(#"{"data":[{"type":"appAssetLibraryImages","id":"image"}]}"#), response(asset(name))]
    }
    private func inventory(name: String = "old") -> [TestHTTPTransport.Response] {
        [response(library), response(library), response(#"{"data":[{"type":"appAssetLibraryRefData","id":"catalog","attributes":{"features":[],"placementProfileGroups":[],"imageSpecs":[],"videoSpecs":[],"placementTypes":[],"displayClasses":[]}}]}"#)]
            + ownedInventory(name: name) + [response(#"{"data":[]}"#)]
    }
}
