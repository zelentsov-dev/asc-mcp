import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Apps Search Contract Tests")
struct AppsSearchContractTests {
    @Test("search schema documents complete traversal and page count")
    func searchSchemaDocumentsTraversal() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeAppsSearchWorker(transport)
        let rawTool = try #require(await worker.getTools().first { $0.name == "apps_search" })
        let tool = ToolMetadataPolicy.apply(to: rawTool)
        guard case .object(let schema)? = tool.outputSchema,
              case .object(let properties)? = schema["properties"],
              case .object(let pagesFetched)? = properties["pagesFetched"] else {
            Issue.record("Expected apps search output schema")
            return
        }

        #expect(pagesFetched["type"] == .string("integer"))
        #expect(tool.description?.contains("Follows every Apple result page") == true)
    }

    @Test("search exhausts both branches and returns stable deduplicated order")
    func searchExhaustsBothBranches() async throws {
        let nameNext = appsSearchNextURL(cursor: "name-2", filter: "filter[name]", query: "Needle")
        let bundleNext = appsSearchNextURL(cursor: "bundle-2", filter: "filter[bundleId]", query: "Needle")
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: appsSearchPage(
                apps: [appsSearchApp(id: "z", name: "Zulu", bundleID: "com.example.z", sku: "Z")],
                next: nameNext
            )),
            .init(statusCode: 200, body: appsSearchPage(
                apps: [appsSearchApp(id: "shared", name: "Alpha", bundleID: "com.example.shared", sku: "S")],
                next: nil
            )),
            .init(statusCode: 200, body: appsSearchPage(
                apps: [
                    appsSearchApp(id: "a", name: "Alpha", bundleID: "com.example.a", sku: "A"),
                    appsSearchApp(id: "shared", name: "Alpha", bundleID: "com.example.shared", sku: "S")
                ],
                next: bundleNext
            )),
            .init(statusCode: 200, body: appsSearchPage(
                apps: [appsSearchApp(id: "b", name: "Alpha", bundleID: "com.example.z", sku: "B")],
                next: nil
            ))
        ])
        let worker = try await makeAppsSearchWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "apps_search",
            arguments: ["query": .string("Needle")]
        ))

        #expect(result.isError != true)
        let payload = try appsSearchObject(result)
        let apps = try #require(payload["apps"] as? [[String: Any]])
        #expect(apps.compactMap { $0["id"] as? String } == ["a", "shared", "b", "z"])
        #expect(payload["count"] as? Int == 4)
        #expect(payload["pagesFetched"] as? Int == 4)
        #expect(payload["searchedIn"] as? [String] == ["name", "bundleId"])

        let requests = await transport.recordedRequests()
        #expect(requests.count == 4)
        for (index, request) in requests.enumerated() {
            let query = appsSearchQuery(request)
            #expect(query["fields[apps]"] == "name,bundleId,sku,primaryLocale")
            #expect(query["limit"] == "200")
            #expect(query["sort"] == "name,bundleId,sku")
            if index < 2 {
                #expect(query["filter[name]"] == "Needle")
                #expect(query["filter[bundleId]"] == nil)
            } else {
                #expect(query["filter[bundleId]"] == "Needle")
                #expect(query["filter[name]"] == nil)
            }
        }
        #expect(appsSearchQuery(requests[1])["cursor"] == "name-2")
        #expect(appsSearchQuery(requests[3])["cursor"] == "bundle-2")
    }

    @Test("search rejects continuation scope drift before returning a partial union")
    func searchRejectsContinuationScopeDrift() async throws {
        let fixed = "filter%5Bname%5D=Needle&fields%5Bapps%5D=name%2CbundleId%2Csku%2CprimaryLocale&limit=200&sort=name%2CbundleId%2Csku"
        let invalidNextURLs = [
            "https://other.example.test/v1/apps?cursor=next&\(fixed)",
            "https://api.example.test/v1/users?cursor=next&\(fixed)",
            "https://api.example.test/v1/apps?cursor=next&filter%5Bname%5D=Needle&fields%5Bapps%5D=name%2CbundleId%2Csku%2CprimaryLocale&limit=200",
            "https://api.example.test/v1/apps?cursor=next&\(fixed)&filter%5Bsku%5D=EXTRA",
            "https://api.example.test/v1/apps?cursor=next&filter%5BbundleId%5D=Needle&fields%5Bapps%5D=name%2CbundleId%2Csku%2CprimaryLocale&limit=200&sort=name%2CbundleId%2Csku"
        ]

        for nextURL in invalidNextURLs {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: appsSearchPage(apps: [], next: nextURL))
            ])
            let worker = try await makeAppsSearchWorker(transport)

            let result = try await worker.handleTool(.init(
                name: "apps_search",
                arguments: ["query": .string("Needle")]
            ))

            #expect(result.isError == true)
            #expect(await transport.requestCount() == 1)
        }
    }

    @Test("search rejects a repeated continuation URL")
    func searchRejectsRepeatedContinuation() async throws {
        let nextURL = appsSearchNextURL(cursor: "same", filter: "filter[name]", query: "Needle")
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: appsSearchPage(apps: [], next: nextURL)),
            .init(statusCode: 200, body: appsSearchPage(apps: [], next: nextURL))
        ])
        let worker = try await makeAppsSearchWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "apps_search",
            arguments: ["query": .string("Needle")]
        ))

        #expect(result.isError == true)
        #expect(appsSearchText(result).contains("repeated next URL"))
        #expect(await transport.requestCount() == 2)
    }

    @Test("search rejects a blank query without network access")
    func searchRejectsBlankQuery() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makeAppsSearchWorker(transport)

        let result = try await worker.handleTool(.init(
            name: "apps_search",
            arguments: ["query": .string("  \n")]
        ))

        #expect(result.isError == true)
        #expect(await transport.requestCount() == 0)
    }

    @Test("manifest fixes pagination controls and classifies Apple 4.4.1 inputs")
    func manifestRecordsSearchContract() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let mapping = try #require(manifest.mapping(for: "apps_search"))
        let operations = Dictionary(uniqueKeysWithValues: mapping.operations.compactMap { operation in
            operation.invocationID.map { ($0, operation) }
        })
        let nonSparseOptionalInputs: Set<String> = [
            "filter[name]", "filter[bundleId]", "filter[sku]",
            "filter[appStoreVersions.appStoreState]", "filter[appStoreVersions.platform]",
            "filter[appStoreVersions.appVersionState]", "filter[reviewSubmissions.state]",
            "filter[reviewSubmissions.platform]", "filter[appStoreVersions]", "filter[id]",
            "exists[gameCenterEnabledVersions]", "sort", "limit", "include",
            "limit[androidToIosAppMappingDetails]", "limit[appClips]", "limit[appCustomProductPages]",
            "limit[appEncryptionDeclarations]", "limit[appEvents]", "limit[appInfos]",
            "limit[appStoreVersionExperimentsV2]", "limit[appStoreVersions]",
            "limit[betaAppLocalizations]", "limit[betaGroups]", "limit[builds]",
            "limit[gameCenterEnabledVersions]", "limit[inAppPurchases]", "limit[inAppPurchasesV2]",
            "limit[preReleaseVersions]", "limit[promotedPurchases]", "limit[reviewSubmissions]",
            "limit[subscriptionGroups]"
        ]

        for (invocationID, boundFilter) in [
            ("name-search", "filter[name]"),
            ("bundle-search", "filter[bundleId]")
        ] {
            let operation = try #require(operations[invocationID])
            let inputs = Dictionary(uniqueKeysWithValues: (operation.inputs ?? []).compactMap { input in
                guard input.location == "query", let name = input.appleName, let value = input.fixedValue else {
                    return nil
                }
                return (name, value)
            })
            #expect(inputs["fields[apps]"] == .array([.string("name"), .string("bundleId"), .string("sku"), .string("primaryLocale")]))
            #expect(inputs["limit"] == .integer(200))
            #expect(inputs["sort"] == .array([.string("name"), .string("bundleId"), .string("sku")]))

            let classifications = operation.optionalParameterClassifications ?? []
            #expect(Set(classifications.map(\.appleName)) == nonSparseOptionalInputs.subtracting(Set([boundFilter, "sort", "limit"])))
            #expect(classifications.allSatisfy { classification in
                classification.disposition == .intentionallyOmitted &&
                    classification.reviewAtSpec == "4.4.1" &&
                    !classification.reason.isEmpty
            })
        }
    }
}

