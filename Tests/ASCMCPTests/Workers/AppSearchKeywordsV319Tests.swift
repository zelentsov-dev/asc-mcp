import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("App Search Keywords v3.19 Contract Tests")
struct AppSearchKeywordsV319Tests {
    @Test("schema and operation manifest expose the complete executable Apple contract")
    func schemaAndManifest() async throws {
        let worker = try await appKeywordWorker(TestHTTPTransport(responses: []))
        let tool = try #require(await worker.getTools().first { $0.name == "apps_list_search_keywords" })
        let properties = try appKeywordProperties(tool)

        #expect(properties["app_id"]?.objectValue?["type"] == .string("string"))
        #expect(properties["app_id"]?.objectValue?["minLength"] == .int(1))
        #expect(properties["app_id"]?.objectValue?["pattern"] == .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#))
        #expect(properties["platforms"]?.objectValue?["minItems"] == .int(1))
        #expect(properties["platforms"]?.objectValue?["uniqueItems"] == .bool(true))
        #expect(properties["platforms"]?.objectValue?["items"]?.objectValue?["enum"] == nil)
        #expect(properties["platforms"]?.objectValue?["items"]?.objectValue?["minLength"] == .int(1))
        #expect(properties["platforms"]?.objectValue?["items"]?.objectValue?["pattern"] == .string(#"^(?!\s)(?!.*\s$)[^,\u0000-\u001F\u007F]+$"#))
        #expect(properties["locales"]?.objectValue?["minItems"] == .int(1))
        #expect(properties["limit"]?.objectValue?["minimum"] == .int(1))
        #expect(properties["limit"]?.objectValue?["maximum"] == .int(200))
        #expect(properties["next_url"]?.objectValue?["minLength"] == .int(1))
        #expect(properties["next_url"]?.objectValue?["format"] == .string("uri-reference"))
        #expect(properties["next_url"]?.objectValue?["pattern"] == .string(#"^(?!.*\s).+$"#))
        #expect(tool.inputSchema.objectValue?["additionalProperties"] == .bool(false))

        let manifest = try ASCOperationManifestBundle.loadBundled()
        let mapping = try #require(manifest.mapping(for: "apps_list_search_keywords"))
        #expect(mapping.effect == .read)
        #expect(mapping.status == .partial)
        #expect(mapping.operations.count == 1)
        let operation = try #require(mapping.operations.first)
        #expect(operation.operationID == "apps_searchKeywords_getToManyRelated")
        #expect(operation.method == "get")
        #expect(operation.path == "/v1/apps/{id}/searchKeywords")
        #expect(operation.optionalParameterClassifications == nil)
        #expect(manifest.index.optionalParameterFamilyRules?.contains {
            $0.family == .sparseFields &&
            $0.disposition == .intentionallyOmitted &&
            $0.reviewAtSpec == "4.4.1"
        } == true)
    }

    @Test("first and continuation pages preserve all filters and project canonical keyword IDs")
    func firstAndContinuationPages() async throws {
        let nextURL = "https://api.example.test/v1/apps/app-1/searchKeywords?filter%5Bplatform%5D=IOS%2CFUTURE_OS&filter%5Blocale%5D=en-US%2Cde-DE&limit=2&cursor=page-2"
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: appKeywordPage(
                ids: ["keyword-1", "keyword-2"],
                next: nextURL,
                total: 3,
                limit: 2,
                nextCursor: "page-2"
            )),
            .init(statusCode: 200, body: appKeywordPage(
                ids: ["keyword-3"],
                total: 3,
                limit: 2
            ))
        ])
        let worker = try await appKeywordWorker(transport)
        let arguments: [String: Value] = [
            "app_id": .string("app-1"),
            "platforms": .array([.string("IOS"), .string("FUTURE_OS")]),
            "locales": .array([.string("en-US"), .string("de-DE")]),
            "limit": .int(2)
        ]

        let first = try await worker.handleTool(.init(
            name: "apps_list_search_keywords",
            arguments: arguments
        ))
        #expect(first.isError != true)
        let firstPayload = try appKeywordObject(first.structuredContent)
        #expect(firstPayload["app_id"] == .string("app-1"))
        #expect(firstPayload["count"] == .int(2))
        #expect(firstPayload["limit"] == .int(2))
        #expect(firstPayload["next_url"] == .string(nextURL))
        let firstKeywords = try #require(firstPayload["search_keywords"]?.arrayValue)
        #expect(firstKeywords.compactMap { $0.objectValue?["id"]?.stringValue } == ["keyword-1", "keyword-2"])
        #expect(firstKeywords.allSatisfy { $0.objectValue?["type"] == .string("appKeywords") })

        var continuationArguments = arguments
        continuationArguments["next_url"] = .string(nextURL)
        let continuation = try await worker.handleTool(.init(
            name: "apps_list_search_keywords",
            arguments: continuationArguments
        ))
        #expect(continuation.isError != true)
        let continuationPayload = try appKeywordObject(continuation.structuredContent)
        #expect(continuationPayload["count"] == .int(1))
        #expect(continuationPayload["next_url"] == nil)
        #expect(try #require(continuationPayload["search_keywords"]?.arrayValue).first?.objectValue?["id"] == .string("keyword-3"))

        let requests = await transport.recordedRequests()
        #expect(requests.count == 2)
        let firstQuery = try appKeywordQuery(try #require(requests.first))
        #expect(firstQuery["filter[platform]"] == "IOS,FUTURE_OS")
        #expect(firstQuery["filter[locale]"] == "en-US,de-DE")
        #expect(firstQuery["limit"] == "2")
        let continuationQuery = try appKeywordQuery(try #require(requests.last))
        #expect(continuationQuery["filter[platform]"] == "IOS,FUTURE_OS")
        #expect(continuationQuery["filter[locale]"] == "en-US,de-DE")
        #expect(continuationQuery["limit"] == "2")
        #expect(continuationQuery["cursor"] == "page-2")
    }

    @Test("invalid arguments and changed continuation scope fail before network access")
    func invalidArgumentsAreZeroRequest() async throws {
        let nextPath = "https://api.example.test/v1/apps/app-1/searchKeywords"
        let cases: [[String: Value]] = [
            [:],
            ["app_id": .int(1)],
            ["app_id": .string("app/1")],
            ["app_id": .string("app-1"), "platforms": .array([])],
            ["app_id": .string("app-1"), "platforms": .array([.string("IOS"), .string("IOS")])],
            ["app_id": .string("app-1"), "platforms": .array([.string("IOS,MAC_OS")])],
            ["app_id": .string("app-1"), "locales": .array([.int(1)])],
            ["app_id": .string("app-1"), "locales": .array([.string(" en-US")])],
            ["app_id": .string("app-1"), "limit": .int(0)],
            ["app_id": .string("app-1"), "limit": .int(201)],
            ["app_id": .string("app-1"), "limit": .string("2")],
            ["app_id": .string("app-1"), "unknown": .bool(true)],
            ["app_id": .string("app-1"), "next_url": .string("https://api.example.test/v1/apps/app-1/searchKeywords?limit=200&cursor=with space")],
            ["app_id": .string("app-1"), "next_url": .string("\(nextPath)?limit=200")],
            ["app_id": .string("app-1"), "next_url": .string("\(nextPath)?limit=199&cursor=next")],
            ["app_id": .string("app-1"), "next_url": .string("https://evil.example/v1/apps/app-1/searchKeywords?limit=200&cursor=next")]
        ]

        for arguments in cases {
            let transport = TestHTTPTransport(responses: [])
            let worker = try await appKeywordWorker(transport)
            let result = try await worker.handleTool(.init(
                name: "apps_list_search_keywords",
                arguments: arguments
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 0)
        }
    }

    @Test("malformed Apple resource and paging documents fail closed")
    func malformedResponsesFailClosed() async throws {
        let bodies = [
            #"{"data":[{"type":"wrong","id":"keyword-1"}],"links":{"self":"https://api.example.test/v1/apps/app-1/searchKeywords"}}"#,
            #"{"data":[{"type":"appKeywords","id":"bad/id"}],"links":{"self":"https://api.example.test/v1/apps/app-1/searchKeywords"}}"#,
            #"{"data":[{"type":"appKeywords","id":"keyword-1"},{"type":"appKeywords","id":"keyword-1"}],"links":{"self":"https://api.example.test/v1/apps/app-1/searchKeywords"}}"#,
            #"{"data":[],"links":{"self":"https://api.example.test/v1/apps/other/searchKeywords"}}"#,
            #"{"data":[],"links":{"self":"https://foreign.example.test/v1/apps/app-1/searchKeywords"}}"#,
            #"{"data":[],"links":{"self":"https://api.example.test/v1/apps/app-1/searchKeywords"},"meta":{}}"#,
            #"{"data":[],"links":{"self":"https://api.example.test/v1/apps/app-1/searchKeywords"},"meta":{"paging":{}}}"#,
            #"{"data":[{"type":"appKeywords","id":"keyword-1"}],"links":{"self":"https://api.example.test/v1/apps/app-1/searchKeywords"},"meta":{"paging":{"limit":0}}}"#,
            #"{"data":[{"type":"appKeywords","id":"keyword-1"}],"links":{"self":"https://api.example.test/v1/apps/app-1/searchKeywords"},"meta":{"paging":{"limit":1,"total":0}}}"#,
            #"{"data":[],"links":{"self":"https://api.example.test/v1/apps/app-1/searchKeywords","next":""}}"#,
            #"{"data":[],"links":{"self":"https://api.example.test/v1/apps/app-1/searchKeywords"},"meta":{"paging":{"limit":200,"nextCursor":"next"}}}"#,
            #"{"data":[],"links":{"self":"https://api.example.test/v1/apps/app-1/searchKeywords","next":"https://api.example.test/v1/apps/app-1/searchKeywords?limit=200&cursor=page-2"},"meta":{"paging":{"limit":200,"nextCursor":"different-page"}}}"#
        ]

        for body in bodies {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await appKeywordWorker(transport)
            let result = try await worker.handleTool(.init(
                name: "apps_list_search_keywords",
                arguments: ["app_id": .string("app-1")]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("Apple pages cannot exceed the requested limit with or without paging metadata")
    func responseCannotExceedRequestedLimit() async throws {
        let bodies = [
            #"{"data":[{"type":"appKeywords","id":"keyword-1"},{"type":"appKeywords","id":"keyword-2"}],"links":{"self":"https://api.example.test/v1/apps/app-1/searchKeywords"}}"#,
            #"{"data":[{"type":"appKeywords","id":"keyword-1"},{"type":"appKeywords","id":"keyword-2"}],"links":{"self":"https://api.example.test/v1/apps/app-1/searchKeywords"},"meta":{"paging":{"limit":2}}}"#,
            #"{"data":[{"type":"appKeywords","id":"keyword-1"}],"links":{"self":"https://api.example.test/v1/apps/app-1/searchKeywords"},"meta":{"paging":{"limit":2}}}"#
        ]

        for body in bodies {
            let transport = TestHTTPTransport(responses: [.init(statusCode: 200, body: body)])
            let worker = try await appKeywordWorker(transport)
            let result = try await worker.handleTool(.init(
                name: "apps_list_search_keywords",
                arguments: ["app_id": .string("app-1"), "limit": .int(1)]
            ))
            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }
}

private func appKeywordWorker(_ transport: TestHTTPTransport) async throws -> AppsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return AppsWorker(client: client)
}

private func appKeywordProperties(_ tool: Tool) throws -> [String: Value] {
    guard case .object(let schema) = tool.inputSchema,
          case .object(let properties)? = schema["properties"] else {
        throw AppKeywordTestError.expectedObject
    }
    return properties
}

private func appKeywordObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object)? = value else {
        throw AppKeywordTestError.expectedObject
    }
    return object
}

private func appKeywordQuery(_ request: URLRequest) throws -> [String: String] {
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    return Dictionary(uniqueKeysWithValues: try (components.queryItems ?? []).map {
        ($0.name, try #require($0.value))
    })
}

private func appKeywordPage(
    ids: [String],
    next: String? = nil,
    total: Int,
    limit: Int,
    nextCursor: String? = nil
) -> String {
    let resources = ids.map { #"{"type":"appKeywords","id":"\#($0)"}"# }.joined(separator: ",")
    let nextField = next.map { #", "next":"\#($0)""# } ?? ""
    let cursorField = nextCursor.map { #", "nextCursor":"\#($0)""# } ?? ""
    return #"{"data":[\#(resources)],"links":{"self":"https://api.example.test/v1/apps/app-1/searchKeywords"\#(nextField)},"meta":{"paging":{"total":\#(total),"limit":\#(limit)\#(cursorField)}}}"#
}

private enum AppKeywordTestError: Error {
    case expectedObject
}
