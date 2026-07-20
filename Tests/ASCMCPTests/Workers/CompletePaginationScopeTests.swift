import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Complete Pagination Scope Tests")
struct CompletePaginationScopeTests {
    @Test("strict scope factory binds the complete query and cursor")
    func strictScopeFactoryContract() {
        let query = ["include": "build", "limit": "25"]
        let scope = PaginationScope.strict(path: "/v1/apps/app-1/appStoreVersions", query: query)

        #expect(scope.path == "/v1/apps/app-1/appStoreVersions")
        #expect(scope.requiredParameters == query)
        #expect(scope.allowedParameters == Set(["include", "limit", "cursor"]))
        #expect(scope.requiredNonEmptyParameters == Set(["cursor"]))

        let legacyScope = PaginationScope(path: "/v1/apps")
        #expect(legacyScope.allowedParameters == nil)
        #expect(legacyScope.requiredNonEmptyParameters.isEmpty)
        #expect(completePaginationFixtures().map(\.toolName) == [
            "app_versions_list",
            "app_versions_list_territory_age_ratings",
            "apps_list",
            "apps_list_versions",
            "apps_list_localizations",
            "review_attachments_list"
        ])
    }

    @Test("complete scopes accept default and explicit continuation controls")
    func acceptsDefaultAndExplicitControls() async throws {
        for fixture in completePaginationFixtures() {
            for variant in [fixture.defaultVariant, fixture.explicitVariant] {
                let transport = TestHTTPTransport(responses: completePaginationResponses(
                    for: fixture,
                    includeContinuation: true
                ))
                var arguments = variant.arguments
                var query = variant.requiredQuery
                query["cursor"] = "next"
                arguments["next_url"] = .string(completePaginationURL(path: fixture.path, query: query))

                let result = try await invokeCompletePaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError != true, "Expected valid continuation for \(fixture.toolName)")
                let requests = await transport.recordedRequests()
                try #require(requests.count == fixture.continuationRequestIndex + 1)
                let request = requests[fixture.continuationRequestIndex]
                #expect(request.url?.path == fixture.path)
                #expect(completePaginationQuery(request) == query)
            }
        }
    }

    @Test("complete scopes require a non-empty cursor")
    func rejectsMissingEmptyAndBlankCursors() async throws {
        for fixture in completePaginationFixtures() {
            for cursor in [nil, "", " "] as [String?] {
                var query = fixture.explicitVariant.requiredQuery
                if let cursor {
                    query["cursor"] = cursor
                }
                try await expectCompletePaginationRejection(
                    fixture,
                    arguments: fixture.explicitVariant.arguments,
                    nextURL: completePaginationURL(path: fixture.path, query: query)
                )
            }
        }
    }

    @Test("complete scopes reject every missing or changed originating control")
    func rejectsEveryMissingOrChangedControl() async throws {
        for fixture in completePaginationFixtures() {
            for name in fixture.explicitVariant.requiredQuery.keys.sorted() {
                for mutation in CompletePaginationQueryMutation.allCases {
                    var query = fixture.explicitVariant.requiredQuery
                    switch mutation {
                    case .missing:
                        query.removeValue(forKey: name)
                    case .changed:
                        query[name] = "drift"
                    }
                    query["cursor"] = "next"

                    try await expectCompletePaginationRejection(
                        fixture,
                        arguments: fixture.explicitVariant.arguments,
                        nextURL: completePaginationURL(path: fixture.path, query: query)
                    )
                }
            }
        }
    }

    @Test("complete scopes reject injection, duplicates, path drift, and origin ambiguity")
    func rejectsScopeAndOriginDrift() async throws {
        for fixture in completePaginationFixtures() {
            var query = fixture.explicitVariant.requiredQuery
            query["cursor"] = "next"
            var injectedQuery = query
            injectedQuery["filter[unexpected]"] = "drift"
            let validURL = completePaginationURL(path: fixture.path, query: query)
            let invalidURLs = [
                completePaginationURL(path: fixture.wrongParentPath, query: query),
                completePaginationURL(path: fixture.path, query: injectedQuery),
                validURL + "&limit=1",
                completePaginationURL(path: fixture.path, query: query, host: "attacker.example.test"),
                completePaginationURL(path: fixture.path, query: query, scheme: "http"),
                completePaginationURL(path: fixture.path, query: query, port: 444),
                completePaginationURL(
                    path: fixture.path,
                    query: query,
                    user: "user",
                    password: "password"
                ),
                validURL + "#fragment"
            ]

            for nextURL in invalidURLs {
                try await expectCompletePaginationRejection(
                    fixture,
                    arguments: fixture.explicitVariant.arguments,
                    nextURL: nextURL
                )
            }
        }
    }
}

