import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Marketing Pagination Scope Tests")
struct MarketingPaginationScopeTests {
    @Test("marketing first pages and continuations preserve exact queries")
    func preservesExactQueries() async throws {
        for fixture in marketingPaginationFixtures() {
            let firstPageTransport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: #"{"data":[]}"#)
            ])
            let firstPageResult = try await invokeMarketingPaginationFixture(
                fixture,
                arguments: fixture.arguments,
                transport: firstPageTransport
            )

            #expect(firstPageResult.isError != true, "Expected first page for \(fixture.toolName)")
            let firstPageRequest = try #require(await firstPageTransport.recordedRequests().first)
            #expect(firstPageRequest.url?.path == fixture.path)
            #expect(marketingPaginationQuery(firstPageRequest) == fixture.requiredQuery)

            let continuationTransport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: #"{"data":[]}"#)
            ])
            var continuationArguments = fixture.arguments
            var continuationQuery = fixture.requiredQuery
            continuationQuery["cursor"] = "next"
            continuationArguments["next_url"] = .string(marketingPaginationURL(
                path: fixture.path,
                query: continuationQuery
            ))
            let continuationResult = try await invokeMarketingPaginationFixture(
                fixture,
                arguments: continuationArguments,
                transport: continuationTransport
            )

            #expect(continuationResult.isError != true, "Expected valid continuation for \(fixture.toolName)")
            let continuationRequest = try #require(await continuationTransport.recordedRequests().first)
            #expect(continuationRequest.url?.path == fixture.path)
            #expect(marketingPaginationQuery(continuationRequest) == continuationQuery)
        }
    }

    @Test("all marketing lists preserve the effective default limit")
    func preservesEffectiveDefaultLimit() async throws {
        for fixture in marketingDefaultLimitFixtures() {
            let firstPageTransport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: #"{"data":[]}"#)
            ])
            let firstPageResult = try await invokeMarketingPaginationFixture(
                fixture,
                arguments: fixture.arguments,
                transport: firstPageTransport
            )

            #expect(firstPageResult.isError != true, "Expected default first page for \(fixture.toolName)")
            let firstPageRequest = try #require(await firstPageTransport.recordedRequests().first)
            #expect(marketingPaginationQuery(firstPageRequest) == fixture.requiredQuery)

            var validQuery = fixture.requiredQuery
            validQuery["cursor"] = "next"
            let validTransport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: #"{"data":[]}"#)
            ])
            var validArguments = fixture.arguments
            validArguments["next_url"] = .string(marketingPaginationURL(
                path: fixture.path,
                query: validQuery
            ))
            let validResult = try await invokeMarketingPaginationFixture(
                fixture,
                arguments: validArguments,
                transport: validTransport
            )

            #expect(validResult.isError != true, "Expected default continuation for \(fixture.toolName)")
            let validRequest = try #require(await validTransport.recordedRequests().first)
            #expect(marketingPaginationQuery(validRequest) == validQuery)

            let changedTransport = TestHTTPTransport(responses: [])
            var changedArguments = fixture.arguments
            var changedQuery = validQuery
            changedQuery["limit"] = "1"
            changedArguments["next_url"] = .string(marketingPaginationURL(
                path: fixture.path,
                query: changedQuery
            ))
            let changedResult = try await invokeMarketingPaginationFixture(
                fixture,
                arguments: changedArguments,
                transport: changedTransport
            )

            #expect(changedResult.isError == true, "Expected default limit drift rejection for \(fixture.toolName)")
            #expect(await changedTransport.requestCount() == 0)
        }
    }

    @Test("marketing continuations reject every missing or changed originating query value")
    func rejectsMissingAndChangedQueryValues() async throws {
        for fixture in marketingPaginationFixtures() {
            for name in fixture.requiredQuery.keys {
                for mutation in MarketingQueryMutation.allCases {
                    let transport = TestHTTPTransport(responses: [])
                    var arguments = fixture.arguments
                    var query = fixture.requiredQuery
                    switch mutation {
                    case .missing:
                        query.removeValue(forKey: name)
                    case .changed:
                        query[name] = "drift"
                    }
                    query["cursor"] = "next"
                    arguments["next_url"] = .string(marketingPaginationURL(
                        path: fixture.path,
                        query: query
                    ))

                    let result = try await invokeMarketingPaginationFixture(
                        fixture,
                        arguments: arguments,
                        transport: transport
                    )

                    #expect(result.isError == true, "Expected \(mutation) \(name) rejection for \(fixture.toolName)")
                    #expect(await transport.requestCount() == 0)
                }
            }
        }
    }

    @Test("marketing continuations require a non-empty cursor")
    func rejectsMissingAndBlankCursors() async throws {
        for fixture in marketingPaginationFixtures() {
            for cursor in [String?.none, .some(""), .some(" ")] {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                var query = fixture.requiredQuery
                if let cursor {
                    query["cursor"] = cursor
                }
                arguments["next_url"] = .string(marketingPaginationURL(
                    path: fixture.path,
                    query: query
                ))

                let result = try await invokeMarketingPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected cursor rejection for \(fixture.toolName)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }

    @Test("marketing continuations reject foreign origins ports and parents")
    func rejectsOriginPortAndParentChanges() async throws {
        for fixture in marketingPaginationFixtures() {
            var validQuery = fixture.requiredQuery
            validQuery["cursor"] = "next"
            let invalidURLs = [
                marketingPaginationURL(path: fixture.wrongParentPath, query: validQuery),
                marketingPaginationURL(path: fixture.path, query: validQuery, host: "other.example.test"),
                marketingPaginationURL(path: fixture.path, query: validQuery, scheme: "http"),
                marketingPaginationURL(path: fixture.path, query: validQuery, port: 444)
            ]

            for nextURL in invalidURLs {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                arguments["next_url"] = .string(nextURL)

                let result = try await invokeMarketingPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected origin or parent rejection for \(fixture.toolName)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }

    @Test("marketing continuations reject injected and duplicate query controls")
    func rejectsInjectedAndDuplicateControls() async throws {
        for fixture in marketingPaginationFixtures() {
            var validQuery = fixture.requiredQuery
            validQuery["cursor"] = "next"

            let injections = [
                ("include", "app"),
                ("fields[appCustomProductPages]", "id"),
                ("limit[appCustomProductPageVersions]", "1"),
                ("filter[unexpected]", "drift")
            ]
            for (name, value) in injections {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                var injectedQuery = validQuery
                injectedQuery[name] = value
                arguments["next_url"] = .string(marketingPaginationURL(
                    path: fixture.path,
                    query: injectedQuery
                ))

                let result = try await invokeMarketingPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected \(name) injection rejection for \(fixture.toolName)")
                #expect(await transport.requestCount() == 0)
            }

            let validURL = marketingPaginationURL(path: fixture.path, query: validQuery)
            var duplicateNames = ["limit", "cursor"]
            if let filterName = fixture.requiredQuery.keys.first(where: { $0.hasPrefix("filter[") }) {
                duplicateNames.append(filterName)
            }
            for name in duplicateNames {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                arguments["next_url"] = .string(marketingPaginationURL(
                    validURL,
                    appendingDuplicate: name,
                    value: "duplicate"
                ))

                let result = try await invokeMarketingPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected duplicate \(name) rejection for \(fixture.toolName)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }

    @Test("marketing continuations reject malformed next_url values")
    func rejectsMalformedNextURLs() async throws {
        let invalidValues: [Value] = [
            .string(""),
            .string(" "),
            .string("/v1/apps/app-1/promotedPurchases?limit=25&cursor=next"),
            .string("https://api.example.test/v1/apps/app-1/promotedPurchases?limit=25&cursor=next#fragment"),
            .int(1)
        ]

        for fixture in marketingPaginationFixtures() {
            for invalidValue in invalidValues {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                arguments["next_url"] = invalidValue

                let result = try await invokeMarketingPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected malformed next_url rejection for \(fixture.toolName)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }

    @Test("custom page continuations accept scalar filter values")
    func acceptsCustomPageScalarFilters() async throws {
        for fixture in customPageScalarPaginationFixtures() {
            let transport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: #"{"data":[]}"#)
            ])
            var arguments = fixture.arguments
            var query = fixture.requiredQuery
            query["cursor"] = "next"
            arguments["next_url"] = .string(marketingPaginationURL(path: fixture.path, query: query))

            let result = try await invokeMarketingPaginationFixture(
                fixture,
                arguments: arguments,
                transport: transport
            )

            #expect(result.isError != true, "Expected scalar continuation for \(fixture.toolName)")
            let request = try #require(await transport.recordedRequests().first)
            #expect(marketingPaginationQuery(request) == query)
        }
    }

    @Test("malformed custom page filters fail before continuation network access")
    func rejectsMalformedCustomPageFiltersWithNextURL() async throws {
        for fixture in malformedCustomPageFilterFixtures() {
            for malformed in fixture.values {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                arguments[fixture.field] = malformed.value
                arguments["next_url"] = .string(marketingPaginationURL(
                    path: fixture.path,
                    query: [
                        "limit": "25",
                        fixture.appleName: malformed.serializedValue,
                        "cursor": "next"
                    ]
                ))

                let result = try await invokeMarketingPaginationFixture(
                    MarketingPaginationFixture(
                        worker: .customPages,
                        toolName: fixture.toolName,
                        arguments: arguments,
                        path: fixture.path,
                        wrongParentPath: fixture.path,
                        requiredQuery: [:]
                    ),
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected malformed \(fixture.field) rejection for \(fixture.toolName)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }
}

private enum MarketingPaginationWorker {
    case customPages
    case ppo
    case promoted
}

private enum MarketingQueryMutation: CaseIterable {
    case missing
    case changed
}

private struct MarketingPaginationFixture {
    let worker: MarketingPaginationWorker
    let toolName: String
    let arguments: [String: Value]
    let path: String
    let wrongParentPath: String
    let requiredQuery: [String: String]
}

private struct MalformedCustomPageFilterFixture {
    let toolName: String
    let arguments: [String: Value]
    let field: String
    let appleName: String
    let path: String
    let values: [MalformedCustomPageFilterValue]
}

private struct MalformedCustomPageFilterValue {
    let value: Value
    let serializedValue: String
}

private func marketingPaginationFixtures() -> [MarketingPaginationFixture] {
    [
        MarketingPaginationFixture(
            worker: .customPages,
            toolName: "custom_pages_list",
            arguments: [
                "app_id": .string("app-1"),
                "visible": .array([.bool(true), .bool(false)]),
                "limit": .int(29)
            ],
            path: "/v1/apps/app-1/appCustomProductPages",
            wrongParentPath: "/v1/apps/app-2/appCustomProductPages",
            requiredQuery: ["filter[visible]": "true,false", "limit": "29"]
        ),
        MarketingPaginationFixture(
            worker: .customPages,
            toolName: "custom_pages_list_versions",
            arguments: [
                "page_id": .string("page-1"),
                "state": .array([.string("READY_FOR_REVIEW"), .string("IN_REVIEW")]),
                "limit": .int(30)
            ],
            path: "/v1/appCustomProductPages/page-1/appCustomProductPageVersions",
            wrongParentPath: "/v1/appCustomProductPages/page-2/appCustomProductPageVersions",
            requiredQuery: ["filter[state]": "READY_FOR_REVIEW,IN_REVIEW", "limit": "30"]
        ),
        MarketingPaginationFixture(
            worker: .customPages,
            toolName: "custom_pages_list_localizations",
            arguments: [
                "version_id": .string("version-1"),
                "locale": .array([.string("en-US"), .string("fr-FR")]),
                "limit": .int(31)
            ],
            path: "/v1/appCustomProductPageVersions/version-1/appCustomProductPageLocalizations",
            wrongParentPath: "/v1/appCustomProductPageVersions/version-2/appCustomProductPageLocalizations",
            requiredQuery: ["filter[locale]": "en-US,fr-FR", "limit": "31"]
        ),
        MarketingPaginationFixture(
            worker: .ppo,
            toolName: "ppo_list_experiments",
            arguments: [
                "app_id": .string("app-1"),
                "states": .array([.string("READY_FOR_REVIEW"), .string("IN_REVIEW")]),
                "limit": .int(32)
            ],
            path: "/v1/apps/app-1/appStoreVersionExperimentsV2",
            wrongParentPath: "/v1/apps/app-2/appStoreVersionExperimentsV2",
            requiredQuery: ["filter[state]": "READY_FOR_REVIEW,IN_REVIEW", "limit": "32"]
        ),
        MarketingPaginationFixture(
            worker: .ppo,
            toolName: "ppo_list_treatments",
            arguments: ["experiment_id": .string("experiment-1"), "limit": .int(33)],
            path: "/v2/appStoreVersionExperiments/experiment-1/appStoreVersionExperimentTreatments",
            wrongParentPath: "/v2/appStoreVersionExperiments/experiment-2/appStoreVersionExperimentTreatments",
            requiredQuery: ["limit": "33"]
        ),
        MarketingPaginationFixture(
            worker: .ppo,
            toolName: "ppo_list_treatment_localizations",
            arguments: [
                "treatment_id": .string("treatment-1"),
                "locale": .array([.string("en-US"), .string("ja")]),
                "limit": .int(34)
            ],
            path: "/v1/appStoreVersionExperimentTreatments/treatment-1/appStoreVersionExperimentTreatmentLocalizations",
            wrongParentPath: "/v1/appStoreVersionExperimentTreatments/treatment-2/appStoreVersionExperimentTreatmentLocalizations",
            requiredQuery: ["filter[locale]": "en-US,ja", "limit": "34"]
        ),
        MarketingPaginationFixture(
            worker: .promoted,
            toolName: "promoted_list",
            arguments: ["app_id": .string("app-1"), "limit": .int(35)],
            path: "/v1/apps/app-1/promotedPurchases",
            wrongParentPath: "/v1/apps/app-2/promotedPurchases",
            requiredQuery: ["limit": "35"]
        )
    ]
}

private func marketingDefaultLimitFixtures() -> [MarketingPaginationFixture] {
    marketingPaginationFixtures().map { fixture in
        var arguments = fixture.arguments
        arguments.removeValue(forKey: "limit")
        var requiredQuery = fixture.requiredQuery
        requiredQuery["limit"] = "25"
        return MarketingPaginationFixture(
            worker: fixture.worker,
            toolName: fixture.toolName,
            arguments: arguments,
            path: fixture.path,
            wrongParentPath: fixture.wrongParentPath,
            requiredQuery: requiredQuery
        )
    }
}

private func customPageScalarPaginationFixtures() -> [MarketingPaginationFixture] {
    [
        MarketingPaginationFixture(
            worker: .customPages,
            toolName: "custom_pages_list",
            arguments: ["app_id": .string("app-1"), "visible": .bool(true)],
            path: "/v1/apps/app-1/appCustomProductPages",
            wrongParentPath: "/v1/apps/app-2/appCustomProductPages",
            requiredQuery: ["filter[visible]": "true", "limit": "25"]
        ),
        MarketingPaginationFixture(
            worker: .customPages,
            toolName: "custom_pages_list_versions",
            arguments: ["page_id": .string("page-1"), "state": .string("READY_FOR_REVIEW")],
            path: "/v1/appCustomProductPages/page-1/appCustomProductPageVersions",
            wrongParentPath: "/v1/appCustomProductPages/page-2/appCustomProductPageVersions",
            requiredQuery: ["filter[state]": "READY_FOR_REVIEW", "limit": "25"]
        ),
        MarketingPaginationFixture(
            worker: .customPages,
            toolName: "custom_pages_list_localizations",
            arguments: ["version_id": .string("version-1"), "locale": .string("en-US")],
            path: "/v1/appCustomProductPageVersions/version-1/appCustomProductPageLocalizations",
            wrongParentPath: "/v1/appCustomProductPageVersions/version-2/appCustomProductPageLocalizations",
            requiredQuery: ["filter[locale]": "en-US", "limit": "25"]
        )
    ]
}

private func malformedCustomPageFilterFixtures() -> [MalformedCustomPageFilterFixture] {
    [
        MalformedCustomPageFilterFixture(
            toolName: "custom_pages_list",
            arguments: ["app_id": .string("app-1")],
            field: "visible",
            appleName: "filter[visible]",
            path: "/v1/apps/app-1/appCustomProductPages",
            values: [
                .init(value: .string("true"), serializedValue: "true"),
                .init(value: .array([]), serializedValue: "true"),
                .init(value: .array([.bool(true), .bool(true)]), serializedValue: "true,true"),
                .init(value: .array([.bool(true), .string("false")]), serializedValue: "true,false")
            ]
        ),
        MalformedCustomPageFilterFixture(
            toolName: "custom_pages_list_versions",
            arguments: ["page_id": .string("page-1")],
            field: "state",
            appleName: "filter[state]",
            path: "/v1/appCustomProductPages/page-1/appCustomProductPageVersions",
            values: malformedStringFilterValues(
                first: "READY_FOR_REVIEW",
                second: "IN_REVIEW"
            )
        ),
        MalformedCustomPageFilterFixture(
            toolName: "custom_pages_list_localizations",
            arguments: ["version_id": .string("version-1")],
            field: "locale",
            appleName: "filter[locale]",
            path: "/v1/appCustomProductPageVersions/version-1/appCustomProductPageLocalizations",
            values: malformedStringFilterValues(first: "en-US", second: "fr-FR")
        )
    ]
}

private func malformedStringFilterValues(
    first: String,
    second: String
) -> [MalformedCustomPageFilterValue] {
    [
        .init(value: .string(" \(first) "), serializedValue: first),
        .init(value: .string("\(first),\(second)"), serializedValue: "\(first),\(second)"),
        .init(value: .string(""), serializedValue: ""),
        .init(value: .array([.string(" \(first) ")]), serializedValue: first),
        .init(value: .array([.string("\(first),\(second)")]), serializedValue: "\(first),\(second)"),
        .init(value: .array([]), serializedValue: first),
        .init(value: .array([.string(first), .string(first)]), serializedValue: "\(first),\(first)"),
        .init(value: .array([.string(first), .int(1)]), serializedValue: first)
    ]
}

private func invokeMarketingPaginationFixture(
    _ fixture: MarketingPaginationFixture,
    arguments: [String: Value],
    transport: TestHTTPTransport
) async throws -> CallTool.Result {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    let parameters = CallTool.Parameters(name: fixture.toolName, arguments: arguments)
    switch fixture.worker {
    case .customPages:
        return try await CustomProductPagesWorker(httpClient: client).handleTool(parameters)
    case .ppo:
        return try await ProductPageOptimizationWorker(httpClient: client).handleTool(parameters)
    case .promoted:
        return try await PromotedPurchasesWorker(
            httpClient: client,
            uploadService: UploadService()
        ).handleTool(parameters)
    }
}

private func marketingPaginationURL(
    path: String,
    query: [String: String],
    host: String = "api.example.test",
    scheme: String = "https",
    port: Int? = nil
) -> String {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.port = port
    components.path = path
    components.queryItems = query.sorted { $0.key < $1.key }.map {
        URLQueryItem(name: $0.key, value: $0.value)
    }
    guard let url = components.url else {
        preconditionFailure("Unable to construct marketing pagination URL")
    }
    return url.absoluteString
}

private func marketingPaginationURL(
    _ url: String,
    appendingDuplicate name: String,
    value: String
) -> String {
    guard var components = URLComponents(string: url) else {
        preconditionFailure("Unable to parse marketing pagination URL")
    }
    var items = components.queryItems ?? []
    items.append(URLQueryItem(name: name, value: value))
    components.queryItems = items
    guard let duplicateURL = components.url else {
        preconditionFailure("Unable to construct duplicate marketing pagination URL")
    }
    return duplicateURL.absoluteString
}

private func marketingPaginationQuery(_ request: URLRequest) -> [String: String] {
    let items = request.url.flatMap {
        URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems
    } ?? []
    return Dictionary(uniqueKeysWithValues: items.compactMap { item in
        item.value.map { (item.name, $0) }
    })
}
