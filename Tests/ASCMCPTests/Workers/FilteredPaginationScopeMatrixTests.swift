import Foundation
import Testing
@testable import asc_mcp

@Suite("Filtered Pagination Scope Matrix Tests")
struct FilteredPaginationScopeMatrixTests {
    @Test("all 33 filtered scopes accept only exact default and explicit continuations")
    func acceptsExactContinuations() throws {
        let fixtures = filteredPaginationFixtures()
        #expect(fixtures.count == 33)

        for fixture in fixtures {
            for query in [fixture.defaultQuery, fixture.explicitQuery] {
                let scope = PaginationScope.strict(path: fixture.path, query: query)
                #expect(scope.requiredParameters == query)
                #expect(scope.allowedParameters == Set(query.keys).union(["cursor"]))
                #expect(scope.requiredNonEmptyParameters == Set(["cursor"]))

                var continuationQuery = query
                continuationQuery["cursor"] = "next"
                let request = try validatedPaginationRequest(
                    paginationMatrixURL(path: fixture.path, query: continuationQuery),
                    baseURL: "https://api.example.test",
                    scope: scope
                )
                #expect(request.path == fixture.path)
                #expect(request.parameters == continuationQuery)
            }
        }
    }

    @Test("all filtered scopes reject every missing or changed originating value")
    func rejectsOriginatingQueryDrift() throws {
        for fixture in filteredPaginationFixtures() {
            for query in [fixture.defaultQuery, fixture.explicitQuery] {
                let scope = PaginationScope.strict(path: fixture.path, query: query)
                for name in query.keys {
                    var missing = query
                    missing.removeValue(forKey: name)
                    missing["cursor"] = "next"
                    #expect(throws: ASCError.self) {
                        try validatedPaginationRequest(
                            paginationMatrixURL(path: fixture.path, query: missing),
                            baseURL: "https://api.example.test",
                            scope: scope
                        )
                    }

                    var changed = query
                    changed[name] = "drift"
                    changed["cursor"] = "next"
                    #expect(throws: ASCError.self) {
                        try validatedPaginationRequest(
                            paginationMatrixURL(path: fixture.path, query: changed),
                            baseURL: "https://api.example.test",
                            scope: scope
                        )
                    }
                }
            }
        }
    }

    @Test("all filtered scopes reject missing empty and blank cursors")
    func rejectsInvalidCursors() throws {
        for fixture in filteredPaginationFixtures() {
            let scope = PaginationScope.strict(path: fixture.path, query: fixture.defaultQuery)
            for cursor in [String?.none, .some(""), .some(" ")] {
                var query = fixture.defaultQuery
                if let cursor {
                    query["cursor"] = cursor
                }
                #expect(throws: ASCError.self) {
                    try validatedPaginationRequest(
                        paginationMatrixURL(path: fixture.path, query: query),
                        baseURL: "https://api.example.test",
                        scope: scope
                    )
                }
            }
        }
    }

    @Test("all filtered scopes reject injection duplicates wrong paths and foreign origins")
    func rejectsBoundaryViolations() throws {
        for fixture in filteredPaginationFixtures() {
            let scope = PaginationScope.strict(path: fixture.path, query: fixture.defaultQuery)
            var validQuery = fixture.defaultQuery
            validQuery["cursor"] = "next"

            var injectedQuery = validQuery
            injectedQuery["filter[unexpected]"] = "drift"
            let validURL = paginationMatrixURL(path: fixture.path, query: validQuery)
            let invalidURLs = [
                paginationMatrixURL(path: fixture.path, query: injectedQuery),
                paginationMatrixURL(validURL, duplicate: "cursor", value: "again"),
                paginationMatrixURL(
                    validURL,
                    duplicate: fixture.defaultQuery.keys.sorted().first ?? "limit",
                    value: "again"
                ),
                paginationMatrixURL(path: fixture.wrongPath, query: validQuery),
                paginationMatrixURL(path: fixture.path, query: validQuery, host: "other.example.test"),
                paginationMatrixURL(path: fixture.path, query: validQuery, scheme: "http"),
                paginationMatrixURL(path: fixture.path, query: validQuery, port: 444),
                paginationMatrixURL(path: fixture.path, query: validQuery, user: "attacker"),
                paginationMatrixURL(path: fixture.path, query: validQuery, fragment: "fragment")
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

private struct FilteredPaginationFixture {
    let tool: String
    let path: String
    let wrongPath: String
    let defaultQuery: [String: String]
    let explicitQuery: [String: String]
}

private func filteredPaginationFixtures() -> [FilteredPaginationFixture] {
    [
        fixture(
            "accessibility_list",
            "/v1/apps/app-1/accessibilityDeclarations",
            "/v1/apps/app-2/accessibilityDeclarations",
            ["limit": "25"],
            ["limit": "31", "filter[deviceFamily]": "IPHONE", "filter[state]": "PUBLISHED", "fields[accessibilityDeclarations]": "deviceFamily,state"]
        ),
        fixture(
            "analytics_list_report_requests",
            "/v1/apps/app-1/analyticsReportRequests",
            "/v1/apps/app-2/analyticsReportRequests",
            ["limit": "25"],
            ["limit": "31", "filter[accessType]": "ONGOING", "include": "reports", "limit[reports]": "11"]
        ),
        fixture(
            "analytics_list_reports",
            "/v1/analyticsReportRequests/request-1/reports",
            "/v1/analyticsReportRequests/request-2/reports",
            ["limit": "25"],
            ["limit": "31", "filter[name]": "App Sessions", "filter[category]": "APP_USAGE"]
        ),
        fixture(
            "analytics_list_instances",
            "/v1/analyticsReports/report-1/instances",
            "/v1/analyticsReports/report-2/instances",
            ["limit": "25"],
            ["limit": "31", "filter[granularity]": "DAILY", "filter[processingDate]": "2026-07-20"]
        ),
        fixture(
            "app_events_list",
            "/v1/apps/app-1/appEvents",
            "/v1/apps/app-2/appEvents",
            ["limit": "25"],
            ["limit": "31", "filter[eventState]": "PUBLISHED", "filter[id]": "event-1", "include": "localizations", "limit[localizations]": "11"]
        ),
        fixture(
            "app_events_list_localizations",
            "/v1/appEvents/event-1/localizations",
            "/v1/appEvents/event-2/localizations",
            ["limit": "25"],
            ["limit": "31", "include": "appEvent,appEventScreenshots,appEventVideoClips", "limit[appEventScreenshots]": "11", "limit[appEventVideoClips]": "12"]
        ),
        fixture(
            "app_info_list",
            "/v1/apps/app-1/appInfos",
            "/v1/apps/app-2/appInfos",
            ["limit": "25"],
            ["limit": "31", "include": "appInfoLocalizations", "limit[appInfoLocalizations]": "11"]
        ),
        fixture(
            "app_info_list_localizations",
            "/v1/appInfos/info-1/appInfoLocalizations",
            "/v1/appInfos/info-2/appInfoLocalizations",
            ["limit": "25"],
            ["limit": "31", "filter[locale]": "en-US", "include": "appInfo"]
        ),
        fixture(
            "beta_feedback_list_crashes",
            "/v1/apps/app-1/betaFeedbackCrashSubmissions",
            "/v1/apps/app-2/betaFeedbackCrashSubmissions",
            ["limit": "25", "sort": "-createdDate"],
            ["limit": "31", "sort": "createdDate", "filter[build]": "build-1", "include": "build,tester"]
        ),
        fixture(
            "beta_feedback_list_screenshots",
            "/v1/apps/app-1/betaFeedbackScreenshotSubmissions",
            "/v1/apps/app-2/betaFeedbackScreenshotSubmissions",
            ["limit": "25", "sort": "-createdDate"],
            ["limit": "31", "sort": "createdDate", "filter[tester]": "tester-1", "include": "build,tester"]
        ),
        fixture(
            "beta_groups_list",
            "/v1/betaGroups",
            "/v1/users",
            ["filter[app]": "app-1", "limit": "25"],
            ["filter[app]": "app-1", "limit": "31", "filter[name]": "Internal", "filter[isInternalGroup]": "true", "sort": "name"]
        ),
        fixture(
            "beta_license_list",
            "/v1/betaLicenseAgreements",
            "/v1/betaTesters",
            ["limit": "25"],
            ["limit": "31", "filter[app]": "app-1"]
        ),
        fixture(
            "beta_testers_list",
            "/v1/betaTesters",
            "/v1/betaGroups",
            ["limit": "25"],
            ["limit": "31", "filter[apps]": "app-1", "filter[email]": "tester@example.com", "filter[betaGroups]": "group-1", "sort": "email"]
        ),
        fixture(
            "beta_testers_search",
            "/v1/betaTesters",
            "/v1/betaGroups",
            ["filter[email]": "tester@example.com", "limit": "25"],
            ["filter[email]": "tester@example.com", "filter[apps]": "app-1", "limit": "31"]
        ),
        fixture(
            "builds_get_beta_groups",
            "/v1/betaGroups",
            "/v1/builds",
            ["filter[builds]": "build-1", "limit": "50"],
            ["filter[builds]": "build-1", "limit": "31", "filter[id]": "group-1", "filter[isInternalGroup]": "true", "sort": "name"]
        ),
        fixture(
            "builds_list",
            "/v1/builds",
            "/v1/users",
            ["filter[app]": "app-1", "include": "app,buildBetaDetail,preReleaseVersion", "limit": "25", "sort": "-uploadedDate"],
            ["filter[app]": "app-1", "include": "app,buildBetaDetail,preReleaseVersion", "limit": "31", "sort": "version", "filter[processingState]": "VALID", "filter[version]": "42"]
        ),
        fixture(
            "metrics_list_build_diagnostics",
            "/v1/builds/build-1/diagnosticSignatures",
            "/v1/builds/build-2/diagnosticSignatures",
            ["limit": "25"],
            ["limit": "31", "filter[diagnosticType]": "DISK_WRITES"]
        ),
        fixture(
            "pre_release_list",
            "/v1/preReleaseVersions",
            "/v1/builds",
            ["limit": "25"],
            ["limit": "31", "filter[app]": "app-1", "filter[platform]": "IOS", "filter[version]": "1.0", "sort": "-version"]
        ),
        fixture(
            "pricing_list_price_points",
            "/v1/apps/app-1/appPricePoints",
            "/v1/apps/app-2/appPricePoints",
            ["include": "territory", "limit": "50"],
            ["include": "territory", "limit": "31", "filter[territory]": "USA"]
        ),
        fixture(
            "pricing_list_territory_availability",
            "/v2/appAvailabilities/availability-1/territoryAvailabilities",
            "/v2/appAvailabilities/availability-2/territoryAvailabilities",
            ["include": "territory", "limit": "50"],
            ["include": "territory", "limit": "31"]
        ),
        fixture(
            "pricing_list_territory_availabilities",
            "/v2/appAvailabilities/availability-1/territoryAvailabilities",
            "/v2/appAvailabilities/availability-2/territoryAvailabilities",
            ["include": "territory", "limit": "50"],
            ["include": "territory", "limit": "31"]
        ),
        fixture("provisioning_list_bundle_ids", "/v1/bundleIds", "/v1/devices", ["limit": "25"], ["limit": "31", "filter[platform]": "IOS", "filter[identifier]": "com.example.app", "sort": "name"]),
        fixture("provisioning_list_devices", "/v1/devices", "/v1/certificates", ["limit": "25"], ["limit": "31", "filter[platform]": "IOS", "filter[status]": "ENABLED", "filter[udid]": "device-1", "sort": "name"]),
        fixture("provisioning_list_certificates", "/v1/certificates", "/v1/profiles", ["limit": "25"], ["limit": "31", "filter[certificateType]": "IOS_DISTRIBUTION", "filter[id]": "certificate-1", "sort": "displayName"]),
        fixture("provisioning_list_profiles", "/v1/profiles", "/v1/certificates", ["limit": "25"], ["limit": "31", "filter[profileType]": "IOS_APP_STORE", "filter[profileState]": "ACTIVE", "sort": "name"]),
        fixture("provisioning_list_capabilities", "/v1/bundleIds/bundle-1/bundleIdCapabilities", "/v1/bundleIds/bundle-2/bundleIdCapabilities", ["limit": "25"], ["limit": "31"]),
        fixture(
            "reviews_list",
            "/v1/apps/app-1/customerReviews",
            "/v1/apps/app-2/customerReviews",
            ["limit": "100", "sort": "-createdDate"],
            ["limit": "31", "sort": "rating", "filter[rating]": "5", "filter[territory]": "USA", "include": "response", "exists[publishedResponse]": "true"]
        ),
        fixture(
            "reviews_list_for_version",
            "/v1/appStoreVersions/version-1/customerReviews",
            "/v1/appStoreVersions/version-2/customerReviews",
            ["limit": "100", "sort": "-createdDate"],
            ["limit": "31", "sort": "rating", "filter[rating]": "5", "filter[territory]": "USA", "include": "response", "exists[publishedResponse]": "true"]
        ),
        fixture(
            "reviews_summarizations",
            "/v1/apps/app-1/customerReviewSummarizations",
            "/v1/apps/app-2/customerReviewSummarizations",
            ["filter[platform]": "IOS", "limit": "25"],
            ["filter[platform]": "MAC_OS", "filter[territory]": "USA", "limit": "31"]
        ),
        fixture("users_list", "/v1/users", "/v1/userInvitations", ["limit": "25"], ["limit": "31", "filter[username]": "owner@example.com", "filter[roles]": "ADMIN", "include": "visibleApps", "limit[visibleApps]": "11", "sort": "username"]),
        fixture("users_list_invitations", "/v1/userInvitations", "/v1/users", ["limit": "25"], ["limit": "31", "filter[email]": "invitee@example.com", "filter[roles]": "DEVELOPER", "include": "visibleApps", "limit[visibleApps]": "11", "sort": "email"]),
        fixture("webhooks_list", "/v1/apps/app-1/webhooks", "/v1/apps/app-2/webhooks", ["limit": "25"], ["limit": "31", "include": "app"]),
        fixture(
            "webhooks_list_deliveries",
            "/v1/webhooks/webhook-1/deliveries",
            "/v1/webhooks/webhook-2/deliveries",
            ["limit": "25", "include": "event"],
            ["limit": "31", "filter[deliveryState]": "SUCCEEDED", "filter[createdDateGreaterThanOrEqualTo]": "2026-07-01T00:00:00Z", "filter[createdDateLessThan]": "2026-07-21T00:00:00Z"]
        )
    ]
}

private func fixture(
    _ tool: String,
    _ path: String,
    _ wrongPath: String,
    _ defaultQuery: [String: String],
    _ explicitQuery: [String: String]
) -> FilteredPaginationFixture {
    FilteredPaginationFixture(
        tool: tool,
        path: path,
        wrongPath: wrongPath,
        defaultQuery: defaultQuery,
        explicitQuery: explicitQuery
    )
}

private func paginationMatrixURL(
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

private func paginationMatrixURL(
    _ url: String,
    duplicate name: String,
    value: String
) -> String {
    guard var components = URLComponents(string: url) else {
        preconditionFailure("Unable to parse pagination fixture URL")
    }
    var items = components.queryItems ?? []
    items.append(URLQueryItem(name: name, value: value))
    components.queryItems = items
    return components.url?.absoluteString ?? "invalid"
}
