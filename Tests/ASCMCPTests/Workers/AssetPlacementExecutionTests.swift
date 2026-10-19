import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Asset placement execution and shared review previews")
struct AssetPlacementExecutionTests {
    @Test("Nested video poster state gates placement and review preparation", arguments: ["COMPLETE", "PROCESSING", "FAILED", "FUTURE_STATE"], [false, true])
    func videoPosterPreparation(_ state: String, review: Bool) async throws {
        let inventory = review ? reviewInventory() : placementInventory(replacing: false)
        let responses = inventory.map { item in
            let body = String(decoding: item.data, as: UTF8.self)
                .replacingOccurrences(of: "appAssetLibraryImages", with: "appAssetLibraryVideos")
                .replacingOccurrences(of: #""specId":"image-spec""#, with: #""previewFrameImage":{"state":{"state":"\#(state)","errors":null,"warnings":null}},"specId":"image-spec""#)
            return response(body, status: item.statusCode)
        }
        let transport = TestHTTPTransport(responses: responses)
        let (worker, _, root) = try await workers(transport)
        defer { try? FileManager.default.removeItem(at: root) }
        var arguments = createArguments
        if review {
            arguments = ["app_id": .string("app"), "action": .string("add_review_item"), "asset_id": .string("replacement"), "submission_id": .string("submission")]
        }
        arguments["asset_kind"] = .string("video")
        let result = try await worker.handleTool(.init(name: "assets_prepare_change", arguments: arguments))
        if state == "COMPLETE" {
            #expect(result.isError != true)
            #expect(result.structuredContent?.objectValue?["preview_id"]?.stringValue != nil)
        } else {
            #expect(result.isError == true)
            #expect(result.structuredContent?.objectValue?["error"]?.stringValue?.contains("poster frame must finish") == true)
        }
        #expect(await transport.recordedRequests().allSatisfy { $0.httpMethod == "GET" })
    }

    @Test("Placement creation succeeds only after resource and localization readback")
    func createPlacement() async throws {
        let created = placement("new", asset: "replacement")
        let transport = TestHTTPTransport(responses:
            placementInventory(replacing: false) + placementInventory(replacing: false) + [
                response(document(created), status: 201), response(document(created)), response(collection([created]))
            ])
        let (worker, _, root) = try await workers(transport)
        defer { try? FileManager.default.removeItem(at: root) }

        let preview = try await prepare(worker, arguments: createArguments)
        #expect(await transport.recordedRequests().allSatisfy { $0.httpMethod == "GET" })
        let result = try await apply(worker, preview: preview)
        #expect(result.isError != true)
        #expect(try operation(result)["status"] == .string("succeeded"))
        #expect(try operation(result)["resourceIDs"]?.objectValue?["placement_id"] == .string("new"))

        let requests = await transport.recordedRequests()
        let writes = requests.filter { $0.httpMethod != "GET" }
        #expect(writes.count == 1)
        let write = try #require(writes.first)
        #expect(write.httpMethod == "POST")
        #expect(write.url?.path == "/v1/appAssetLibraryPlacements")
        let data = try requestData(write)
        let attributes = try #require(data["attributes"]?.objectValue)
        #expect(Set(attributes.keys) == Set(["placementType", "placementGroup"]))
        #expect(attributes["placementType"]?.stringValue == "screenshot")
        #expect(attributes["placementGroup"]?.stringValue == "phone")
        let relations = try #require(data["relationships"]?.objectValue)
        #expect(Set(relations.keys) == Set(["image", "appStoreVersionLocalization"]))
        #expect(relations["image"]?.objectValue?["data"]?.objectValue?["id"]?.stringValue == "replacement")
        #expect(relations["appStoreVersionLocalization"]?.objectValue?["data"]?.objectValue?["id"]?.stringValue == "localization")
        #expect(requests.suffix(2).map(\.httpMethod) == ["GET", "GET"])
        #expect(requests.suffix(2).compactMap { $0.url?.path } == [
            "/v1/appAssetLibraryPlacements/new", "/v1/appStoreVersionLocalizations/localization/placements"
        ])
    }

    @Test("Replacement retains both binaries and preserves the complete original group order")
    func replacePlacement() async throws {
        let transport = TestHTTPTransport(responses:
            placementInventory(replacing: true) + placementInventory(replacing: true)
                + replacementThroughCreation() + [
                    response(collection(unorderedReplacement)),
                    response(orderingRequest, status: 201),
                    response(collection(orderedReplacement))
                ])
        let (worker, _, root) = try await workers(transport)
        defer { try? FileManager.default.removeItem(at: root) }

        let preview = try await prepare(worker, arguments: replaceArguments)
        let changes = try #require(preview.structuredContent?.objectValue?["changes"]?.objectValue)
        #expect(changes["orderedPlacementIDs"] == .array([.string("first"), .string("old"), .string("last")]))
        #expect(changes["warnings"]?.arrayValue?.contains(where: { $0.stringValue?.contains("not atomic") == true }) == true)
        let result = try await apply(worker, preview: preview)
        #expect(result.isError != true)
        #expect(try operation(result)["status"] == .string("succeeded"))
        #expect(try operation(result)["completedSteps"] == .array([
            .string("remove_old_placement"), .string("create_placement"), .string("reorder_placements")
        ]))

        let requests = await transport.recordedRequests()
        let writes = requests.filter { $0.httpMethod != "GET" }
        #expect(writes.map(\.httpMethod) == ["DELETE", "POST", "POST"])
        #expect(writes.compactMap { $0.url?.path } == [
            "/v1/appAssetLibraryPlacements/old", "/v1/appAssetLibraryPlacements",
            "/v1/appAssetLibraryPlacementOrderingRequests"
        ])
        #expect(!writes.contains { $0.url?.path.contains("appAssetLibraryImages") == true || $0.url?.path.contains("appAssetLibraryVideos") == true })
        let orderingWrite = try #require(writes.last)
        let order = try requestData(orderingWrite)["relationships"]?.objectValue?["orderedPlacements"]?.objectValue?["data"]?.arrayValue
        #expect(order?.compactMap { $0.objectValue?["id"]?.stringValue } == ["first", "new", "last"])
        #expect(requests.last?.httpMethod == "GET")
        #expect(requests.last?.url?.path == "/v1/appStoreVersionLocalizations/localization/placements")
    }

    @Test("A lost replacement creation response stays uncertain even with one matching candidate")
    func lostReplacementResponse() async throws {
        let recovery = targetInventory() + [response(collection(unorderedReplacement))]
        let transport = TestHTTPTransport(responses:
            placementInventory(replacing: true) + placementInventory(replacing: true) + [
                response("", status: 204), response(notFound, status: 404), response(collection(remainingPlacements)),
                response(unavailable, status: 503)
            ] + recovery + recovery)
        let (worker, _, root) = try await workers(transport)
        defer { try? FileManager.default.removeItem(at: root) }

        let preview = try await prepare(worker, arguments: replaceArguments)
        let result = try await apply(worker, preview: preview)
        #expect(result.isError == true)
        let value = try operation(result)
        #expect(value["status"] == .string("requires_reconciliation"))
        #expect(value["completedSteps"] == .array([.string("remove_old_placement")]))
        #expect(value["pendingStep"] == .string("create_placement"))
        #expect(value["resourceIDs"]?.objectValue?["placement_id"] == nil)
        #expect(value["resourceIDs"]?.objectValue?["candidate_placement_id"] == .string("new"))
        #expect(result.structuredContent?.objectValue?["success"] == .bool(false))
        #expect(result.structuredContent?.objectValue?["retry_safe"] == .bool(false))

        let restartedStore = AssetOperationStore(root: root)
        let operationID = try #require(value["id"]?.stringValue)
        let account = try await worker.accountScope()
        let persisted = try await restartedStore.get(id: operationID, account: account)
        let previous = try #require(persisted.change.previousPlacement)
        #expect(persisted.status == "requires_reconciliation")
        #expect(persisted.change.assetID == "replacement")
        #expect(persisted.change.placementID == "old")
        #expect(previous.assetKind == .image)
        #expect(previous.assetID == "original")
        #expect(previous.target == .appStoreVersionLocalization)
        #expect(previous.targetID == "localization")
        #expect(previous.placementType == "screenshot")
        #expect(previous.placementGroup == "phone")
        #expect(previous.orderedPlacementIDs == ["first", "old", "last"])

        let before = await transport.requestCount()
        let inspected = try await worker.handleTool(.init(name: "assets_get_operation", arguments: [
            "operation_id": try #require(value["id"])
        ]))
        #expect(inspected.isError == true)
        #expect(try operation(inspected)["status"] == .string("requires_reconciliation"))
        let requests = await transport.recordedRequests()
        #expect(requests.dropFirst(before).count == 3)
        #expect(requests.dropFirst(before).allSatisfy { $0.httpMethod == "GET" })
        #expect(requests.filter { $0.httpMethod != "GET" }.compactMap { $0.url?.path } == [
            "/v1/appAssetLibraryPlacements/old", "/v1/appAssetLibraryPlacements"
        ])
    }

    @Test("Replacement with the right members in the wrong order is not success or replayed")
    func incompleteReplacementOrder() async throws {
        let recovery = targetInventory() + [response(collection(unorderedReplacement))]
        let transport = TestHTTPTransport(responses:
            placementInventory(replacing: true) + placementInventory(replacing: true)
                + replacementThroughCreation() + [
                    response(collection(unorderedReplacement)), response(orderingRequest, status: 201),
                    response(collection(unorderedReplacement))
                ] + recovery + recovery)
        let (worker, _, root) = try await workers(transport)
        defer { try? FileManager.default.removeItem(at: root) }

        let preview = try await prepare(worker, arguments: replaceArguments)
        let result = try await apply(worker, preview: preview)
        #expect(result.isError == true)
        let value = try operation(result)
        #expect(value["status"] == .string("requires_reconciliation"))
        #expect(value["resourceIDs"]?.objectValue?["placement_id"] == .string("new"))
        #expect(value["completedSteps"]?.arrayValue?.contains(.string("remove_old_placement")) == true)
        #expect(value["message"]?.stringValue?.contains("order is incomplete") == true)
        let before = await transport.requestCount()
        let inspected = try await worker.handleTool(.init(name: "assets_get_operation", arguments: [
            "operation_id": try #require(value["id"])
        ]))
        #expect(inspected.isError == true)
        #expect(try operation(inspected)["status"] == .string("requires_reconciliation"))
        let requests = await transport.recordedRequests()
        #expect(requests.dropFirst(before).count == 3)
        #expect(requests.dropFirst(before).allSatisfy { $0.httpMethod == "GET" })
        #expect(requests.filter { $0.httpMethod == "POST" && $0.url?.path == "/v1/appAssetLibraryPlacementOrderingRequests" }.count == 1)
        #expect(requests.filter { $0.httpMethod == "DELETE" }.compactMap { $0.url?.path } == ["/v1/appAssetLibraryPlacements/old"])
    }

    @Test("Asset and review tools share one bound preview without duplicate review items", arguments: [true, false])
    func sharedReviewPreview(_ reviewFirst: Bool) async throws {
        let transport = TestHTTPTransport(responses: reviewInventory() + reviewInventory() + [
            response(document(reviewItem), status: 201), response(collection([reviewItem]))
        ])
        let (worker, review, root) = try await workers(transport)
        defer { try? FileManager.default.removeItem(at: root) }
        let preview = try await prepare(worker, arguments: [
            "app_id": .string("app"), "action": .string("add_review_item"), "asset_kind": .string("image"),
            "asset_id": .string("replacement"), "submission_id": .string("submission")
        ])
        let id = try #require(preview.structuredContent?.objectValue?["preview_id"]?.stringValue)
        let request = CallTool.Parameters(name: "review_submissions_add_item", arguments: [
            "submission_id": .string("submission"), "app_asset_library_image_id": .string("replacement"),
            "preview_id": .string(id)
        ])
        let before = await transport.requestCount()
        let substituted = try await review.handleTool(.init(name: "review_submissions_add_item", arguments: [
            "submission_id": .string("another-submission"), "app_asset_library_image_id": .string("replacement"),
            "preview_id": .string(id)
        ]))
        #expect(substituted.isError == true)
        #expect(await transport.requestCount() == before)
        let applied: CallTool.Result
        if reviewFirst { applied = try await review.handleTool(request) }
        else { applied = try await apply(worker, preview: preview) }
        #expect(applied.isError != true)
        #expect(try operation(applied)["status"] == .string("succeeded"))
        let after = await transport.requestCount()
        let replay: CallTool.Result
        if reviewFirst { replay = try await apply(worker, preview: preview) }
        else { replay = try await review.handleTool(request) }
        #expect(replay.isError == true)
        #expect(await transport.requestCount() == after)
        let writes = await transport.recordedRequests().filter { $0.httpMethod != "GET" }
        #expect(writes.count == 1)
        let write = try #require(writes.first)
        #expect(write.httpMethod == "POST")
        #expect(write.url?.path == "/v1/reviewSubmissionItems")
        let relations = try #require(try requestData(write)["relationships"]?.objectValue)
        #expect(Set(relations.keys) == Set(["reviewSubmission", "appAssetLibraryImage"]))
        #expect(relations["appAssetLibraryImage"]?.objectValue?["data"]?.objectValue?["id"]?.stringValue == "replacement")
        #expect(relations["reviewSubmission"]?.objectValue?["data"]?.objectValue?["id"]?.stringValue == "submission")
    }

    @Test("A globally known group cannot borrow another feature's placement policy")
    func featureGroupPolicy() async throws {
        let transport = TestHTTPTransport(responses: [])
        let (worker, _, root) = try await workers(transport)
        defer { try? FileManager.default.removeItem(at: root) }
        let resource = try JSONDecoder().decode(AssetLibraryResource.self, from: Data(catalog.utf8))
        #expect(try worker.availableSpecs(resource, category: category, target: .appStoreVersionLocalization,
                                          placementType: "screenshot", group: "phone") == Set(["image-spec"]))
        #expect(try worker.availableSpecs(resource, category: category, target: .appCustomProductPageLocalization,
                                          placementType: "screenshot", group: "cpp-only") == Set(["image-spec"]))
        #expect(throws: AssetLibraryError.self) {
            try worker.availableSpecs(resource, category: category, target: .appStoreVersionLocalization,
                                      placementType: "screenshot", group: "cpp-only")
        }
        #expect(await transport.requestCount() == 0)
    }

    private var category: String { "APP_SCREENSHOTS_AND_PREVIEWS" }
    private var createArguments: [String: Value] {
        ["app_id": .string("app"), "action": .string("create_placement"), "asset_kind": .string("image"),
         "asset_id": .string("replacement"), "target_type": .string("appStoreVersionLocalization"),
         "target_id": .string("localization"), "placement_type": .string("screenshot"), "placement_group": .string("phone")]
    }
    private var replaceArguments: [String: Value] {
        ["app_id": .string("app"), "action": .string("replace_placement"), "asset_kind": .string("image"),
         "asset_id": .string("replacement"), "placement_id": .string("old")]
    }

    private func workers(_ transport: TestHTTPTransport) async throws -> (AssetsWorker, ReviewSubmissionsWorker, URL) {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let root = project.appendingPathComponent(".build/asset-placement-tests/" + UUID().uuidString)
        let client = await HTTPClient(jwtService: try TestFactory.makeJWTService(), baseURL: "https://api.appstoreconnect.apple.com",
                                      transport: transport, maxRetries: 1)
        let worker = AssetsWorker(httpClient: client, companiesManager: try TestFactory.makeCompaniesManager(),
                                  uploadService: UploadService(transport: TestHTTPTransport(responses: [])), store: AssetOperationStore(root: root))
        return (worker, ReviewSubmissionsWorker(httpClient: client, assetsWorker: worker), root)
    }

    private func prepare(_ worker: AssetsWorker, arguments: [String: Value]) async throws -> CallTool.Result {
        let result = try await worker.handleTool(.init(name: "assets_prepare_change", arguments: arguments))
        let detail = result.structuredContent?.objectValue?["error"]?.stringValue
            ?? result.content.compactMap { content -> String? in
                if case .text(let text) = content { return text.text }
                return nil
            }.joined(separator: "\n")
        try #require(result.isError != true, "Asset preparation failed: \(Redactor.redact(detail))")
        return result
    }

    private func apply(_ worker: AssetsWorker, preview: CallTool.Result) async throws -> CallTool.Result {
        let id = try #require(preview.structuredContent?.objectValue?["preview_id"])
        return try await worker.handleTool(.init(name: "assets_apply_change", arguments: ["preview_id": id]))
    }

    private func operation(_ result: CallTool.Result) throws -> [String: Value] {
        try #require(result.structuredContent?.objectValue?["operation"]?.objectValue)
    }

    private func requestData(_ request: URLRequest) throws -> [String: JSONValue] {
        let body = try #require(request.httpBody)
        return try #require(JSONDecoder().decode(JSONValue.self, from: body).objectValue?["data"]?.objectValue)
    }

    private func response(_ body: String, status: Int = 200) -> TestHTTPTransport.Response { .init(statusCode: status, body: body) }
    private func document(_ resource: String) -> String { "{\"data\":\(resource)}" }
    private func collection(_ resources: [String]) -> String { "{\"data\":[\(resources.joined(separator: ","))]}" }

    private func placement(_ id: String, asset: String = "original", group: String = "phone") -> String {
        #"{"type":"appAssetLibraryPlacements","id":"\#(id)","attributes":{"placementType":"screenshot","placementGroup":"\#(group)"},"relationships":{"image":{"data":{"type":"appAssetLibraryImages","id":"\#(asset)"}},"appStoreVersionLocalization":{"data":{"type":"appStoreVersionLocalizations","id":"localization"}}}}"#
    }
    private var remainingPlacements: [String] { [placement("first"), placement("last"), placement("unrelated", group: "tablet")] }
    private var unorderedReplacement: [String] { remainingPlacements + [placement("new", asset: "replacement")] }
    private var orderedReplacement: [String] {
        [placement("first"), placement("new", asset: "replacement"), placement("last"), placement("unrelated", group: "tablet")]
    }
    private var library: String { #"{"data":{"type":"appAssetLibraries","id":"library"}}"# }
    private var asset: String {
        #"{"data":{"type":"appAssetLibraryImages","id":"replacement","attributes":{"state":"PREPARE_FOR_SUBMISSION","specId":"image-spec","category":"APP_SCREENSHOTS_AND_PREVIEWS"}}}"#
    }
    private var notFound: String { #"{"errors":[{"status":"404","title":"Not Found"}]}"# }
    private var unavailable: String { #"{"errors":[{"status":"503","title":"Unavailable"}]}"# }
    private var orderingRequest: String { #"{"data":{"type":"appAssetLibraryPlacementOrderingRequests","id":"ordering"}}"# }

    private func targetInventory() -> [TestHTTPTransport.Response] {
        [response(document(#"{"type":"appStoreVersionLocalizations","id":"localization","attributes":{"locale":"en-US"},"relationships":{"appStoreVersion":{"data":{"type":"appStoreVersions","id":"draft"}}}}"#)),
         response(document(#"{"type":"appStoreVersions","id":"draft","attributes":{"platform":"IOS","appVersionState":"PREPARE_FOR_SUBMISSION"},"relationships":{"app":{"data":{"type":"apps","id":"app"}}}}"#))]
    }

    private func ownedAssetInventory() -> [TestHTTPTransport.Response] {
        [response(library), response(library), response(#"{"data":[{"type":"appAssetLibraryImages","id":"replacement"}]}"#), response(asset), response(collection([]))]
    }

    private func placementInventory(replacing: Bool) -> [TestHTTPTransport.Response] {
        var result = [response(library), response(library), response(collection([catalog]))]
        if replacing { result += [response(document(placement("old")))] + targetInventory() }
        result += targetInventory()
        let existing = replacing ? [placement("first"), placement("old"), placement("last"), placement("unrelated", group: "tablet")] : []
        return result + [response(collection(existing))] + ownedAssetInventory()
    }

    private func replacementThroughCreation() -> [TestHTTPTransport.Response] {
        [response("", status: 204), response(notFound, status: 404), response(collection(remainingPlacements)),
         response(document(placement("new", asset: "replacement")), status: 201),
         response(document(placement("new", asset: "replacement"))), response(collection(unorderedReplacement))]
    }

    private var submission: String {
        #"{"type":"reviewSubmissions","id":"submission","attributes":{"state":"READY_FOR_REVIEW","platform":"IOS"},"relationships":{"app":{"data":{"type":"apps","id":"app"}}}}"#
    }
    private var reviewItem: String {
        #"{"type":"reviewSubmissionItems","id":"item","attributes":{"state":"READY_FOR_REVIEW"},"relationships":{"reviewSubmission":{"data":{"type":"reviewSubmissions","id":"submission"}},"appAssetLibraryImage":{"data":{"type":"appAssetLibraryImages","id":"replacement"}}}}"#
    }
    private func reviewInventory() -> [TestHTTPTransport.Response] {
        [response(library), response(library), response(collection([catalog]))] + ownedAssetInventory() + [
            response(document(submission)),
            response(#"{"data":[{"type":"appStoreVersions","id":"approved","attributes":{"platform":"IOS","appVersionState":"READY_FOR_DISTRIBUTION"}}]}"#),
            response(collection([submission])), response(collection([]))
        ]
    }

    private var catalog: String {
        #"""
        {"type":"appAssetLibraryRefData","id":"catalog","attributes":{
          "features":[
            {"featureId":"APP_STORE_VERSIONS","placementPolicies":[{"placementType":"screenshot","groupLimits":[{"groupIds":["phone"],"maxCount":3}]}]},
            {"featureId":"CUSTOM_PRODUCT_PAGES","placementPolicies":[{"placementType":"screenshot","groupLimits":[{"groupIds":["cpp-only"],"maxCount":3}]}]}
          ],
          "placementProfileGroups":[
            {"placementProfileGroupId":"phone","platform":"IPHONE_APP_STORE"},
            {"placementProfileGroupId":"cpp-only","platform":"IPHONE_APP_STORE"}
          ],
          "placementTypes":[{"placementTypeId":"screenshot","acceptsAssetCategories":["APP_SCREENSHOTS_AND_PREVIEWS"],"specMappings":[
            {"placementGroupId":"phone","specs":["image-spec"]},
            {"placementGroupId":"cpp-only","specs":["image-spec"]}
          ]}],
          "imageSpecs":[],"videoSpecs":[],"displayClasses":[]
        }}
        """#
    }
}
