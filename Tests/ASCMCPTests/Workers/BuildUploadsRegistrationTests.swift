import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Build Uploads Registration Tests")
struct BuildUploadsRegistrationTests {
    @Test("registry adds Build Uploads without dropping v3.16 workers")
    func registryPreservesExistingWorkers() async throws {
        let requiredKeys: Set<String> = [
            "builds",
            "build_uploads",
            "export_compliance",
            "review_submissions"
        ]
        #expect(WorkerManager.validWorkerFilterKeys.count == 35)
        #expect(requiredKeys.isSubset(of: WorkerManager.validWorkerFilterKeys))

        let snapshots = try await TestFactory.collectWorkerToolSnapshots()
        #expect(snapshots.count == 35)
        #expect(Set(snapshots.map(\.key)) == WorkerManager.validWorkerFilterKeys)
        #expect(snapshots.reduce(0) { $0 + $1.count } == 472)

        let uploads = try #require(snapshots.first { $0.key == "build_uploads" })
        #expect(uploads.readmeName == "Build Uploads")
        #expect(Set(uploads.tools.map(\.name)) == Self.buildUploadToolNames)
    }

    @Test("build_uploads filtering is independent from builds")
    func filterIsIndependentFromBuilds() async throws {
        let buildsOnly = try await TestFactory.makeWorkerManager(enabledWorkers: ["builds"])
        let disabledUpload = try await buildsOnly.routeTool(CallTool.Parameters(
            name: "build_uploads_get",
            arguments: nil
        ))
        #expect(disabledUpload.isError == true)
        #expect(Self.text(from: disabledUpload).contains("Worker 'build_uploads' is disabled"))

        let uploadsOnly = try await TestFactory.makeWorkerManager(enabledWorkers: ["build_uploads"])
        let enabledUpload = try await uploadsOnly.routeTool(CallTool.Parameters(
            name: "build_uploads_get",
            arguments: nil
        ))
        #expect(enabledUpload.isError == true)
        #expect(Self.text(from: enabledUpload).contains("build_upload_id"))
        #expect(!Self.text(from: enabledUpload).contains("is disabled"))

        let disabledBuild = try await uploadsOnly.routeTool(CallTool.Parameters(
            name: "builds_get",
            arguments: nil
        ))
        #expect(disabledBuild.isError == true)
        #expect(Self.text(from: disabledBuild).contains("Worker 'builds' is disabled"))
    }

    @Test("metadata classifies four reads and six mutations")
    func metadataClassifiesReadsAndMutations() async throws {
        let snapshots = try await TestFactory.collectWorkerToolSnapshots()
        let uploadSnapshot = try #require(snapshots.first { $0.key == "build_uploads" })
        let tools = Dictionary(uniqueKeysWithValues: uploadSnapshot.tools.map {
            ($0.name, ToolMetadataPolicy.apply(to: $0))
        })

        let reads: Set<String> = [
            "build_uploads_list",
            "build_uploads_get",
            "build_uploads_list_files",
            "build_uploads_get_file"
        ]
        let mutations = Self.buildUploadToolNames.subtracting(reads)
        #expect(reads.count == 4)
        #expect(mutations.count == 6)

        for name in reads {
            let tool = try #require(tools[name])
            #expect(tool.annotations.readOnlyHint == true, "Expected read-only metadata for \(name)")
            #expect(tool.annotations.destructiveHint == false, "Expected non-destructive metadata for \(name)")
            #expect(tool.annotations.idempotentHint == true, "Expected idempotent metadata for \(name)")
        }
        for name in mutations {
            let tool = try #require(tools[name])
            #expect(tool.annotations.readOnlyHint == false, "Expected mutation metadata for \(name)")
            #expect(tool.annotations.destructiveHint == true, "Expected high-risk metadata for \(name)")
            #expect(tool.annotations.idempotentHint == false, "Expected non-idempotent metadata for \(name)")
        }

        #expect(tools["build_uploads_upload"]?._meta?.fields["anthropic/maxResultSizeChars"] == .int(500_000))
        #expect(tools["build_uploads_upload_file"]?._meta?.fields["anthropic/maxResultSizeChars"] == .int(500_000))
    }

