import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Marketing Pagination Scope Tests")
struct MarketingPaginationScopeTests {
    @Test("marketing first pages and continuations preserve exact queries")
    func preservesExactQueries() async throws {
        let fixtures = marketingPaginationFixtures()
        #expect(fixtures.count == 14)
        #expect(fixtures.map(\.toolName) == marketingPaginationToolNames)

        for fixture in fixtures {
            let firstPageTransport = TestHTTPTransport(responses: [
                .init(statusCode: 200, body: marketingPaginationResponseBody(for: fixture))
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

            var continuationArguments = fixture.arguments
            var continuationQuery = fixture.requiredQuery
            continuationQuery["cursor"] = "next"
            let continuationTransport = TestHTTPTransport(responses: [
                .init(
                    statusCode: 200,
                    body: marketingPaginationResponseBody(for: fixture, query: continuationQuery)
                )
            ])
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
                .init(statusCode: 200, body: marketingPaginationResponseBody(for: fixture))
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
                .init(
                    statusCode: 200,
                    body: marketingPaginationResponseBody(for: fixture, query: validQuery)
                )
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

    @Test("marketing continuations accept scoped root-relative links")
    func acceptsScopedRootRelativeLinks() async throws {
        for fixture in marketingPaginationFixtures() {
            var continuationQuery = fixture.requiredQuery
            continuationQuery["cursor"] = "next"
            let transport = TestHTTPTransport(responses: [
                .init(
                    statusCode: 200,
                    body: marketingPaginationResponseBody(for: fixture, query: continuationQuery)
                )
            ])
            var arguments = fixture.arguments
            arguments["next_url"] = .string(marketingPaginationRootRelativeURL(
                path: fixture.path,
                query: continuationQuery
            ))

            let result = try await invokeMarketingPaginationFixture(
                fixture,
                arguments: arguments,
                transport: transport
            )

            #expect(result.isError != true, "Expected root-relative continuation for \(fixture.toolName)")
            let request = try #require(await transport.recordedRequests().first)
            #expect(request.url?.path == fixture.path)
            #expect(marketingPaginationQuery(request) == continuationQuery)
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
            .string("//api.example.test/v1/apps/app-1/promotedPurchases?limit=25&cursor=next"),
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
            var arguments = fixture.arguments
            var query = fixture.requiredQuery
            query["cursor"] = "next"
            let transport = TestHTTPTransport(responses: [
                .init(
                    statusCode: 200,
                    body: marketingPaginationResponseBody(for: fixture, query: query)
                )
            ])
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
    case reviewAttachments
    case screenshots
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

private let marketingPaginationToolNames = [
    "custom_pages_list",
    "custom_pages_list_versions",
    "custom_pages_list_localizations",
    "custom_pages_list_search_keywords",
    "ppo_list_experiments",
    "ppo_list_version_experiments",
    "ppo_list_treatments",
    "ppo_list_treatment_localizations",
    "promoted_list",
    "screenshots_list_sets",
    "screenshots_list",
    "screenshots_list_preview_sets",
    "screenshots_list_previews",
    "review_attachments_list"
]

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
            worker: .customPages,
            toolName: "custom_pages_list_search_keywords",
            arguments: [
                "localization_id": .string("localization-1"),
                "platform": .array([.string("IOS"), .string("MAC_OS")]),
                "locale": .array([.string("en-US"), .string("fr-FR")]),
                "limit": .int(36)
            ],
            path: "/v1/appCustomProductPageLocalizations/localization-1/searchKeywords",
            wrongParentPath: "/v1/appCustomProductPageLocalizations/localization-2/searchKeywords",
            requiredQuery: [
                "filter[platform]": "IOS,MAC_OS",
                "filter[locale]": "en-US,fr-FR",
                "limit": "36"
            ]
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
            toolName: "ppo_list_version_experiments",
            arguments: [
                "version_id": .string("version-1"),
                "states": .array([.string("READY_FOR_REVIEW"), .string("IN_REVIEW")]),
                "limit": .int(37)
            ],
            path: "/v1/appStoreVersions/version-1/appStoreVersionExperimentsV2",
            wrongParentPath: "/v1/appStoreVersions/version-2/appStoreVersionExperimentsV2",
            requiredQuery: ["filter[state]": "READY_FOR_REVIEW,IN_REVIEW", "limit": "37"]
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
        ),
        MarketingPaginationFixture(
            worker: .screenshots,
            toolName: "screenshots_list_sets",
            arguments: [
                "app_store_version_localization_id": .string("localization-1"),
                "display_types": .array([.string("APP_IPHONE_67"), .string("APP_IPAD_PRO_3GEN_129")]),
                "custom_product_page_localization_ids": .array([.string("page-localization-1")]),
                "treatment_localization_ids": .array([.string("treatment-localization-1")]),
                "limit": .int(38)
            ],
            path: "/v1/appStoreVersionLocalizations/localization-1/appScreenshotSets",
            wrongParentPath: "/v1/appStoreVersionLocalizations/localization-2/appScreenshotSets",
            requiredQuery: [
                "filter[screenshotDisplayType]": "APP_IPHONE_67,APP_IPAD_PRO_3GEN_129",
                "filter[appCustomProductPageLocalization]": "page-localization-1",
                "filter[appStoreVersionExperimentTreatmentLocalization]": "treatment-localization-1",
                "limit": "38"
            ]
        ),
        MarketingPaginationFixture(
            worker: .screenshots,
            toolName: "screenshots_list",
            arguments: ["set_id": .string("screenshot-set-1"), "limit": .int(39)],
            path: "/v1/appScreenshotSets/screenshot-set-1/appScreenshots",
            wrongParentPath: "/v1/appScreenshotSets/screenshot-set-2/appScreenshots",
            requiredQuery: ["limit": "39"]
        ),
        MarketingPaginationFixture(
            worker: .screenshots,
            toolName: "screenshots_list_preview_sets",
            arguments: [
                "custom_product_page_localization_id": .string("page-localization-1"),
                "preview_types": .array([.string("IPHONE_67"), .string("IPAD_PRO_3GEN_129")]),
                "app_store_version_localization_ids": .array([.string("localization-1")]),
                "treatment_localization_ids": .array([.string("treatment-localization-1")]),
                "limit": .int(40)
            ],
            path: "/v1/appCustomProductPageLocalizations/page-localization-1/appPreviewSets",
            wrongParentPath: "/v1/appCustomProductPageLocalizations/page-localization-2/appPreviewSets",
            requiredQuery: [
                "filter[previewType]": "IPHONE_67,IPAD_PRO_3GEN_129",
                "filter[appStoreVersionLocalization]": "localization-1",
                "filter[appStoreVersionExperimentTreatmentLocalization]": "treatment-localization-1",
                "limit": "40"
            ]
        ),
        MarketingPaginationFixture(
            worker: .screenshots,
            toolName: "screenshots_list_previews",
            arguments: ["set_id": .string("preview-set-1"), "limit": .int(41)],
            path: "/v1/appPreviewSets/preview-set-1/appPreviews",
            wrongParentPath: "/v1/appPreviewSets/preview-set-2/appPreviews",
            requiredQuery: ["limit": "41"]
        ),
        MarketingPaginationFixture(
            worker: .reviewAttachments,
            toolName: "review_attachments_list",
            arguments: ["review_detail_id": .string("review-detail-1"), "limit": .int(42)],
            path: "/v1/appStoreReviewDetails/review-detail-1/appStoreReviewAttachments",
            wrongParentPath: "/v1/appStoreReviewDetails/review-detail-2/appStoreReviewAttachments",
            requiredQuery: [
                "fields[appStoreReviewAttachments]": "fileSize,fileName,sourceFileChecksum,assetDeliveryState,appStoreReviewDetail",
                "fields[appStoreReviewDetails]": "appStoreVersion",
                "include": "appStoreReviewDetail",
                "limit": "42"
            ]
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
        ),
        MarketingPaginationFixture(
            worker: .customPages,
            toolName: "custom_pages_list_search_keywords",
            arguments: [
                "localization_id": .string("localization-1"),
                "platform": .string("IOS"),
                "locale": .string("en-US")
            ],
            path: "/v1/appCustomProductPageLocalizations/localization-1/searchKeywords",
            wrongParentPath: "/v1/appCustomProductPageLocalizations/localization-2/searchKeywords",
            requiredQuery: [
                "filter[platform]": "IOS",
                "filter[locale]": "en-US",
                "limit": "25"
            ]
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
        ),
        MalformedCustomPageFilterFixture(
            toolName: "custom_pages_list_search_keywords",
            arguments: ["localization_id": .string("localization-1")],
            field: "platform",
            appleName: "filter[platform]",
            path: "/v1/appCustomProductPageLocalizations/localization-1/searchKeywords",
            values: malformedStringFilterValues(first: "IOS", second: "MAC_OS")
        ),
        MalformedCustomPageFilterFixture(
            toolName: "custom_pages_list_search_keywords",
            arguments: ["localization_id": .string("localization-1")],
            field: "locale",
            appleName: "filter[locale]",
            path: "/v1/appCustomProductPageLocalizations/localization-1/searchKeywords",
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
    case .reviewAttachments:
        return try await ReviewAttachmentsWorker(
            httpClient: client,
            uploadService: UploadService()
        ).handleTool(parameters)
    case .screenshots:
        return try await ScreenshotsWorker(
            httpClient: client,
            uploadService: UploadService()
        ).handleTool(parameters)
    }
}

private func marketingPaginationResponseBody(
    for fixture: MarketingPaginationFixture,
    query: [String: String]? = nil
) -> String {
    let responseQuery = query ?? fixture.requiredQuery
    guard let limit = responseQuery["limit"], Int(limit) != nil else {
        preconditionFailure("Missing numeric pagination limit for \(fixture.toolName)")
    }
    let selfURL = marketingPaginationURL(path: fixture.path, query: responseQuery)
    return #"{"data":[],"links":{"self":"\#(selfURL)"},"meta":{"paging":{"total":0,"limit":\#(limit)}}}"#
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

private func marketingPaginationRootRelativeURL(
    path: String,
    query: [String: String]
) -> String {
    guard let absoluteURL = URL(string: marketingPaginationURL(path: path, query: query)),
          let components = URLComponents(url: absoluteURL, resolvingAgainstBaseURL: false),
          let encodedQuery = components.percentEncodedQuery else {
        preconditionFailure("Unable to construct root-relative marketing pagination URL")
    }
    return "\(path)?\(encodedQuery)"
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