private enum CompletePaginationWorkerKind {
    case appLifecycle
    case apps
    case reviewAttachments
}

private enum CompletePaginationQueryMutation: CaseIterable {
    case missing
    case changed
}

private struct CompletePaginationVariant {
    let arguments: [String: Value]
    let requiredQuery: [String: String]
}

private struct CompletePaginationFixture {
    let worker: CompletePaginationWorkerKind
    let toolName: String
    let path: String
    let wrongParentPath: String
    let defaultVariant: CompletePaginationVariant
    let explicitVariant: CompletePaginationVariant
    let continuationResponse: String
    let requiresVersionOwnershipRequest: Bool

    var continuationRequestIndex: Int {
        requiresVersionOwnershipRequest ? 1 : 0
    }
}

private func completePaginationFixtures() -> [CompletePaginationFixture] {
    let appVersionInclude = "build,appStoreVersionPhasedRelease"
    let appVersionFields = "platform,versionString,appVersionState,appStoreState,createdDate"
    let localizationFields = "locale,description,whatsNew,keywords,promotionalText,supportUrl,marketingUrl,appStoreVersion"
    let attachmentFields = "fileSize,fileName,sourceFileChecksum,assetDeliveryState,appStoreReviewDetail"

    return [
        CompletePaginationFixture(
            worker: .appLifecycle,
            toolName: "app_versions_list",
            path: "/v1/apps/app-1/appStoreVersions",
            wrongParentPath: "/v1/apps/app-2/appStoreVersions",
            defaultVariant: CompletePaginationVariant(
                arguments: ["app_id": .string("app-1")],
                requiredQuery: ["include": appVersionInclude, "limit": "25"]
            ),
            explicitVariant: CompletePaginationVariant(
                arguments: [
                    "app_id": .string("app-1"),
                    "states": .array([.string("PREPARE_FOR_SUBMISSION"), .string("READY_FOR_SALE")]),
                    "app_version_states": .array([.string("READY_FOR_REVIEW"), .string("WAITING_FOR_REVIEW")]),
                    "platform": .string("IOS"),
                    "version_ids": .array([.string("version-1"), .string("version-2")]),
                    "version_strings": .array([.string("1.0"), .string("1.1")]),
                    "limit": .int(73)
                ],
                requiredQuery: [
                    "include": appVersionInclude,
                    "filter[appStoreState]": "PREPARE_FOR_SUBMISSION,READY_FOR_SALE",
                    "filter[appVersionState]": "READY_FOR_REVIEW,WAITING_FOR_REVIEW",
                    "filter[platform]": "IOS",
                    "filter[id]": "version-1,version-2",
                    "filter[versionString]": "1.0,1.1",
                    "limit": "73"
                ]
            ),
            continuationResponse: #"{"data":[]}"#,
            requiresVersionOwnershipRequest: false
        ),
        CompletePaginationFixture(
            worker: .appLifecycle,
            toolName: "app_versions_list_territory_age_ratings",
            path: "/v1/appInfos/info-1/territoryAgeRatings",
            wrongParentPath: "/v1/appInfos/info-2/territoryAgeRatings",
            defaultVariant: CompletePaginationVariant(
                arguments: ["app_info_id": .string("info-1")],
                requiredQuery: [
                    "fields[territoryAgeRatings]": "appStoreAgeRating,territory",
                    "fields[territories]": "currency",
                    "include": "territory",
                    "limit": "200"
                ]
            ),
            explicitVariant: CompletePaginationVariant(
                arguments: ["app_info_id": .string("info-1"), "limit": .int(73)],
                requiredQuery: [
                    "fields[territoryAgeRatings]": "appStoreAgeRating,territory",
                    "fields[territories]": "currency",
                    "include": "territory",
                    "limit": "73"
                ]
            ),
            continuationResponse: #"{"data":[]}"#,
            requiresVersionOwnershipRequest: false
        ),
        CompletePaginationFixture(
            worker: .apps,
            toolName: "apps_list",
            path: "/v1/apps",
            wrongParentPath: "/v1/apps/app-2",
            defaultVariant: CompletePaginationVariant(
                arguments: [:],
                requiredQuery: ["limit": "25"]
            ),
            explicitVariant: CompletePaginationVariant(
                arguments: [
                    "limit": .int(73),
                    "sort": .string("-name"),
                    "bundle_id": .string("com.example.app"),
                    "name": .string("Example"),
                    "app_ids": .array([.string("app-1"), .string("app-2")]),
                    "skus": .array([.string("SKU-1"), .string("SKU-2")]),
                    "app_store_version_ids": .array([.string("version-1")]),
                    "app_store_states": .array([.string("READY_FOR_SALE")]),
                    "platforms": .array([.string("IOS")]),
                    "app_version_states": .array([.string("READY_FOR_DISTRIBUTION")]),
                    "review_submission_states": .array([.string("READY_FOR_REVIEW")]),
                    "review_submission_platforms": .array([.string("IOS")]),
                    "has_game_center_enabled_versions": .bool(true)
                ],
                requiredQuery: [
                    "limit": "73",
                    "sort": "-name",
                    "filter[bundleId]": "com.example.app",
                    "filter[name]": "Example",
                    "filter[id]": "app-1,app-2",
                    "filter[sku]": "SKU-1,SKU-2",
                    "filter[appStoreVersions]": "version-1",
                    "filter[appStoreVersions.appStoreState]": "READY_FOR_SALE",
                    "filter[appStoreVersions.platform]": "IOS",
                    "filter[appStoreVersions.appVersionState]": "READY_FOR_DISTRIBUTION",
                    "filter[reviewSubmissions.state]": "READY_FOR_REVIEW",
                    "filter[reviewSubmissions.platform]": "IOS",
                    "exists[gameCenterEnabledVersions]": "true"
                ]
            ),
            continuationResponse: #"{"data":[],"links":{"self":"https://api.example.test/v1/apps"}}"#,
            requiresVersionOwnershipRequest: false
        ),
        CompletePaginationFixture(
            worker: .apps,
            toolName: "apps_list_versions",
            path: "/v1/apps/app-1/appStoreVersions",
            wrongParentPath: "/v1/apps/app-2/appStoreVersions",
            defaultVariant: CompletePaginationVariant(
                arguments: ["app_id": .string("app-1")],
                requiredQuery: [
                    "fields[appStoreVersions]": appVersionFields,
                    "limit": "200"
                ]
            ),
            explicitVariant: CompletePaginationVariant(
                arguments: [
                    "app_id": .string("app-1"),
                    "version_ids": .array([.string("version-1"), .string("version-2")]),
                    "version_strings": .array([.string("1.0"), .string("1.1")]),
                    "app_store_states": .array([.string("READY_FOR_SALE")]),
                    "app_version_states": .array([.string("READY_FOR_DISTRIBUTION")]),
                    "platforms": .array([.string("IOS"), .string("VISION_OS")])
                ],
                requiredQuery: [
                    "fields[appStoreVersions]": appVersionFields,
                    "limit": "200",
                    "filter[id]": "version-1,version-2",
                    "filter[versionString]": "1.0,1.1",
                    "filter[appStoreState]": "READY_FOR_SALE",
                    "filter[appVersionState]": "READY_FOR_DISTRIBUTION",
                    "filter[platform]": "IOS,VISION_OS"
                ]
            ),
            continuationResponse: #"{"data":[]}"#,
            requiresVersionOwnershipRequest: false
        ),
        CompletePaginationFixture(
            worker: .apps,
            toolName: "apps_list_localizations",
            path: "/v1/appStoreVersions/version-1/appStoreVersionLocalizations",
            wrongParentPath: "/v1/appStoreVersions/version-2/appStoreVersionLocalizations",
            defaultVariant: CompletePaginationVariant(
                arguments: [
                    "app_id": .string("app-1"),
                    "version_id": .string("version-1")
                ],
                requiredQuery: [
                    "fields[appStoreVersionLocalizations]": localizationFields,
                    "limit": "200"
                ]
            ),
            explicitVariant: CompletePaginationVariant(
                arguments: [
                    "app_id": .string("app-1"),
                    "version_id": .string("version-1"),
                    "locales": .array([.string("en-US"), .string("ru-RU")]),
                    "limit": .int(73)
                ],
                requiredQuery: [
                    "fields[appStoreVersionLocalizations]": localizationFields,
                    "limit": "73",
                    "filter[locale]": "en-US,ru-RU"
                ]
            ),
            continuationResponse: #"{"data":[]}"#,
            requiresVersionOwnershipRequest: true
        ),
        CompletePaginationFixture(
            worker: .reviewAttachments,
            toolName: "review_attachments_list",
            path: "/v1/appStoreReviewDetails/review-detail-1/appStoreReviewAttachments",
            wrongParentPath: "/v1/appStoreReviewDetails/review-detail-2/appStoreReviewAttachments",
            defaultVariant: CompletePaginationVariant(
                arguments: ["review_detail_id": .string("review-detail-1")],
                requiredQuery: [
                    "fields[appStoreReviewAttachments]": attachmentFields,
                    "limit": "25"
                ]
            ),
            explicitVariant: CompletePaginationVariant(
                arguments: [
                    "review_detail_id": .string("review-detail-1"),
                    "limit": .int(73)
                ],
                requiredQuery: [
                    "fields[appStoreReviewAttachments]": attachmentFields,
                    "limit": "73"
                ]
            ),
            continuationResponse: #"{"data":[]}"#,
            requiresVersionOwnershipRequest: false
        )
    ]
}