    @Test("read-only mode blocks every Build Upload mutation")
    func readOnlyModeBlocksAllMutations() async throws {
        let manager = try await TestFactory.makeWorkerManager(readOnlyMode: true)
        let reads: Set<String> = [
            "build_uploads_list",
            "build_uploads_get",
            "build_uploads_list_files",
            "build_uploads_get_file"
        ]

        for name in Self.buildUploadToolNames.subtracting(reads) {
            let result = try await manager.routeTool(CallTool.Parameters(name: name, arguments: nil))
            #expect(result.isError == true)
            #expect(result._meta?.fields["asc/readOnlyMode"] == .bool(true))
            #expect(result._meta?.fields["asc/blockedTool"] == .string(name))
        }
    }

    @Test("webhook triage uses Apple resource identities safely")
    func webhookTriageUsesCorrectResourceTypes() throws {
        let uploadRecommendations = ASCWebhookTriagePolicy.recommendations(
            eventType: "BUILD_UPLOAD_STATE_UPDATED",
            relatedResource: ASCWebhookRelatedResource(type: "buildUploads", id: "upload-1"),
            delivery: .empty
        )
        #expect(uploadRecommendations.count == 1)
        let uploadRecommendation = try #require(uploadRecommendations.first)
        #expect(uploadRecommendation.tool == "build_uploads_get")
        #expect(uploadRecommendation.arguments["build_upload_id"] as? String == "upload-1")

        let betaDetailRecommendations = ASCWebhookTriagePolicy.recommendations(
            eventType: "BUILD_BETA_DETAIL_EXTERNAL_BUILD_STATE_UPDATED",
            relatedResource: ASCWebhookRelatedResource(type: "buildBetaDetails", id: "detail-1"),
            delivery: ASCWebhookDeliveryContext(
                deliveryID: "delivery-1",
                webhookID: "webhook-1",
                deliveryState: nil,
                httpStatusCode: nil,
                errorMessage: nil
            )
        )
        #expect(betaDetailRecommendations.count == 1)
        let betaDetailRecommendation = try #require(betaDetailRecommendations.first)
        #expect(betaDetailRecommendation.tool == "webhooks_list_deliveries")
        #expect(betaDetailRecommendation.arguments["webhook_id"] as? String == "webhook-1")
        #expect(!betaDetailRecommendations.contains { $0.tool == "builds_get" || $0.tool == "builds_get_beta_detail" })

        let betaDetailWithoutWebhook = ASCWebhookTriagePolicy.recommendations(
            eventType: "BUILD_BETA_DETAIL_EXTERNAL_BUILD_STATE_UPDATED",
            relatedResource: ASCWebhookRelatedResource(type: "buildBetaDetails", id: "detail-1"),
            delivery: .empty
        )
        #expect(betaDetailWithoutWebhook.isEmpty)

        let mismatchedUploadRecommendations = ASCWebhookTriagePolicy.recommendations(
            eventType: "BUILD_UPLOAD_STATE_UPDATED",
            relatedResource: ASCWebhookRelatedResource(type: "builds", id: "build-1"),
            delivery: .empty
        )
        #expect(mismatchedUploadRecommendations.isEmpty)
        #expect(!mismatchedUploadRecommendations.contains { $0.tool == "builds_get" || $0.tool == "builds_list" })
    }

