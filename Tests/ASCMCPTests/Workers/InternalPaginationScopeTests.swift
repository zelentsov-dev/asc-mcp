import Foundation
import Testing
@testable import asc_mcp

@Suite("Internal Pagination Scope Tests")
struct InternalPaginationScopeTests {
    @Test("all six internal loops preserve exact continuation context")
    func acceptsExactInternalContinuations() throws {
        let fixtures = internalPaginationFixtures()
        #expect(fixtures.count == 6)

        for fixture in fixtures {
            for query in fixture.queries {
                let scope = PaginationScope.strict(path: fixture.path, query: query)
                #expect(scope.requiredParameters == query)
                #expect(scope.allowedParameters == Set(query.keys).union(["cursor"]))
                #expect(scope.requiredNonEmptyParameters == Set(["cursor"]))

                var continuationQuery = query
                continuationQuery["cursor"] = "next"
                let request = try validatedPaginationRequest(
                    internalPaginationURL(path: fixture.path, query: continuationQuery),
                    baseURL: "https://api.example.test",
                    scope: scope
                )
                #expect(request.parameters == continuationQuery)
            }
        }
    }

    @Test("all internal loops reject cursor query and boundary drift")
    func rejectsInternalContinuationDrift() throws {
        for fixture in internalPaginationFixtures() {
            for query in fixture.queries {
                let scope = PaginationScope.strict(path: fixture.path, query: query)

                for name in query.keys {
                    var missing = query
                    missing.removeValue(forKey: name)
                    missing["cursor"] = "next"
                    #expect(throws: ASCError.self) {
                        try validatedPaginationRequest(
                            internalPaginationURL(path: fixture.path, query: missing),
                            baseURL: "https://api.example.test",
                            scope: scope
                        )
                    }

                    var changed = query
                    changed[name] = "drift"
                    changed["cursor"] = "next"
                    #expect(throws: ASCError.self) {
                        try validatedPaginationRequest(
                            internalPaginationURL(path: fixture.path, query: changed),
                            baseURL: "https://api.example.test",
                            scope: scope
                        )
                    }
                }

                for cursor in [String?.none, .some(""), .some(" ")] {
                    var invalidCursor = query
                    if let cursor {
                        invalidCursor["cursor"] = cursor
                    }
                    #expect(throws: ASCError.self) {
                        try validatedPaginationRequest(
                            internalPaginationURL(path: fixture.path, query: invalidCursor),
                            baseURL: "https://api.example.test",
                            scope: scope
                        )
                    }
                }

                var valid = query
                valid["cursor"] = "next"
                var injection = valid
                injection["filter[unexpected]"] = "drift"
                let validURL = internalPaginationURL(path: fixture.path, query: valid)
                let invalidURLs = [
                    internalPaginationURL(path: fixture.path, query: injection),
                    internalPaginationURL(validURL, duplicate: "cursor"),
                    internalPaginationURL(validURL, duplicate: query.keys.sorted().first ?? "limit"),
                    internalPaginationURL(path: fixture.wrongPath, query: valid),
                    internalPaginationURL(path: fixture.path, query: valid, host: "other.example.test"),
                    internalPaginationURL(path: fixture.path, query: valid, scheme: "http"),
                    internalPaginationURL(path: fixture.path, query: valid, port: 444),
                    internalPaginationURL(path: fixture.path, query: valid, user: "attacker"),
                    internalPaginationURL(path: fixture.path, query: valid, fragment: "fragment")
                ]

