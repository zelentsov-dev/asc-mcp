import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Xcode Cloud Optional Input Contract Tests")
struct XcodeCloudOptionalInputContractTests {
    @Test("build-run builds encode all Apple filters and paging total")
    func buildRunBuildsEncodeFiltersAndTotal() async throws {
        let transport = XcodeCloudOptionalInputTransport(body: """
        {
          "data": [],
          "links": { "self": "https://api.example.test/v1/ciBuildRuns/run-1/builds?limit=2" },
          "meta": { "paging": { "total": 7, "limit": 2 } }
        }
        """)
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_run_builds_list",
            arguments: [
                "build_run_id": .string("run-1"),
                "limit": .int(2),
                "version": .array([.string("42"), .string("43")]),
                "expired": .array([.bool(false), .bool(true)]),
                "processing_state": .array([.string("PROCESSING"), .string("VALID")]),
                "beta_review_states": .array([.string("IN_REVIEW"), .string("APPROVED")]),
                "uses_non_exempt_encryption": .bool(true),
                "pre_release_versions": .array([.string("1.2"), .string("1.3")]),
                "pre_release_platforms": .array([.string("IOS"), .string("VISION_OS")]),
                "build_audience_types": .array([.string("INTERNAL_ONLY"), .string("APP_STORE_ELIGIBLE")]),
                "pre_release_version_ids": .array([.string("pre-1"), .string("pre-2")]),
                "app_ids": .array([.string("app-1"), .string("app-2")]),
                "beta_group_ids": .array([.string("group-1"), .string("group-2")]),
                "app_store_version_ids": .array([.string("version-1"), .string("version-2")]),
                "build_ids": .array([.string("build-1"), .string("build-2")]),
                "uses_non_exempt_encryption_set": .bool(false),
                "sort": .array([.string("-uploadedDate"), .string("version")])
            ]
        ))

        #expect(result.isError == nil)
        let query = await transport.lastQueryItems()
        #expect(query["limit"] == "2")
        #expect(query["filter[version]"] == "42,43")
        #expect(query["filter[expired]"] == "false,true")
        #expect(query["filter[processingState]"] == "PROCESSING,VALID")
        #expect(query["filter[betaAppReviewSubmission.betaReviewState]"] == "IN_REVIEW,APPROVED")
        #expect(query["filter[usesNonExemptEncryption]"] == "true")
        #expect(query["filter[preReleaseVersion.version]"] == "1.2,1.3")
        #expect(query["filter[preReleaseVersion.platform]"] == "IOS,VISION_OS")
        #expect(query["filter[buildAudienceType]"] == "INTERNAL_ONLY,APP_STORE_ELIGIBLE")
        #expect(query["filter[preReleaseVersion]"] == "pre-1,pre-2")
        #expect(query["filter[app]"] == "app-1,app-2")
        #expect(query["filter[betaGroups]"] == "group-1,group-2")
        #expect(query["filter[appStoreVersion]"] == "version-1,version-2")
        #expect(query["filter[id]"] == "build-1,build-2")
        #expect(query["exists[usesNonExemptEncryption]"] == "false")
        #expect(query["sort"] == "-uploadedDate,version")
        guard case .object(let root)? = result.structuredContent else {
            Issue.record("Expected structured result")
            return
        }
        #expect(root["count"] == .int(0))
        #expect(root["total"] == .int(7))
    }

    @Test("invalid build filters fail before transport")
    func invalidBuildFiltersFailBeforeTransport() async throws {
        let transport = XcodeCloudOptionalInputTransport(body: "{}")
        let worker = try await makeWorker(transport: transport)

        let invalidEnum = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_run_builds_list",
            arguments: [
                "build_run_id": .string("run-1"),
                "processing_state": .string("DONE")
            ]
        ))
        let emptyArray = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_run_builds_list",
            arguments: [
                "build_run_id": .string("run-1"),
                "version": .array([])
            ]
        ))
        let mixedArray = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_run_builds_list",
            arguments: [
                "build_run_id": .string("run-1"),
                "build_ids": .array([.string("build-1"), .int(2)])
            ]
        ))

        #expect(invalidEnum.isError == true)
        #expect(emptyArray.isError == true)
        #expect(mixedArray.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("product build runs accept scalar-or-array build filters")
    func productBuildRunsAcceptBuildFilters() async throws {
        let transport = XcodeCloudOptionalInputTransport(body: """
        {
          "data": [],
          "links": { "self": "https://api.example.test/v1/ciProducts/product-1/buildRuns" },
          "meta": { "paging": { "total": 0, "limit": 25 } }
        }
        """)
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_product_build_runs_list",
            arguments: [
                "product_id": .string("product-1"),
                "build_id": .array([.string("build-1"), .string("build-2")])
            ]
        ))

        #expect(result.isError == nil)
        #expect(await transport.lastPath() == "/v1/ciProducts/product-1/buildRuns")
        let query = await transport.lastQueryItems()
        #expect(query["filter[builds]"] == "build-1,build-2")
    }

    @Test("pagination preserves product build filters")
    func paginationPreservesProductBuildFilters() async throws {
        let transport = XcodeCloudOptionalInputTransport(body: "{}")
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_product_build_runs_list",
            arguments: [
                "product_id": .string("product-1"),
                "build_id": .array([.string("build-1"), .string("build-2")]),
                "next_url": .string("https://api.example.test/v1/ciProducts/product-1/buildRuns?cursor=next")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("pagination preserves build filters and sort")
    func paginationPreservesBuildFiltersAndSort() async throws {
        let transport = XcodeCloudOptionalInputTransport(body: "{}")
        let worker = try await makeWorker(transport: transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "xcode_cloud_build_run_builds_list",
            arguments: [
                "build_run_id": .string("run-1"),
                "processing_state": .string("VALID"),
                "sort": .string("-uploadedDate"),
                "next_url": .string("https://api.example.test/v1/ciBuildRuns/run-1/builds?cursor=next")
            ]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("manifest binds public filters and classifies unsafe expansions")
    func manifestBindsAndClassifiesOptionalInputs() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let builds = try #require(manifest.mapping(for: "xcode_cloud_build_run_builds_list"))
        let publicAppleNames = Set(builds.fields.compactMap { field in
            field.sourceKind == .parameter && field.location == "query" ? field.appleName : nil
        })
        #expect(publicAppleNames.isSuperset(of: Set([
            "filter[version]", "filter[expired]", "filter[processingState]",
            "filter[betaAppReviewSubmission.betaReviewState]", "filter[usesNonExemptEncryption]",
            "filter[preReleaseVersion.version]", "filter[preReleaseVersion.platform]",
            "filter[buildAudienceType]", "filter[preReleaseVersion]", "filter[app]",
            "filter[betaGroups]", "filter[appStoreVersion]", "filter[id]",
            "exists[usesNonExemptEncryption]", "sort"
        ])))
        #expect(builds.response.fields.contains { $0.outputField == "total" && $0.jsonPointer == "/meta/paging/total" })

        let buildClassifications = try #require(builds.operations.first?.optionalParameterClassifications)
        #expect(Set(buildClassifications.map(\.appleName)) == Set([
            "include", "limit[individualTesters]", "limit[betaGroups]",
            "limit[betaBuildLocalizations]", "limit[icons]", "limit[buildBundles]"
        ]))
        #expect(buildClassifications.allSatisfy {
            $0.disposition == .intentionallyOmitted && $0.reviewAtSpec == "4.4.1"
        })

        let expectedRelatedLimits: [String: String] = [
            "xcode_cloud_build_runs_get": "limit[builds]",
            "xcode_cloud_product_build_runs_list": "limit[builds]",
            "xcode_cloud_workflow_build_runs_list": "limit[builds]",
            "xcode_cloud_products_get": "limit[primaryRepositories]",
            "xcode_cloud_products_list": "limit[primaryRepositories]",
            "xcode_cloud_macos_versions_get": "limit[xcodeVersions]",
            "xcode_cloud_macos_versions_list": "limit[xcodeVersions]",
            "xcode_cloud_xcode_versions_get": "limit[macOsVersions]",
            "xcode_cloud_xcode_versions_list": "limit[macOsVersions]"
        ]
        for (tool, appleName) in expectedRelatedLimits {
            let mapping = try #require(manifest.mapping(for: tool))
            let classification = try #require(mapping.operations.first?.optionalParameterClassifications?.first {
                $0.appleName == appleName
            })
            #expect(classification.disposition == .intentionallyOmitted)
            #expect(classification.reviewAtSpec == "4.4.1")
        }

        let productRuns = try #require(manifest.mapping(for: "xcode_cloud_product_build_runs_list"))
        #expect(productRuns.fields.contains {
            $0.toolField == "build_id" && $0.appleName == "filter[builds]"
        })
    }

    private func makeWorker(transport: XcodeCloudOptionalInputTransport) async throws -> XcodeCloudWorker {
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        return XcodeCloudWorker(httpClient: client)
    }
}

private actor XcodeCloudOptionalInputTransport: HTTPTransport {
    private let body: String
    private var request: URLRequest?

    init(body: String) {
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.request = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.test")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        return (Data(body.utf8), response)
    }

    func lastPath() -> String? {
        request?.url?.path
    }

    func lastQueryItems() -> [String: String] {
        guard let url = request?.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }

    func requestCount() -> Int {
        request == nil ? 0 : 1
    }
}