private func makeAppsSearchWorker(_ transport: TestHTTPTransport) async throws -> AppsWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return AppsWorker(client: client)
}

private func appsSearchApp(id: String, name: String, bundleID: String, sku: String) -> String {
    #"{"type":"apps","id":"\#(id)","attributes":{"name":"\#(name)","bundleId":"\#(bundleID)","sku":"\#(sku)","primaryLocale":"en-US"}}"#
}

private func appsSearchPage(apps: [String], next: String?) -> String {
    let nextField = next.map { #", "next": "\#($0)""# } ?? ""
    return #"{"data":[\#(apps.joined(separator: ","))],"links":{"self":"https://api.example.test/v1/apps"\#(nextField)}}"#
}

private func appsSearchNextURL(cursor: String, filter: String, query: String) -> String {
    var components = URLComponents(string: "https://api.example.test/v1/apps")!
    components.queryItems = [
        URLQueryItem(name: "cursor", value: cursor),
        URLQueryItem(name: filter, value: query),
        URLQueryItem(name: "fields[apps]", value: "name,bundleId,sku,primaryLocale"),
        URLQueryItem(name: "limit", value: "200"),
        URLQueryItem(name: "sort", value: "name,bundleId,sku")
    ]
    return components.url!.absoluteString
}

private func appsSearchQuery(_ request: URLRequest) -> [String: String] {
    guard let url = request.url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return [:]
    }
    return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
}

private func appsSearchText(_ result: CallTool.Result) -> String {
    result.content.compactMap { content in
        if case .text(let text, _, _) = content { return text }
        return nil
    }.joined(separator: "\n")
}

private func appsSearchObject(_ result: CallTool.Result) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(appsSearchText(result).utf8)) as? [String: Any])
}
