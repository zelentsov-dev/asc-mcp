import Foundation
import Testing
@testable import asc_mcp

@Suite("OpenAPI Coverage Tooling Tests")
struct OpenAPICoverageToolingTests {
    @Test("parser extracts spec metadata, paths, and operations")
    func parserExtractsSpecMetadataPathsAndOperations() throws {
        let data = try loadFixture("openapi_minimal.oas")
        let spec = try ASCOpenAPISpec.parse(data)

        #expect(spec.title == "App Store Connect API")
        #expect(spec.version == "4.3-test")
        #expect(spec.openAPIVersion == "3.0.1")
        #expect(spec.sha256 == "63b8d5f4134f5199a7edacf00c529cf41ae12935bfa2147968f77cd03abbdfd6")
        #expect(spec.paths.count == 5)
        #expect(spec.operations.count == 8)
        #expect(spec.schemas.count == 5)
        #expect(spec.schemas["AppUpdateRequest"]?.requiredProperties == ["data"])
        #expect(spec.schemas["AppUpdateRequest"]?.requiredPropertyPointers == ["/data"])
        #expect(spec.schemas["AppUpdateRequest"]?.propertyPointers == ["/data"])
        #expect(spec.schemas["AppUpdateRequest"]?.referencePointers == [
            ASCOpenAPIReferencePointer(
                pointer: "/data",
                reference: "#/components/schemas/AppUpdateData"
            )
        ])
        #expect(spec.schemas["AppUpdateData"]?.requiredPropertyPointers == [
            "/attributes",
            "/attributes/name",
            "/type"
        ])
        #expect(spec.operations.contains { operation in
            operation.path == "/v1/apps" &&
            operation.method == "get" &&
            operation.operationID == "apps_getCollection"
        })
    }

    @Test("parser merges parameters and extracts request and response contracts")
    func parserExtractsOperationContracts() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let listApps = try #require(spec.operation(id: "apps_getCollection"))
        let getApp = try #require(spec.operation(id: "apps_getInstance"))
        let updateApp = try #require(spec.operation(id: "apps_updateInstance"))

        let limit = try #require(listApps.parameters.first { $0.name == "limit" })
        #expect(limit.location == .query)
        #expect(limit.schema.type == "integer")
        #expect(limit.schema.minimum == 1)
        #expect(limit.schema.maximum == 200)
        #expect(!limit.schema.fingerprint.isEmpty)

        let nameFilter = try #require(listApps.parameters.first { $0.name == "filter[name]" })
        #expect(nameFilter.schema.type == "array")
        #expect(nameFilter.schema.itemType == "string")
        #expect(nameFilter.schema.minItems == 1)

        let platform = try #require(listApps.parameters.first { $0.name == "filter[platform]" })
        #expect(platform.required)
        #expect(platform.schema.enumValues == ["IOS", "MAC_OS"])

        let includeBeta = try #require(listApps.parameters.first { $0.name == "includeBeta" })
        #expect(includeBeta.required)
        #expect(includeBeta.schema.valueConstraints[""]?.types == ["boolean"])

        #expect(getApp.parameters.count == 2)
        let id = try #require(getApp.parameters.first { $0.name == "id" })
        #expect(id.location == .path)
        #expect(id.required)
        #expect(id.description == "operation override")
        #expect(id.schema.pattern == "^[0-9]+$")

        let include = try #require(getApp.parameters.first { $0.name == "include" })
        #expect(include.schema.itemEnumValues == ["appInfos", "appStoreVersions"])

        let requestBody = try #require(updateApp.requestBody)
        #expect(requestBody.required)
        #expect(requestBody.content.map(\.contentType) == ["application/json"])
        #expect(requestBody.content.first?.schema.reference == "#/components/schemas/AppUpdateRequest")
        #expect(spec.schemas["AppUpdateData"]?.valueConstraints["/type"]?.enumValues == ["apps"])
        #expect(
            spec.schemas["AppUpdateData"]?.valueConstraints["/attributes/reviewNote"]?.types ==
                ["null"]
        )
        #expect(spec.schemas["ReviewNote"]?.valueConstraints[""]?.types == ["string"])
        #expect(spec.schemas["ReviewNote"]?.valueConstraints[""]?.enumValues == ["PRIVATE", "PUBLIC"])
        #expect(updateApp.responses.map(\.statusCode) == ["200", "204"])
        #expect(updateApp.responses.first?.isSuccess == true)

        let deprecated = try #require(spec.operation(id: "gameCenterAchievements_createInstance"))
        #expect(deprecated.deprecated)
    }

    @Test("parser recognizes every OpenAPI HTTP operation key")
    func parserRecognizesEveryOpenAPIOperationKey() throws {
        let data = Data(
            #"{"openapi":"3.0.1","info":{"title":"Methods","version":"test"},"paths":{"/probe":{"delete":{"operationId":"probe_delete"},"get":{"operationId":"probe_get"},"head":{"operationId":"probe_head"},"options":{"operationId":"probe_options"},"patch":{"operationId":"probe_patch"},"post":{"operationId":"probe_post"},"put":{"operationId":"probe_put"},"trace":{"operationId":"probe_trace"}}}}"#.utf8
        )

        let spec = try ASCOpenAPISpec.parse(data)
        let expectedMethods: Set<String> = [
            "delete", "get", "head", "options", "patch", "post", "put", "trace"
        ]

        #expect(Set(spec.operations.map(\.method)) == expectedMethods)
    }

    @Test("analyzer matches domain prefixes and surfaces high priority gaps")
    func analyzerMatchesDomainPrefixesAndSurfacesHighPriorityGaps() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let rules = [
            ASCOpenAPICoverageRule(
                domain: "Apps",
                priority: .p0,
                status: .partial,
                pathPrefixes: ["/v1/apps"],
                workerKeys: ["apps"],
                toolPrefixes: ["apps_"],
                notes: "Core app reads exist."
            ),
            ASCOpenAPICoverageRule(
                domain: "Game Center",
                priority: .p2,
                status: .missing,
                pathPrefixes: ["/v1/gameCenter"],
                workerKeys: [],
                toolPrefixes: [],
                notes: "No worker yet."
            )
        ]

        let report = ASCOpenAPICoverageAnalyzer(rules: rules).analyze(
            spec: spec,
            generatedAt: "2026-05-07"
        )

        let apps = try #require(report.domains.first { $0.rule.domain == "Apps" })
        let gameCenter = try #require(report.domains.first { $0.rule.domain == "Game Center" })

        #expect(apps.pathCount == 2)
        #expect(apps.operationCount == 3)
        #expect(gameCenter.pathCount == 2)
        #expect(report.highPriorityAppleGaps.map(\.rule.domain) == ["Apps"])
        #expect(report.missingAppleDomains.map(\.rule.domain) == ["Game Center"])
        #expect(report.unclassifiedPaths == ["/v1/actors"])
    }

    @Test("markdown renderer includes summary, gaps, and examples")
    func markdownRendererIncludesSummaryGapsAndExamples() throws {
        let spec = try ASCOpenAPISpec.parse(loadFixture("openapi_minimal.oas"))
        let rules = [
            ASCOpenAPICoverageRule(
                domain: "Apps",
                priority: .p0,
                status: .partial,
                pathPrefixes: ["/v1/apps"],
                workerKeys: ["apps"],
                toolPrefixes: ["apps_"],
                notes: "Core app reads exist."
            )
        ]
        let report = ASCOpenAPICoverageAnalyzer(rules: rules).analyze(
            spec: spec,
            generatedAt: "2026-05-07"
        )

        let markdown = ASCOpenAPICoverageMarkdownRenderer.render(report)

        #expect(markdown.contains("# App Store Connect OpenAPI Coverage"))
        #expect(markdown.contains("Spec: App Store Connect API 4.3-test"))
        #expect(markdown.contains("Apple paths: 5"))
        #expect(markdown.contains("| Apps | Partial | P0 | 2 | 3 | `apps` | Core app reads exist. |"))
        #expect(markdown.contains("## Unclassified Apple Paths"))
        #expect(markdown.contains("`/v1/actors`"))
    }

    @Test("default OpenAPI coverage rules track every inventory area")
    func defaultRulesTrackEveryInventoryArea() {
        let ruleDomains = Set(ASCOpenAPICoverageRules.defaultRules.map(\.domain))

        for area in ASCCoverageInventory.areas {
            #expect(ruleDomains.contains(area.name), "Missing OpenAPI coverage rule for \(area.name)")
        }
    }
}