                for invalidURL in invalidURLs {
                    #expect(throws: ASCError.self) {
                        try validatedPaginationRequest(
                            invalidURL,
                            baseURL: "https://api.example.test",
                            scope: scope
                        )
                    }
                }
            }
        }
    }

    @Test("remaining inventory cannot regress to permissive scope construction")
    func targetWorkersUseOnlyStrictScopes() throws {
        let workersRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/asc-mcp/Workers", isDirectory: true)
        let workerNames = [
            "AccessibilityWorker", "AnalyticsWorker", "AppEventsWorker", "AppInfoWorker",
            "AppLifecycleWorker", "AppsWorker", "BetaFeedbackWorker", "BetaGroupsWorker",
            "BetaLicenseAgreementsWorker", "BetaTestersWorker", "BuildBetaDetailsWorker",
            "BuildsWorker", "MetricsWorker", "PreReleaseVersionsWorker", "PricingWorker",
            "ProvisioningWorker", "ReviewAttachmentsWorker", "ReviewsWorker",
            "SandboxTestersWorker", "UsersWorker", "WebhooksWorker"
        ]
        var strictScopeCount = 0
        var permissiveFiles: [String] = []

        for workerName in workerNames {
            let directory = workersRoot.appendingPathComponent(workerName, isDirectory: true)
            let files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasSuffix("Handlers.swift") }
            for file in files {
                let source = try String(contentsOf: file, encoding: .utf8)
                strictScopeCount += source.components(separatedBy: "PaginationScope.strict(").count - 1
                if source.contains("PaginationScope(") {
                    permissiveFiles.append(workerName)
                }
            }
        }

        #expect(strictScopeCount == 55)
        #expect(permissiveFiles.isEmpty, "Target workers must not construct permissive scopes: \(permissiveFiles)")
    }
}

private struct InternalPaginationFixture {
    let name: String
    let path: String
    let wrongPath: String
    let queries: [[String: String]]
}

private func internalPaginationFixtures() -> [InternalPaginationFixture] {
    [
        InternalPaginationFixture(
            name: "apps_search",
            path: "/v1/apps",
            wrongPath: "/v1/users",
            queries: [
                ["filter[name]": "Needle", "fields[apps]": "name,bundleId,sku,primaryLocale", "limit": "200", "sort": "name,bundleId,sku"],
                ["filter[bundleId]": "Needle", "fields[apps]": "name,bundleId,sku,primaryLocale", "limit": "200", "sort": "name,bundleId,sku"]
            ]
        ),
        InternalPaginationFixture(
            name: "apps_metadata_versions",
            path: "/v1/apps/app-1/appStoreVersions",
            wrongPath: "/v1/apps/app-2/appStoreVersions",
            queries: [["fields[appStoreVersions]": "platform,versionString,appVersionState,appStoreState,createdDate", "limit": "200"]]
        ),
        InternalPaginationFixture(
            name: "apps_metadata_previews",
            path: "/v1/appStoreVersionLocalizations/localization-1/appPreviewSets",
            wrongPath: "/v1/appStoreVersionLocalizations/localization-2/appPreviewSets",
            queries: [["include": "appPreviews", "limit": "200", "limit[appPreviews]": "50"]]
        ),
        InternalPaginationFixture(
            name: "apps_metadata_screenshots",
            path: "/v1/appStoreVersionLocalizations/localization-1/appScreenshotSets",
            wrongPath: "/v1/appStoreVersionLocalizations/localization-2/appScreenshotSets",
            queries: [["include": "appScreenshots", "limit": "200", "limit[appScreenshots]": "50"]]
        ),
        InternalPaginationFixture(
            name: "analytics_snapshot_reports",
            path: "/v1/analyticsReportRequests/request-1/reports",
            wrongPath: "/v1/analyticsReportRequests/request-2/reports",
            queries: [
                ["limit": "200"],
                ["filter[category]": "COMMERCE", "filter[name]": "Sales", "limit": "200"]
            ]
        ),
        InternalPaginationFixture(
            name: "reviews_stats",
            path: "/v1/apps/app-1/customerReviews",
            wrongPath: "/v1/apps/app-2/customerReviews",
            queries: [
                ["limit": "200", "sort": "-createdDate"],
                ["filter[territory]": "USA", "exists[publishedResponse]": "true", "limit": "200", "sort": "-createdDate"]
            ]
        )
    ]
}

private func internalPaginationURL(
    path: String,
    query: [String: String],
    scheme: String = "https",
    host: String = "api.example.test",
    port: Int? = nil,
    user: String? = nil,
    fragment: String? = nil
) -> String {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.port = port
    components.user = user
    components.path = path
    components.queryItems = query.sorted { $0.key < $1.key }.map {
        URLQueryItem(name: $0.key, value: $0.value)
    }
    components.fragment = fragment
    return components.url?.absoluteString ?? "invalid"
}

private func internalPaginationURL(_ url: String, duplicate name: String) -> String {
    guard var components = URLComponents(string: url) else {
        preconditionFailure("Unable to parse internal pagination fixture URL")
    }
    var items = components.queryItems ?? []
    items.append(URLQueryItem(name: name, value: "duplicate"))
    components.queryItems = items
    return components.url?.absoluteString ?? "invalid"
}
