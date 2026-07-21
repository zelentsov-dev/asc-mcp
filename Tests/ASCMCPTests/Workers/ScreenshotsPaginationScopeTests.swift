import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Screenshots Pagination Scope Tests")
struct ScreenshotsPaginationScopeTests {
    @Test("first pages and valid continuations preserve exact screenshot queries")
    func preservesExactQueries() async throws {
        for fixture in screenshotPaginationFixtures() {
            let firstPageTransport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: screenshotPaginationEmptyResponse(path: fixture.path))
            ])
            let firstPageResult = try await invokeScreenshotPaginationFixture(
                fixture,
                arguments: fixture.arguments,
                transport: firstPageTransport
            )

            #expect(firstPageResult.isError != true, "Expected first page for \(fixture.toolName)")
            let firstPageRequest = try #require(await firstPageTransport.recordedRequests().first)
            #expect(firstPageRequest.url?.path == fixture.path)
            #expect(screenshotPaginationQuery(firstPageRequest) == fixture.requiredQuery)

            let continuationTransport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: screenshotPaginationEmptyResponse(path: fixture.path))
            ])
            var continuationArguments = fixture.arguments
            var continuationQuery = fixture.requiredQuery
            continuationQuery["cursor"] = "next"
            continuationArguments["next_url"] = .string(screenshotPaginationURL(
                path: fixture.path,
                query: continuationQuery
            ))
            let continuationResult = try await invokeScreenshotPaginationFixture(
                fixture,
                arguments: continuationArguments,
                transport: continuationTransport
            )

            #expect(continuationResult.isError != true, "Expected valid continuation for \(fixture.toolName)")
            let continuationRequest = try #require(await continuationTransport.recordedRequests().first)
            #expect(continuationRequest.url?.path == fixture.path)
            #expect(screenshotPaginationQuery(continuationRequest) == continuationQuery)
        }
    }

    @Test("all screenshot lists preserve the effective default limit")
    func preservesDefaultLimit() async throws {
        for fixture in screenshotDefaultLimitFixtures() {
            let firstPageTransport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: screenshotPaginationEmptyResponse(path: fixture.path))
            ])
            let firstPageResult = try await invokeScreenshotPaginationFixture(
                fixture,
                arguments: fixture.arguments,
                transport: firstPageTransport
            )

            #expect(firstPageResult.isError != true, "Expected default first page for \(fixture.toolName)")
            let firstPageRequest = try #require(await firstPageTransport.recordedRequests().first)
            #expect(screenshotPaginationQuery(firstPageRequest) == ["limit": "25"])

            var validQuery = fixture.requiredQuery
            validQuery["cursor"] = "next"
            let validTransport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: screenshotPaginationEmptyResponse(path: fixture.path))
            ])
            var validArguments = fixture.arguments
            validArguments["next_url"] = .string(screenshotPaginationURL(
                path: fixture.path,
                query: validQuery
            ))
            let validResult = try await invokeScreenshotPaginationFixture(
                fixture,
                arguments: validArguments,
                transport: validTransport
            )

            #expect(validResult.isError != true, "Expected default continuation for \(fixture.toolName)")
            let validRequest = try #require(await validTransport.recordedRequests().first)
            #expect(screenshotPaginationQuery(validRequest) == validQuery)

            let changedTransport = TestHTTPTransport(responses: [])
            var changedArguments = fixture.arguments
            var changedQuery = validQuery
            changedQuery["limit"] = "1"
            changedArguments["next_url"] = .string(screenshotPaginationURL(
                path: fixture.path,
                query: changedQuery
            ))
            let changedResult = try await invokeScreenshotPaginationFixture(
                fixture,
                arguments: changedArguments,
                transport: changedTransport
            )

            #expect(changedResult.isError == true, "Expected default limit drift rejection for \(fixture.toolName)")
            #expect(await changedTransport.requestCount() == 0)
        }
    }

    @Test("screenshot continuations reject every missing or changed originating query value")
    func rejectsMissingAndChangedQueryValues() async throws {
        for fixture in screenshotPaginationFixtures() {
            for name in fixture.requiredQuery.keys {
                for mutation in ScreenshotQueryMutation.allCases {
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
                    arguments["next_url"] = .string(screenshotPaginationURL(
                        path: fixture.path,
                        query: query
                    ))

                    let result = try await invokeScreenshotPaginationFixture(
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

    @Test("screenshot continuations require a non-empty cursor")
    func rejectsMissingAndBlankCursors() async throws {
        for fixture in screenshotPaginationFixtures() {
            for cursor in [String?.none, .some(""), .some(" ")] {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                var query = fixture.requiredQuery
                if let cursor {
                    query["cursor"] = cursor
                }
                arguments["next_url"] = .string(screenshotPaginationURL(
                    path: fixture.path,
                    query: query
                ))

                let result = try await invokeScreenshotPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected cursor rejection for \(fixture.toolName)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }

    @Test("screenshot continuations reject foreign origins ports and parents")
    func rejectsOriginPortAndParentChanges() async throws {
        for fixture in screenshotPaginationFixtures() {
            var validQuery = fixture.requiredQuery
            validQuery["cursor"] = "next"
            let invalidURLs = [
                screenshotPaginationURL(path: fixture.wrongParentPath, query: validQuery),
                screenshotPaginationURL(path: fixture.path, query: validQuery, host: "other.example.test"),
                screenshotPaginationURL(path: fixture.path, query: validQuery, scheme: "http"),
                screenshotPaginationURL(path: fixture.path, query: validQuery, port: 444)
            ]

            for nextURL in invalidURLs {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                arguments["next_url"] = .string(nextURL)

                let result = try await invokeScreenshotPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected origin or path rejection for \(fixture.toolName)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }

    @Test("screenshot continuations reject injected and duplicate query controls")
    func rejectsInjectedAndDuplicateControls() async throws {
        for fixture in screenshotPaginationFixtures() {
            var validQuery = fixture.requiredQuery
            validQuery["cursor"] = "next"

            let injections = [
                ("include", "appScreenshotSet"),
                ("fields[appScreenshots]", "fileName"),
                ("filter[unexpected]", "drift")
            ]
            for (name, value) in injections {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                var injectedQuery = validQuery
                injectedQuery[name] = value
                arguments["next_url"] = .string(screenshotPaginationURL(
                    path: fixture.path,
                    query: injectedQuery
                ))

                let result = try await invokeScreenshotPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected \(name) injection rejection for \(fixture.toolName)")
                #expect(await transport.requestCount() == 0)
            }

            let validURL = screenshotPaginationURL(path: fixture.path, query: validQuery)
            var duplicateNames = ["limit", "cursor"]
            if let filterName = fixture.requiredQuery.keys.first(where: { $0.hasPrefix("filter[") }) {
                duplicateNames.append(filterName)
            }
            for name in duplicateNames {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                arguments["next_url"] = .string(screenshotPaginationURL(
                    validURL,
                    appendingDuplicate: name,
                    value: "duplicate"
                ))

                let result = try await invokeScreenshotPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected duplicate \(name) rejection for \(fixture.toolName)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }

    @Test("screenshot continuations reject malformed next_url values")
    func rejectsMalformedNextURLs() async throws {
        let invalidValues: [Value] = [
            .string(""),
            .string(" "),
            .string("v1/appScreenshotSets/set-1/appScreenshots?limit=25&cursor=next"),
            .string("https://api.example.test/v1/apps?limit=25&cursor=next#fragment"),
            .int(1)
        ]

        for fixture in screenshotPaginationFixtures() {
            for invalidValue in invalidValues {
                let transport = TestHTTPTransport(responses: [])
                var arguments = fixture.arguments
                arguments["next_url"] = invalidValue

                let result = try await invokeScreenshotPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected malformed next_url rejection for \(fixture.toolName)")
                #expect(await transport.requestCount() == 0)
            }
        }
    }
}

private enum ScreenshotQueryMutation: CaseIterable {
    case missing
    case changed
}

private struct ScreenshotPaginationFixture {
    let toolName: String
    let arguments: [String: Value]
    let path: String
    let wrongParentPath: String
    let requiredQuery: [String: String]
}

private func screenshotPaginationFixtures() -> [ScreenshotPaginationFixture] {
    [
        ScreenshotPaginationFixture(
            toolName: "screenshots_list_sets",
            arguments: [
                "localization_id": .string("version-loc-1"),
                "display_types": .array([.string("APP_IPHONE_67"), .string("APP_WATCH_SERIES_10")]),
                "custom_product_page_localization_ids": .array([.string("cpp-loc-1")]),
                "treatment_localization_ids": .array([.string("treatment-loc-1"), .string("treatment-loc-2")]),
                "limit": .int(29)
            ],
            path: "/v1/appStoreVersionLocalizations/version-loc-1/appScreenshotSets",
            wrongParentPath: "/v1/appStoreVersionLocalizations/version-loc-2/appScreenshotSets",
            requiredQuery: [
                "filter[screenshotDisplayType]": "APP_IPHONE_67,APP_WATCH_SERIES_10",
                "filter[appCustomProductPageLocalization]": "cpp-loc-1",
                "filter[appStoreVersionExperimentTreatmentLocalization]": "treatment-loc-1,treatment-loc-2",
                "limit": "29"
            ]
        ),
        ScreenshotPaginationFixture(
            toolName: "screenshots_list_preview_sets",
            arguments: [
                "localization_id": .string("version-loc-1"),
                "preview_types": .array([.string("IPHONE_67"), .string("APPLE_VISION_PRO")]),
                "custom_product_page_localization_ids": .array([.string("cpp-loc-2")]),
                "treatment_localization_ids": .array([.string("treatment-loc-3")]),
                "limit": .int(30)
            ],
            path: "/v1/appStoreVersionLocalizations/version-loc-1/appPreviewSets",
            wrongParentPath: "/v1/appStoreVersionLocalizations/version-loc-2/appPreviewSets",
            requiredQuery: [
                "filter[previewType]": "IPHONE_67,APPLE_VISION_PRO",
                "filter[appCustomProductPageLocalization]": "cpp-loc-2",
                "filter[appStoreVersionExperimentTreatmentLocalization]": "treatment-loc-3",
                "limit": "30"
            ]
        ),
        ScreenshotPaginationFixture(
            toolName: "screenshots_list",
            arguments: ["set_id": .string("screenshot-set-1"), "limit": .int(31)],
            path: "/v1/appScreenshotSets/screenshot-set-1/appScreenshots",
            wrongParentPath: "/v1/appScreenshotSets/screenshot-set-2/appScreenshots",
            requiredQuery: ["limit": "31"]
        ),
        ScreenshotPaginationFixture(
            toolName: "screenshots_list_previews",
            arguments: ["set_id": .string("preview-set-1"), "limit": .int(32)],
            path: "/v1/appPreviewSets/preview-set-1/appPreviews",
            wrongParentPath: "/v1/appPreviewSets/preview-set-2/appPreviews",
            requiredQuery: ["limit": "32"]
        )
    ]
}

private func screenshotDefaultLimitFixtures() -> [ScreenshotPaginationFixture] {
    [
        ScreenshotPaginationFixture(
            toolName: "screenshots_list_sets",
            arguments: ["localization_id": .string("version-loc-1")],
            path: "/v1/appStoreVersionLocalizations/version-loc-1/appScreenshotSets",
            wrongParentPath: "/v1/appStoreVersionLocalizations/version-loc-2/appScreenshotSets",
            requiredQuery: ["limit": "25"]
        ),
        ScreenshotPaginationFixture(
            toolName: "screenshots_list_preview_sets",
            arguments: ["localization_id": .string("version-loc-1")],
            path: "/v1/appStoreVersionLocalizations/version-loc-1/appPreviewSets",
            wrongParentPath: "/v1/appStoreVersionLocalizations/version-loc-2/appPreviewSets",
            requiredQuery: ["limit": "25"]
        ),
        ScreenshotPaginationFixture(
            toolName: "screenshots_list",
            arguments: ["set_id": .string("screenshot-set-1")],
            path: "/v1/appScreenshotSets/screenshot-set-1/appScreenshots",
            wrongParentPath: "/v1/appScreenshotSets/screenshot-set-2/appScreenshots",
            requiredQuery: ["limit": "25"]
        ),
        ScreenshotPaginationFixture(
            toolName: "screenshots_list_previews",
            arguments: ["set_id": .string("preview-set-1")],
            path: "/v1/appPreviewSets/preview-set-1/appPreviews",
            wrongParentPath: "/v1/appPreviewSets/preview-set-2/appPreviews",
            requiredQuery: ["limit": "25"]
        )
    ]
}

private func invokeScreenshotPaginationFixture(
    _ fixture: ScreenshotPaginationFixture,
    arguments: [String: Value],
    transport: TestHTTPTransport
) async throws -> CallTool.Result {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return try await ScreenshotsWorker(
        httpClient: client,
        uploadService: UploadService()
    ).handleTool(CallTool.Parameters(name: fixture.toolName, arguments: arguments))
}

private func screenshotPaginationURL(
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
        preconditionFailure("Unable to construct screenshot pagination URL")
    }
    return url.absoluteString
}

private func screenshotPaginationEmptyResponse(path: String) -> String {
    #"{"data":[],"links":{"self":"\#(path)"}}"#
}

private func screenshotPaginationURL(
    _ url: String,
    appendingDuplicate name: String,
    value: String
) -> String {
    guard var components = URLComponents(string: url) else {
        preconditionFailure("Unable to parse screenshot pagination URL")
    }
    var items = components.queryItems ?? []
    items.append(URLQueryItem(name: name, value: value))
    components.queryItems = items
    guard let duplicateURL = components.url else {
        preconditionFailure("Unable to construct duplicate screenshot pagination URL")
    }
    return duplicateURL.absoluteString
}

private func screenshotPaginationQuery(_ request: URLRequest) -> [String: String] {
    let items = request.url.flatMap {
        URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems
    } ?? []
    return Dictionary(uniqueKeysWithValues: items.compactMap { item in
        item.value.map { (item.name, $0) }
    })
}