    @Test("build listing requests and projects included BuildUpload")
    func buildListingIncludesBuildUpload() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: Self.buildsResponse)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = BuildsWorker(httpClient: client)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "builds_list",
            arguments: ["app_id": .string("app-1")]
        ))
        #expect(result.isError != true)

        let request = try #require(await transport.recordedRequests().first)
        let query = Dictionary(uniqueKeysWithValues: (
            URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        ).map { ($0.name, $0.value ?? "") })
        #expect(query["include"] == "app,buildBetaDetail,preReleaseVersion,buildUpload")

        let object = try Self.structuredObject(from: result)
        let builds = try #require(Self.array(object["builds"]))
        let build = try #require(Self.object(builds.first))
        let buildRelationships = try #require(Self.object(build["relationships"]))
        #expect(buildRelationships["buildUploadId"] == .string("upload-1"))

        let included = try #require(Self.array(object["included"]))
        let upload = try #require(Self.object(included.first))
        #expect(upload["id"] == .string("upload-1"))
        #expect(upload["type"] == .string("buildUploads"))
        #expect(upload["shortVersion"] == .string("1.2.3"))
        #expect(upload["buildVersion"] == .string("42"))
        let state = try #require(Self.object(upload["state"]))
        #expect(state["state"] == .string("COMPLETE"))
        let relationships = try #require(Self.object(upload["relationships"]))
        #expect(relationships["buildId"] == .string("build-1"))
    }

    @Test("build get and finder request and return BuildUpload projection")
    func buildLookupsIncludeBuildUpload() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: Self.buildResponse),
            .init(statusCode: 200, body: Self.buildsResponse)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = BuildsWorker(httpClient: client)

        let getResult = try await worker.handleTool(CallTool.Parameters(
            name: "builds_get",
            arguments: ["build_id": .string("build-1")]
        ))
        let findResult = try await worker.handleTool(CallTool.Parameters(
            name: "builds_find_by_number",
            arguments: [
                "app_id": .string("app-1"),
                "build_number": .string("42")
            ]
        ))
        #expect(getResult.isError != true)
        #expect(findResult.isError != true)

        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        let getQuery = Self.query(from: try #require(requests.first?.url))
        let findQuery = Self.query(from: try #require(requests.last?.url))
        #expect(getQuery["include"] == "buildBetaDetail,preReleaseVersion,buildBundles,buildUpload")
        #expect(findQuery["include"] == "app,buildBetaDetail,preReleaseVersion,buildUpload")

        let getObject = try Self.structuredObject(from: getResult)
        let getIncluded = try #require(Self.object(getObject["included"]))
        let getUpload = try #require(Self.object(getIncluded["buildUpload"]))
        #expect(getUpload["id"] == .string("upload-1"))

        let findObject = try Self.structuredObject(from: findResult)
        let findIncluded = try #require(Self.array(findObject["included"]))
        let findUpload = try #require(Self.object(findIncluded.first))
        #expect(findUpload["id"] == .string("upload-1"))
    }

    private static let buildUploadToolNames: Set<String> = [
        "build_uploads_list",
        "build_uploads_get",
        "build_uploads_create",
        "build_uploads_delete",
        "build_uploads_list_files",
        "build_uploads_get_file",
        "build_uploads_reserve_file",
        "build_uploads_commit_file",
        "build_uploads_upload_file",
        "build_uploads_upload"
    ]

    private static let buildsResponse = #"""
    {
      "data": [{
        "type": "builds",
        "id": "build-1",
        "attributes": {"version": "42", "processingState": "VALID"},
        "relationships": {
          "buildUpload": {"data": {"type": "buildUploads", "id": "upload-1"}}
        }
      }],
      "included": [{
        "type": "buildUploads",
        "id": "upload-1",
        "attributes": {
          "cfBundleShortVersionString": "1.2.3",
          "cfBundleVersion": "42",
          "createdDate": "2026-07-21T00:00:00Z",
          "state": {"state": "COMPLETE", "errors": [], "warnings": [], "infos": []},
          "platform": "IOS",
          "uploadedDate": "2026-07-21T00:10:00Z"
        },
        "relationships": {
          "build": {"data": {"type": "builds", "id": "build-1"}},
          "buildUploadFiles": {"links": {"related": "https://api.example.test/v1/buildUploads/upload-1/buildUploadFiles"}}
        }
      }],
      "links": {"self": "https://api.example.test/v1/builds"}
    }
    """#

    private static let buildResponse = #"""
    {
      "data": {
        "type": "builds",
        "id": "build-1",
        "attributes": {"version": "42", "processingState": "VALID"},
        "relationships": {
          "buildUpload": {"data": {"type": "buildUploads", "id": "upload-1"}}
        }
      },
      "included": [{
        "type": "buildUploads",
        "id": "upload-1",
        "attributes": {
          "cfBundleShortVersionString": "1.2.3",
          "cfBundleVersion": "42",
          "state": {"state": "COMPLETE"},
          "platform": "IOS"
        }
      }]
    }
    """#

    private static func text(from result: CallTool.Result) -> String {
        result.content.compactMap { content in
            if case .text(let text, _, _) = content {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }

    private static func structuredObject(from result: CallTool.Result) throws -> [String: Value] {
        guard case .object(let object) = result.structuredContent else {
            Issue.record("Expected structured object content")
            return [:]
        }
        return object
    }

    private static func object(_ value: Value?) -> [String: Value]? {
        guard case .object(let object)? = value else {
            return nil
        }
        return object
    }

    private static func array(_ value: Value?) -> [Value]? {
        guard case .array(let array)? = value else {
            return nil
        }
        return array
    }

    private static func query(from url: URL) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        ).map { ($0.name, $0.value ?? "") })
    }
}
