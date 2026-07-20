import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Beta Feedback Reliability Tests")
struct BetaFeedbackReliabilityTests {
    @Test("collection read sends OpenAPI CSV queries and preserves safe included output")
    func collectionReadUsesExactQueryAndPreservesOutput() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [{
                "type": "betaFeedbackCrashSubmissions",
                "id": "crash-1",
                "attributes": {
                  "comment": "private comment",
                  "email": "feedback@example.com",
                  "deviceModel": "iPhone17,1"
                },
                "relationships": {
                  "build": { "data": { "type": "builds", "id": "build-1" } },
                  "tester": { "data": { "type": "betaTesters", "id": "tester-1" } }
                }
              }],
              "included": [
                {
                  "type": "builds",
                  "id": "build-1",
                  "attributes": { "version": "42", "customMarker": "preserved" },
                  "links": { "self": "https://api.example.test/v1/builds/build-1" }
                },
                {
                  "type": "betaTesters",
                  "id": "tester-1",
                  "attributes": {
                    "firstName": "Private",
                    "lastName": "Tester",
                    "email": "tester@example.com",
                    "state": "INSTALLED"
                  }
                }
              ],
              "links": {
                "self": "https://api.example.test/v1/apps/app-1/betaFeedbackCrashSubmissions",
                "next": "https://api.example.test/v1/apps/app-1/betaFeedbackCrashSubmissions?cursor=next"
              },
              "meta": { "paging": { "total": 17, "limit": 50 } }
            }
            """)
        ])
        let worker = try await betaFeedbackWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_feedback_list_crashes",
            arguments: [
                "app_id": .string("app-1"),
                "build_id": .array([.string("build-1"), .string("build-2")]),
                "pre_release_version_id": .string("pre-1,pre-2"),
                "tester_id": .array([.string("tester-1"), .string("tester-2")]),
                "device_model": .array([.string("iPhone17,1"), .string("iPad16,3")]),
                "os_version": .string("18.5"),
                "app_platform": .array([.string("IOS"), .string("VISION_OS")]),
                "device_platform": .string("IOS"),
                "sort": .array([.string("-createdDate")]),
                "include": .array([.string("tester")]),
                "include_related": .bool(true),
                "include_pii": .bool(false),
                "limit": .int(50)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/apps/app-1/betaFeedbackCrashSubmissions")
        let query = betaFeedbackQuery(request)
        #expect(query["filter[build]"] == "build-1,build-2")
        #expect(query["filter[build.preReleaseVersion]"] == "pre-1,pre-2")
        #expect(query["filter[tester]"] == "tester-1,tester-2")
        #expect(query["filter[deviceModel]"] == "iPhone17,1,iPad16,3")
        #expect(query["filter[osVersion]"] == "18.5")
        #expect(query["filter[appPlatform]"] == "IOS,VISION_OS")
        #expect(query["filter[devicePlatform]"] == "IOS")
        #expect(query["sort"] == "-createdDate")
        #expect(query["include"] == "tester")
        #expect(query["limit"] == "50")

        let root = try betaFeedbackObject(result.structuredContent)
        #expect(root["total"] == .int(17))
        #expect(root["next_url"] == .string("https://api.example.test/v1/apps/app-1/betaFeedbackCrashSubmissions?cursor=next"))
        let crashes = try betaFeedbackArray(root["crashes"])
        let crash = try betaFeedbackObject(crashes.first)
        #expect(crash["email"] == nil)
        #expect(crash["comment"] == nil)

        let included = try betaFeedbackArray(root["included"])
        let build = try betaFeedbackObject(included[0])
        let buildAttributes = try betaFeedbackObject(build["attributes"])
        #expect(buildAttributes["customMarker"] == .string("preserved"))
        #expect(build["links"] != nil)
        let tester = try betaFeedbackObject(included[1])
        let testerAttributes = try betaFeedbackObject(tester["attributes"])
        #expect(testerAttributes["firstName"] == nil)
        #expect(testerAttributes["lastName"] == nil)
        #expect(testerAttributes["email"] == nil)
        #expect(testerAttributes["state"] == .string("INSTALLED"))
    }

    @Test("single read supports include_related alias and retains PII by default")
    func singleReadSupportsCompatibilityAlias() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": {
                "type": "betaFeedbackScreenshotSubmissions",
                "id": "shot-1",
                "attributes": { "comment": "details", "email": "feedback@example.com" }
              },
              "included": [{
                "type": "betaTesters",
                "id": "tester-1",
                "attributes": {
                  "firstName": "Named",
                  "lastName": "Tester",
                  "email": "tester@example.com"
                }
              }]
            }
            """)
        ])
        let worker = try await betaFeedbackWorker(transport)

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_feedback_get_screenshot",
            arguments: [
                "submission_id": .string("shot-1"),
                "include_related": .bool(true)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/betaFeedbackScreenshotSubmissions/shot-1")
        #expect(betaFeedbackQuery(request)["include"] == "build,tester")
        let root = try betaFeedbackObject(result.structuredContent)
        let screenshot = try betaFeedbackObject(root["screenshot"])
        #expect(screenshot["email"] == .string("feedback@example.com"))
        #expect(screenshot["comment"] == .string("details"))
        let included = try betaFeedbackArray(root["included"])
        let tester = try betaFeedbackObject(included.first)
        let attributes = try betaFeedbackObject(tester["attributes"])
        #expect(attributes["firstName"] == .string("Named"))
        #expect(attributes["email"] == .string("tester@example.com"))
    }

    @Test("all four feedback wrappers decode Build and BetaTester included resources")
    func allResponseWrappersDecodeIncludedUnion() throws {
        let included = """
        "included": [
          { "type": "builds", "id": "build-1", "attributes": { "version": "42" } },
          { "type": "betaTesters", "id": "tester-1", "attributes": { "email": "tester@example.com" } }
        ]
        """
        let crash = #"{"type":"betaFeedbackCrashSubmissions","id":"crash-1"}"#
        let screenshot = #"{"type":"betaFeedbackScreenshotSubmissions","id":"shot-1"}"#

        let crashList = try JSONDecoder().decode(
            ASCBetaFeedbackCrashSubmissionsResponse.self,
            from: Data("{\"data\":[\(crash)],\(included)}".utf8)
        )
        let crashSingle = try JSONDecoder().decode(
            ASCBetaFeedbackCrashSubmissionResponse.self,
            from: Data("{\"data\":\(crash),\(included)}".utf8)
        )
        let screenshotList = try JSONDecoder().decode(
            ASCBetaFeedbackScreenshotSubmissionsResponse.self,
            from: Data("{\"data\":[\(screenshot)],\(included)}".utf8)
        )
        let screenshotSingle = try JSONDecoder().decode(
            ASCBetaFeedbackScreenshotSubmissionResponse.self,
            from: Data("{\"data\":\(screenshot),\(included)}".utf8)
        )

        #expect(crashList.included?.count == 2)
        #expect(crashSingle.included?.count == 2)
        #expect(screenshotList.included?.count == 2)
        #expect(screenshotSingle.included?.count == 2)
        if let first = crashList.included?.first, case .build(_) = first {
        } else {
            Issue.record("Expected included Build resource")
        }
        if let last = crashList.included?.last, case .betaTester(_) = last {
        } else {
            Issue.record("Expected included BetaTester resource")
        }
    }

    @Test("invalid CSV, enum, include, and bounds fail before network I/O")
    func invalidInputsFailBeforeNetworkIO() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await betaFeedbackWorker(transport)
        let invalidArguments: [[String: Value]] = [
            ["app_id": .string("app-1"), "build_id": .array([.string("build-1"), .string("build-1")])],
            ["app_id": .string("app-1"), "tester_id": .int(1)],
            ["app_id": .string("app-1"), "app_platform": .string("WATCH_OS")],
            ["app_id": .string("app-1"), "include": .string("app")],
            ["app_id": .string("app-1"), "sort": .string("uploadedDate")],
            ["app_id": .string("app-1"), "limit": .int(0)]
        ]

        for arguments in invalidArguments {
            let result = try await worker.handleTool(CallTool.Parameters(
                name: "beta_feedback_list_crashes",
                arguments: arguments
            ))
            #expect(result.isError == true)
        }

        let logResult = try await worker.handleTool(CallTool.Parameters(
            name: "beta_feedback_get_crash_log",
            arguments: ["submission_id": .string("crash-1"), "max_log_chars": .int(500_001)]
        ))
        #expect(logResult.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("pagination follows a scoped next URL and returns total")
    func paginationPreservesCollectionScope() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: """
            {
              "data": [],
              "links": { "self": "https://api.example.test/v1/apps/app-1/betaFeedbackCrashSubmissions" },
              "meta": { "paging": { "total": 31, "limit": 25 } }
            }
            """)
        ])
        let worker = try await betaFeedbackWorker(transport)
        let nextURL = "https://api.example.test/v1/apps/app-1/betaFeedbackCrashSubmissions?filter%5Bbuild%5D=build-1&include=tester&cursor=page-2&limit=25"

        let result = try await worker.handleTool(CallTool.Parameters(
            name: "beta_feedback_list_crashes",
            arguments: [
                "app_id": .string("app-1"),
                "build_id": .string("build-1"),
                "include": .string("tester"),
                "next_url": .string(nextURL)
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url?.path == "/v1/apps/app-1/betaFeedbackCrashSubmissions")
        let query = betaFeedbackQuery(request)
        #expect(query["filter[build]"] == "build-1")
        #expect(query["include"] == "tester")
        #expect(query["cursor"] == "page-2")
        #expect(try betaFeedbackObject(result.structuredContent)["total"] == .int(31))
    }

    @Test("delete tools use exact resource paths and accept 204")
    func deleteToolsUseExactPaths() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 204, body: ""),
            .init(statusCode: 204, body: "")
        ])
        let worker = try await betaFeedbackWorker(transport)

        let crashResult = try await worker.handleTool(CallTool.Parameters(
            name: "beta_feedback_delete_crash",
            arguments: ["submission_id": .string("crash-1")]
        ))
        let screenshotResult = try await worker.handleTool(CallTool.Parameters(
            name: "beta_feedback_delete_screenshot",
            arguments: ["submission_id": .string("shot-1")]
        ))

        #expect(crashResult.isError != true)
        #expect(screenshotResult.isError != true)
        let requests = await transport.recordedRequests()
        #expect(requests.map(\.httpMethod) == ["DELETE", "DELETE"])
        #expect(requests.compactMap { $0.url?.path } == [
            "/v1/betaFeedbackCrashSubmissions/crash-1",
            "/v1/betaFeedbackScreenshotSubmissions/shot-1"
        ])
    }

    @Test("schemas publish cardinality, exact enums, defaults, and bounds")
    func schemasPublishExactContract() async throws {
        let worker = try await betaFeedbackWorker(TestHTTPTransport(responses: []))
        let tools = await worker.getTools()
        let listNames = ["beta_feedback_list_crashes", "beta_feedback_list_screenshots"]
        let listFields = [
            "build_id", "pre_release_version_id", "tester_id", "device_model",
            "os_version", "app_platform", "device_platform"
        ]

        for name in listNames {
            let tool = try #require(tools.first { $0.name == name })
            let properties = try betaFeedbackProperties(tool)
            for field in listFields {
                #expect(try betaFeedbackArray(try betaFeedbackObject(properties[field])["oneOf"]).count == 2)
            }
            #expect(try betaFeedbackArray(try betaFeedbackObject(properties["include"])["oneOf"]).count == 2)
            #expect(try betaFeedbackObject(properties["limit"])["minimum"] == .int(1))
            #expect(try betaFeedbackObject(properties["limit"])["maximum"] == .int(200))
            #expect(try betaFeedbackObject(properties["limit"])["default"] == .int(25))
            #expect(try betaFeedbackObject(properties["sort"])["default"] == .string("-createdDate"))
            #expect(try betaFeedbackObject(properties["include_pii"])["default"] == .bool(false))

            let platformVariants = try betaFeedbackArray(try betaFeedbackObject(properties["app_platform"])["oneOf"])
            let scalarEnum = try betaFeedbackArray(try betaFeedbackObject(platformVariants[0])["enum"])
            #expect(scalarEnum.compactMap(\.stringValue) == BetaFeedbackPlatformValues.all)
        }

        for name in ["beta_feedback_get_crash", "beta_feedback_get_screenshot"] {
            let tool = try #require(tools.first { $0.name == name })
            let properties = try betaFeedbackProperties(tool)
            #expect(properties["include"] != nil)
            #expect(try betaFeedbackObject(properties["include_related"])["default"] == .bool(false))
            #expect(try betaFeedbackObject(properties["include_pii"])["default"] == .bool(true))
        }

        for name in ["beta_feedback_get_crash_log", "beta_feedback_get_crash_log_by_id"] {
            let tool = try #require(tools.first { $0.name == name })
            let properties = try betaFeedbackProperties(tool)
            let maxChars = try betaFeedbackObject(properties["max_log_chars"])
            #expect(maxChars["minimum"] == .int(1))
            #expect(maxChars["maximum"] == .int(500_000))
            #expect(maxChars["default"] == .int(100_000))
        }
    }

    @Test("manifest records direct include and included response lineage")
    func manifestRecordsIncludedLineage() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let names = [
            "beta_feedback_get_crash",
            "beta_feedback_get_screenshot",
            "beta_feedback_list_crashes",
            "beta_feedback_list_screenshots"
        ]

        for name in names {
            let mapping = try #require(manifest.mapping(for: name))
            let include = try #require(mapping.fields.first { $0.toolField == "include" })
            #expect(include.sourceKind == .parameter)
            #expect(include.location == "query")
            #expect(include.appleName == "include")
            let alias = try #require(mapping.fields.first { $0.toolField == "include_related" })
            #expect(alias.sourceKind == .local)
            #expect(alias.localRole?.contains("Compatibility alias") == true)
            let included = try #require(mapping.response.fields.first { $0.outputField == "included" })
            #expect(included.jsonPointer == "/included")
        }
    }
}

private func betaFeedbackWorker(_ transport: TestHTTPTransport) async throws -> BetaFeedbackWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return BetaFeedbackWorker(httpClient: client)
}

private func betaFeedbackQuery(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map {
        ($0.name, $0.value ?? "")
    })
}

private func betaFeedbackObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        throw BetaFeedbackReliabilityTestError.expectedObject
    }
    return object
}

private func betaFeedbackArray(_ value: Value?) throws -> [Value] {
    guard case .array(let array) = value else {
        throw BetaFeedbackReliabilityTestError.expectedArray
    }
    return array
}

private func betaFeedbackProperties(_ tool: Tool) throws -> [String: Value] {
    try betaFeedbackObject(try betaFeedbackObject(tool.inputSchema)["properties"])
}

private enum BetaFeedbackReliabilityTestError: Error {
    case expectedArray
    case expectedObject
}
