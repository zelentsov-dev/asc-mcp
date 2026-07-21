import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Custom Product Pages Worker Contract Tests")
struct CustomProductPagesWorkerContractTests {
    @Test("list filters preserve Apple's comma-separated array semantics")
    func listFilters() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 200,
                body: #"{"data":[],"links":{"self":"/v1/apps/app-1/appCustomProductPages"},"meta":{"paging":{"limit":25,"total":0}}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":[],"links":{"self":"/v1/appCustomProductPages/page-1/appCustomProductPageVersions"},"meta":{"paging":{"limit":25,"total":0}}}"#
            ),
            .init(
                statusCode: 200,
                body: #"{"data":[],"links":{"self":"/v1/appCustomProductPageVersions/version-1/appCustomProductPageLocalizations"},"meta":{"paging":{"limit":25,"total":0}}}"#
            )
        ])
        let worker = CustomProductPagesWorker(httpClient: try await cppClient(transport))

        let pages = try await worker.handleTool(.init(
            name: "custom_pages_list",
            arguments: [
                "app_id": .string("app-1"),
                "visible": .array([.bool(true), .bool(false)])
            ]
        ))
        let versions = try await worker.handleTool(.init(
            name: "custom_pages_list_versions",
            arguments: [
                "page_id": .string("page-1"),
                "state": .array([.string("READY_FOR_REVIEW"), .string("IN_REVIEW")])
            ]
        ))
        let localizations = try await worker.handleTool(.init(
            name: "custom_pages_list_localizations",
            arguments: [
                "version_id": .string("version-1"),
                "locale": .array([.string("en-US"), .string("fr-FR")])
            ]
        ))

        #expect(pages.isError != true)
        #expect(versions.isError != true)
        #expect(localizations.isError != true)
        let requests = await transport.recordedRequests()
        #expect(cppQuery(requests[0])["filter[visible]"] == "true,false")
        #expect(cppQuery(requests[1])["filter[state]"] == "READY_FOR_REVIEW,IN_REVIEW")
        #expect(cppQuery(requests[2])["filter[locale]"] == "en-US,fr-FR")

        let invalid = try await worker.handleTool(.init(
            name: "custom_pages_list_versions",
            arguments: ["page_id": .string("page-1"), "state": .string("UNKNOWN")]
        ))
        #expect(invalid.isError == true)
        #expect(await transport.requestCount() == 3)
    }

    @Test("create binds an existing custom product page template")
    func createPageTemplate() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 201,
                body: #"{"data":{"type":"appCustomProductPages","id":"page-2","attributes":{"name":"Campaign"},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}}}},"links":{"self":"/v1/appCustomProductPages/page-2"}}"#
            )
        ])
        let worker = CustomProductPagesWorker(httpClient: try await cppClient(transport))

        let result = try await worker.handleTool(.init(
            name: "custom_pages_create",
            arguments: [
                "app_id": .string("app-1"),
                "name": .string("Campaign"),
                "locale": .string("en-US"),
                "template_page_id": .string("page-template")
            ]
        ))

        #expect(result.isError != true)
        let request = try #require(await transport.recordedRequests().first)
        let relationships = try cppRelationships(request)
        let template = try cppObject(relationships["customProductPageTemplate"])
        let identifier = try cppObject(template["data"])
        #expect(identifier["type"] as? String == "appCustomProductPages")
        #expect(identifier["id"] as? String == "page-template")

        let tool = try #require(await worker.getTools().first { $0.name == "custom_pages_create" })
        let properties = try cppValueObject(try cppValueObject(tool.inputSchema)["properties"])
        #expect(properties["template_page_id"] != nil)
    }

    @Test("version create preserves deep-link value, null, and validation")
    func versionDeepLink() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(
                statusCode: 201,
                body: #"{"data":{"type":"appCustomProductPageVersions","id":"version-1","attributes":{"deepLink":"ascmcp://campaign/summer"},"relationships":{"appCustomProductPage":{"data":{"type":"appCustomProductPages","id":"page-1"}}}},"links":{"self":"/v1/appCustomProductPageVersions/version-1"}}"#
            ),
            .init(
                statusCode: 201,
                body: #"{"data":{"type":"appCustomProductPageVersions","id":"version-2","attributes":{"deepLink":null},"relationships":{"appCustomProductPage":{"data":{"type":"appCustomProductPages","id":"page-1"}}}},"links":{"self":"/v1/appCustomProductPageVersions/version-2"}}"#
            )
        ])
        let worker = CustomProductPagesWorker(httpClient: try await cppClient(transport))

        let concrete = try await worker.handleTool(.init(
            name: "custom_pages_create_version",
            arguments: [
                "page_id": .string("page-1"),
                "deep_link": .string("ascmcp://campaign/summer")
            ]
        ))
        let nullable = try await worker.handleTool(.init(
            name: "custom_pages_create_version",
            arguments: ["page_id": .string("page-1"), "deep_link": .null]
        ))

        #expect(concrete.isError != true)
        #expect(nullable.isError != true)
        let concreteRoot = try cppValueObject(concrete.structuredContent)
        let concreteVersion = try cppValueObject(concreteRoot["version"])
        #expect(concreteVersion["id"] == .string("version-1"))
        #expect(concreteVersion["deepLink"] == .string("ascmcp://campaign/summer"))
        let nullableRoot = try cppValueObject(nullable.structuredContent)
        let nullableVersion = try cppValueObject(nullableRoot["version"])
        #expect(nullableVersion["id"] == .string("version-2"))
        #expect(nullableVersion["deepLink"] == .null)
        let requests = await transport.recordedRequests()
        #expect(try cppAttributes(requests[0])["deepLink"] as? String == "ascmcp://campaign/summer")
        #expect(try cppAttributes(requests[1])["deepLink"] is NSNull)

        let invalid = try await worker.handleTool(.init(
            name: "custom_pages_create_version",
            arguments: ["page_id": .string("page-1"), "deep_link": .string("campaign link")]
        ))
        #expect(invalid.isError == true)
        #expect(await transport.requestCount() == 2)

        let tool = try #require(await worker.getTools().first { $0.name == "custom_pages_create_version" })
        let properties = try cppValueObject(try cppValueObject(tool.inputSchema)["properties"])
        let deepLink = try cppValueObject(properties["deep_link"])
        #expect(deepLink["format"] == .string("uri"))
        #expect(deepLink["type"] == .array([.string("string"), .string("null")]))
    }

    @Test("manifest accounts for every custom-pages optional input")
    func optionalInputManifest() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let mappings = manifest.tools.filter { $0.tool.hasPrefix("custom_pages_") }

        let classifications = Set(mappings.flatMap { mapping in
            mapping.operations.flatMap { operation in
                (operation.optionalParameterClassifications ?? []).map {
                    "\(mapping.tool)|\($0.location)|\($0.appleName)|\($0.disposition.rawValue)"
                }
            }
        })
        let expectedClassifications: Set<String> = [
            "custom_pages_create|body|/data/relationships/appCustomProductPageVersions|internalControl",
            "custom_pages_create_version|body|/data/relationships/appCustomProductPageLocalizations|intentionallyOmitted",
            "custom_pages_get|query|include|intentionallyOmitted",
            "custom_pages_get|query|limit[appCustomProductPageVersions]|intentionallyOmitted",
            "custom_pages_get_localization|query|include|intentionallyOmitted",
            "custom_pages_get_localization|query|limit[appPreviewSets]|intentionallyOmitted",
            "custom_pages_get_localization|query|limit[appScreenshotSets]|intentionallyOmitted",
            "custom_pages_get_localization|query|limit[searchKeywords]|intentionallyOmitted",
            "custom_pages_get_version|query|include|intentionallyOmitted",
            "custom_pages_get_version|query|limit[appCustomProductPageLocalizations]|intentionallyOmitted",
            "custom_pages_list|query|include|intentionallyOmitted",
            "custom_pages_list|query|limit[appCustomProductPageVersions]|intentionallyOmitted",
            "custom_pages_list_localizations|query|include|intentionallyOmitted",
            "custom_pages_list_localizations|query|limit[appPreviewSets]|intentionallyOmitted",
            "custom_pages_list_localizations|query|limit[appScreenshotSets]|intentionallyOmitted",
            "custom_pages_list_localizations|query|limit[searchKeywords]|intentionallyOmitted",
            "custom_pages_list_versions|query|include|intentionallyOmitted",
            "custom_pages_list_versions|query|limit[appCustomProductPageLocalizations]|intentionallyOmitted"
        ]
        #expect(classifications == expectedClassifications)
        #expect(mappings.flatMap(\.operations).flatMap { $0.optionalParameterClassifications ?? [] }.allSatisfy {
            $0.reviewAtSpec == "4.4.1" && !$0.reason.isEmpty
        })

        let expectedBindings: Set<String> = [
            "visible|apps_appCustomProductPages_getToManyRelated",
            "state|appCustomProductPages_appCustomProductPageVersions_getToManyRelated",
            "locale|appCustomProductPageVersions_appCustomProductPageLocalizations_getToManyRelated",
            "template_page_id|appCustomProductPages_createInstance",
            "deep_link|appCustomProductPageVersions_createInstance"
        ]
        let newBindings = Set(mappings.flatMap(\.fields).compactMap { field -> String? in
            guard let operationID = field.operationID else { return nil }
            let identity = "\(field.toolField)|\(operationID)"
            return expectedBindings.contains(identity) ? identity : nil
        })
        #expect(newBindings == expectedBindings)
    }
}

private func cppClient(_ transport: TestHTTPTransport) async throws -> HTTPClient {
    await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
}

private func cppQuery(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).compactMap {
        guard let value = $0.value else { return nil }
        return ($0.name, value)
    })
}

private func cppRequestBody(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func cppObject(_ value: Any?) throws -> [String: Any] {
    try #require(value as? [String: Any])
}

private func cppRelationships(_ request: URLRequest) throws -> [String: Any] {
    let data = try cppObject(try cppRequestBody(request)["data"])
    return try cppObject(data["relationships"])
}

private func cppAttributes(_ request: URLRequest) throws -> [String: Any] {
    let data = try cppObject(try cppRequestBody(request)["data"])
    return try cppObject(data["attributes"])
}

private func cppValueObject(_ value: Value?) throws -> [String: Value] {
    try #require(value?.objectValue)
}
