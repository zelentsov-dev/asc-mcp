import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("API 4.5.1 non-asset contracts")
struct API451AdditionsContractTests {
    @Test("Korea overrides accept every current value", arguments: ["NONE", "ALL", "TWELVE_PLUS", "FIFTEEN_PLUS", "NINETEEN_PLUS"])
    func koreaOverrides(_ value: String) async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":{"type":"ageRatingDeclarations","id":"age-1"}}"#),
            .init(statusCode: 200, body: #"{"data":{"type":"ageRatingDeclarations","id":"age-1"}}"#)
        ])
        let worker = AppLifecycleWorker(httpClient: try await api451Client(transport))
        let tool = try #require(await worker.getTools().first { $0.name == "app_versions_update_age_rating" })
        let schema = try api451Object(tool.inputSchema)
        let properties = try api451Object(schema["properties"])
        let korea = try api451Object(properties["korea_age_rating_override"])
        #expect(korea["enum"]?.arrayValue?.contains(.string(value)) == true)
        #expect(korea["enum"]?.arrayValue?.contains(.null) == true)

        let result = try await worker.handleTool(.init(name: tool.name, arguments: [
            "app_info_id": .string("info-1"), "korea_age_rating_override": .string(value)
        ]))
        #expect(result.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["GET", "PATCH"])
        let body = try #require(await transport.recordedBodyStrings().last)
        let attributes = try api451Attributes(body)
        #expect(attributes == ["koreaAgeRatingOverride": .string(value)])
    }

    @Test("Unknown Korea override fails before network access")
    func unknownKoreaOverride() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = AppLifecycleWorker(httpClient: try await api451Client(transport))
        let result = try await worker.handleTool(.init(name: "app_versions_update_age_rating", arguments: [
            "app_info_id": .string("info-1"), "korea_age_rating_override": .string("THIRTEEN_PLUS")
        ]))
        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("Organization inputs are nullable PATCH-only controls")
    func organizationSchemas() async throws {
        let worker = SubscriptionsWorker(httpClient: try await api451Client(TestHTTPTransport(responses: [])), uploadService: UploadService())
        let tools = await worker.getTools()
        let update = try #require(tools.first { $0.name == "subscriptions_update" })
        let create = try #require(tools.first { $0.name == "subscriptions_create" })
        let updateProperties = try api451Object(try api451Object(update.inputSchema)["properties"])
        let createProperties = try api451Object(try api451Object(create.inputSchema)["properties"])
        for field in ["market_settings", "multi_seat_status"] {
            #expect(createProperties[field] == nil)
            #expect(try api451Object(updateProperties[field])["type"]?.arrayValue?.contains(.string("null")) == true)
        }
        let markets = try api451Object(updateProperties["market_settings"])
        #expect(markets["uniqueItems"] == .bool(true))
        #expect(try api451Object(markets["items"])["enum"]?.arrayValue == [.string("APPLE_SCHOOL"), .string("APP_STORE"), .string("APPLE_BUSINESS")])
    }

    @Test("Subscription organization settings use PATCH and project the response")
    func updateOrganizationSettings() async throws {
        let body = #"{"data":{"type":"subscriptions","id":"sub-1","attributes":{"marketSettings":["APPLE_BUSINESS","APP_STORE"],"multiSeatStatus":"ENABLED"}}}"#
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = SubscriptionsWorker(httpClient: try await api451Client(transport), uploadService: UploadService())
        let result = try await worker.handleTool(.init(name: "subscriptions_update", arguments: [
            "subscription_id": .string("sub-1"),
            "market_settings": .array([.string("APP_STORE"), .string("APPLE_BUSINESS")]),
            "multi_seat_status": .string("ENABLED")
        ]))
        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v1/subscriptions/sub-1")
        let attributes = try api451Attributes(try #require(await transport.recordedBodyStrings().first))
        #expect(attributes == ["marketSettings": .array([.string("APP_STORE"), .string("APPLE_BUSINESS")]), "multiSeatStatus": .string("ENABLED")])
        let resultSubscription = try api451Object(try api451Object(result.structuredContent)["subscription"])
        #expect(resultSubscription["marketSettings"] == .array([.string("APPLE_BUSINESS"), .string("APP_STORE")]))
        #expect(resultSubscription["multiSeatStatus"] == .string("ENABLED"))
    }

    @Test("Subscription updates distinguish omission, null, and empty market selection")
    func organizationTriState() async throws {
        for (arguments, expected) in [
            (["name": Value.string("Renamed")], ["name": Value.string("Renamed")]),
            (["market_settings": Value.null, "multi_seat_status": .null], ["marketSettings": Value.null, "multiSeatStatus": .null]),
            (["market_settings": Value.array([])], ["marketSettings": Value.array([])])
        ] {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: #"{"data":{"type":"subscriptions","id":"sub-1","attributes":{"marketSettings":[]}}}"#)])
            let worker = SubscriptionsWorker(httpClient: try await api451Client(transport), uploadService: UploadService())
            var input = arguments
            input["subscription_id"] = .string("sub-1")
            let result = try await worker.handleTool(.init(name: "subscriptions_update", arguments: input))
            #expect(result.isError != true)
            #expect(try api451Attributes(try #require(await transport.recordedBodyStrings().first)) == expected)
        }
    }

    @Test("Malformed organization inputs fail before network access")
    func invalidOrganizationInputs() async throws {
        let invalid: [[String: Value]] = [
            ["market_settings": .string("APP_STORE")],
            ["market_settings": .array([.string("FUTURE_MARKET")])],
            ["market_settings": .array([.string("APP_STORE"), .string("APP_STORE")])],
            ["market_settings": .array([.int(1)])],
            ["multi_seat_status": .string("enabled")],
            ["multi_seat_status": .bool(true)]
        ]
        for arguments in invalid {
            let transport = TestHTTPTransport(responses: [])
            let worker = SubscriptionsWorker(httpClient: try await api451Client(transport), uploadService: UploadService())
            var input = arguments
            input["subscription_id"] = .string("sub-1")
            let result = try await worker.handleTool(.init(name: "subscriptions_update", arguments: input))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("Organization inputs cannot be silently ignored during CREATE")
    func organizationCreateRejected() async throws {
        for field in ["market_settings", "multi_seat_status"] {
            let transport = TestHTTPTransport(responses: [])
            let worker = SubscriptionsWorker(httpClient: try await api451Client(transport), uploadService: UploadService())
            let result = try await worker.handleTool(.init(name: "subscriptions_create", arguments: [
                "group_id": .string("group-1"), "name": .string("Test"), "product_id": .string("test.subscription"), field: .null
            ]))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("Subscription reads preserve future organization values")
    func futureOrganizationValues() async throws {
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: #"{"data":{"type":"subscriptions","id":"sub-1","attributes":{"marketSettings":["FUTURE_MARKET"],"multiSeatStatus":"FUTURE_STATUS"}}}"#)])
        let worker = SubscriptionsWorker(httpClient: try await api451Client(transport), uploadService: UploadService())
        let result = try await worker.handleTool(.init(name: "subscriptions_get", arguments: ["subscription_id": .string("sub-1")]))
        #expect(result.isError != true)
        let subscription = try api451Object(try api451Object(result.structuredContent)["subscription"])
        #expect(subscription["marketSettings"] == .array([.string("FUTURE_MARKET")]))
        #expect(subscription["multiSeatStatus"] == .string("FUTURE_STATUS"))
    }

    @Test("An unconfirmed organization PATCH is committed unverified", arguments: [
        #"{"data":{"type":"subscriptions","id":"other-sub","attributes":{"multiSeatStatus":"ENABLED"}}}"#,
        #"{"data":{"type":"subscriptions","id":"sub-1","attributes":{"multiSeatStatus":"DISABLED"}}}"#,
        #"{"data":{"type":"subscriptions","id":"sub-1","attributes":{}}}"#
    ])
    func organizationResponseMismatch(_ body: String) async throws {
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = SubscriptionsWorker(httpClient: try await api451Client(transport), uploadService: UploadService())
        let result = try await worker.handleTool(.init(name: "subscriptions_update", arguments: ["subscription_id": .string("sub-1"), "multi_seat_status": .string("ENABLED")]))
        #expect(result.isError == true)
        #expect(try api451Object(result.structuredContent)["operationCommitState"] == .string("committed_unverified"))
        #expect(await transport.requestCount() == 1)
    }

    @Test("Performance overview uses its media type and projects every domain")
    func performanceOverview() async throws {
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: api451Overview)])
        let worker = MetricsWorker(httpClient: try await api451Client(transport))
        let tool = try #require(await worker.getTools().first { $0.name == "metrics_performance_overview" })
        #expect(tool.annotations.readOnlyHint == true)
        #expect(ToolMetadataPolicy.isReadOnly(tool.name))
        let result = try await worker.handleTool(.init(name: tool.name, arguments: [
            "app_id": .string("app-1"), "device_type": .array([.string("iPhone15,2"), .string("iPhone16,1")])
        ]))
        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/apps/app-1/performanceOverviews")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.apple.xcode-overview+json")
        let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.first { $0.name == "filter[deviceType]" }?.value == "iPhone15,2,iPhone16,1")
        let output = try api451Object(result.structuredContent)
        #expect(output["data_available"] == .bool(true))
        #expect(output["telemetry_identifier"] == .string("telemetry-1"))
        #expect(try api451Object(output["app_metadata"])["app_id"] == .string("app-1"))
        let categories = try #require(output["categories"]?.arrayValue)
        let category = try api451Object(categories.first)
        #expect(category["display_name"] == .string("Storage"))
        let section = try api451Object(try #require(category["sections"]?.arrayValue?.first))
        #expect(section["sort_order"] == .int(1))
        let dataset = try api451Object(try #require(section["datasets"]?.arrayValue?.first))
        let point = try api451Object(try #require(dataset["points"]?.arrayValue?.first))
        #expect(point["error_margin"] == .double(0.25))
        let signatures = try api451Object(output["signatures"])
        let signature = try api451Object(try #require(signatures["top_hang_point"]?.arrayValue?.first))
        #expect(signature["trend_info"] == .string("FUTURE_DIRECTION"))
        #expect(signature["source_file"] == .string("Example.swift"))
        #expect(signature["line_number"] == .int(42))
    }

    @Test("Empty overview remains a successful absence of observations", arguments: ["{}", #"{"categories":[],"signatures":{},"appMetadata":{"appId":"app-1"}}"#])
    func emptyOverview(_ body: String) async throws {
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = MetricsWorker(httpClient: try await api451Client(transport))
        let result = try await worker.handleTool(.init(name: "metrics_performance_overview", arguments: ["app_id": .string("app-1")]))
        #expect(result.isError != true)
        #expect(try api451Object(result.structuredContent)["data_available"] == .bool(false))
        let request = try #require(await transport.recordedRequests().first)
        #expect(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems?.isEmpty != false)
    }

    @Test("Overview rejects malformed and cross-app success responses", arguments: [
        #"{"data":{}}"#, #"{"categories":"invalid"}"#, #"{"unrelated":true}"#,
        #"{"appMetadata":{"appId":"another-app"}}"#,
        #"{"categories":[{"sections":[{"datasets":[{"points":[{"value":"invalid"}]}]}]}]}"#
    ])
    func malformedOverview(_ body: String) async throws {
        let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let worker = MetricsWorker(httpClient: try await api451Client(transport))
        let result = try await worker.handleTool(.init(name: "metrics_performance_overview", arguments: ["app_id": .string("app-1")]))
        #expect(result.isError == true)
        #expect(try api451Object(result.structuredContent)["data_available"] == nil)
    }

    @Test("Unavailable or forbidden overview remains an API error", arguments: [403, 404])
    func overviewAPIErrors(_ status: Int) async throws {
        let transport = TestHTTPTransport(responses: [.init(statusCode: status, body: #"{"errors":[{"status":"403","code":"NOT_AVAILABLE","title":"Unavailable","detail":"Not available for this caller"}]}"#)])
        let worker = MetricsWorker(httpClient: try await api451Client(transport))
        let result = try await worker.handleTool(.init(name: "metrics_performance_overview", arguments: ["app_id": .string("app-1")]))
        #expect(result.isError == true)
        #expect(try api451Object(result.structuredContent)["data_available"] == nil)
        #expect(await transport.requestCount() == 1)
    }

    @Test("Overview validates input before network access")
    func overviewInvalidInput() async throws {
        for input: [String: Value] in [
            [:], ["app_id": .string("")], ["app_id": .string("../app-1")],
            ["app_id": .string("app-1"), "device_type": .array([])],
            ["app_id": .string("app-1"), "device_type": .array([.string("a"), .string("a")])],
            ["app_id": .string("app-1"), "device_type": .array([.int(1)])],
            ["app_id": .string("app-1"), "device_type": .null],
            ["app_id": .string("app-1"), "next_url": .string("https://example.test")]
        ] {
            let transport = TestHTTPTransport(responses: [])
            let worker = MetricsWorker(httpClient: try await api451Client(transport))
            let result = try await worker.handleTool(.init(name: "metrics_performance_overview", arguments: input))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }
}

private func api451Client(_ transport: TestHTTPTransport) async throws -> HTTPClient {
    await HTTPClient(jwtService: try TestFactory.makeJWTService(), baseURL: "https://api.example.test", transport: transport, maxRetries: 1)
}

private func api451Object(_ value: Value?) throws -> [String: Value] {
    try #require(value?.objectValue)
}

private func api451Attributes(_ body: String) throws -> [String: Value] {
    let json = try JSONDecoder().decode(Value.self, from: Data(body.utf8))
    return try api451Object(try api451Object(try api451Object(json)["data"])["attributes"])
}

private let api451Overview = #"""
{
  "version":"1.0",
  "appMetadata":{"bundleId":"example.test","appId":"app-1","latestVersion":"4.2","platform":"IOS"},
  "insights":{"regressions":[{"metricCategory":"FUTURE_CATEGORY","latestVersion":"4.2","metric":"test","summaryString":"Regression","referenceVersions":"4.1","maxLatestVersionValue":12,"subSystemLabel":"test","highImpact":true,"populations":[{"deltaPercentage":2,"percentile":"P90","summaryString":"Details","referenceAverageValue":10,"latestVersionValue":12,"device":"iPhone15,2"}]}],"trendingUp":[]},
  "categories":[{"identifier":"STORAGE","displayName":"Storage","sections":[{"identifier":"storage","displayName":"Storage","relevanceScore":0.8,"sortOrder":1,"unit":{"identifier":"mb","displayName":"MB"},"datasets":[{"filterCriteria":{"percentile":"P90","device":"iPhone15,2","deviceMarketingName":"iPhone"},"points":[{"version":"4.2","value":12,"errorMargin":0.25,"percentageBreakdown":{"value":20,"subSystemLabel":"Data"}}],"recommendedMetricGoal":{"value":10,"detail":"Below 10 MB"}}]}]}],
  "signatures":{"topHangPoint":[{"signatureId":"sig-1","signature":"Main thread","count":3,"weight":0.5,"sourceFile":"Example.swift","lineNumber":42,"trendInfo":"FUTURE_DIRECTION","metricsSummary":{"referenceVersions":[{"version":"4.1","value":2}]}}],"topLaunchPoint":[],"topDiskWritePoint":[]},
  "telemetryIdentifier":"telemetry-1"
}
"""#