private func invokeCompletePaginationFixture(
    _ fixture: CompletePaginationFixture,
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
    case .appLifecycle:
        return try await AppLifecycleWorker(httpClient: client).handleTool(parameters)
    case .apps:
        return try await AppsWorker(client: client).handleTool(parameters)
    case .reviewAttachments:
        return try await ReviewAttachmentsWorker(
            httpClient: client,
            uploadService: UploadService(transport: TestHTTPTransport(responses: []))
        ).handleTool(parameters)
    }
}

private func expectCompletePaginationRejection(
    _ fixture: CompletePaginationFixture,
    arguments: [String: Value],
    nextURL: String
) async throws {
    let transport = TestHTTPTransport(responses: completePaginationResponses(
        for: fixture,
        includeContinuation: false
    ))
    var invocationArguments = arguments
    invocationArguments["next_url"] = .string(nextURL)

    let result = try await invokeCompletePaginationFixture(
        fixture,
        arguments: invocationArguments,
        transport: transport
    )

    #expect(result.isError == true, "Expected continuation rejection for \(fixture.toolName)")
    #expect(await transport.requestCount() == fixture.continuationRequestIndex)
}

private func completePaginationResponses(
    for fixture: CompletePaginationFixture,
    includeContinuation: Bool
) -> [TestHTTPTransport.Response] {
    var responses: [TestHTTPTransport.Response] = []
    if fixture.requiresVersionOwnershipRequest {
        responses.append(.init(
            statusCode: 200,
            body: #"{"data":{"type":"appStoreVersions","id":"version-1","attributes":{"platform":"IOS","versionString":"1.0","appVersionState":"PREPARE_FOR_SUBMISSION"},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}}}}}"#
        ))
    }
    if includeContinuation {
        responses.append(.init(statusCode: 200, body: fixture.continuationResponse))
    }
    return responses
}

private func completePaginationURL(
    path: String,
    query: [String: String],
    scheme: String = "https",
    host: String = "api.example.test",
    port: Int? = nil,
    user: String? = nil,
    password: String? = nil
) -> String {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.port = port
    components.user = user
    components.password = password
    components.path = path
    components.queryItems = query.sorted { $0.key < $1.key }.map {
        URLQueryItem(name: $0.key, value: $0.value)
    }
    guard let url = components.url else {
        preconditionFailure("Unable to construct complete pagination URL")
    }
    return url.absoluteString
}

private func completePaginationQuery(_ request: URLRequest) -> [String: String] {
    Dictionary(uniqueKeysWithValues: (URLComponents(
        url: request.url!,
        resolvingAgainstBaseURL: false
    )?.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
    })
}
