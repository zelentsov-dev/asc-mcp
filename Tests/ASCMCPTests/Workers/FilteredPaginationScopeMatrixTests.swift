import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Filtered Pagination Scope Matrix Tests")
struct FilteredPaginationScopeMatrixTests {
    @Test("all 33 filtered handlers preserve exact default and maximal explicit queries")
    func acceptsExactContinuations() async throws {
        let fixtures = filteredPaginationFixtures()
        #expect(fixtures.count == 33)
        #expect(fixtures.map(\.tool) == filteredPaginationToolNames)

        for fixture in fixtures {
            for variant in filteredPaginationVariants(for: fixture) {
                let firstPageTransport = TestHTTPTransport(
                    responses: filteredPaginationResponses(for: fixture, includePage: true)
                )
                let firstPageResult = try await invokeFilteredPaginationFixture(
                    fixture,
                    arguments: variant.arguments,
                    transport: firstPageTransport
                )

                #expect(firstPageResult.isError != true, "Expected first page for \(fixture.tool) [\(variant.name)]")
                let firstPageRequests = await firstPageTransport.recordedRequests()
                let firstPageRequest = try #require(
                    firstPageRequests.dropFirst(filteredPaginationRequestIndex(for: fixture)).first
                )
                #expect(firstPageRequest.url?.path == fixture.path)
                #expect(filteredPaginationQuery(firstPageRequest) == variant.query)

                var continuationQuery = variant.query
                continuationQuery["cursor"] = "next"
                var continuationArguments = variant.arguments
                continuationArguments["next_url"] = .string(
                    paginationMatrixURL(path: fixture.path, query: continuationQuery)
                )
                let continuationTransport = TestHTTPTransport(
                    responses: filteredPaginationResponses(for: fixture, includePage: true)
                )
                let continuationResult = try await invokeFilteredPaginationFixture(
                    fixture,
                    arguments: continuationArguments,
                    transport: continuationTransport
                )

                #expect(continuationResult.isError != true, "Expected continuation for \(fixture.tool) [\(variant.name)]")
                let continuationRequests = await continuationTransport.recordedRequests()
                let continuationRequest = try #require(
                    continuationRequests.dropFirst(filteredPaginationRequestIndex(for: fixture)).first
                )
                #expect(continuationRequest.url?.path == fixture.path)
                #expect(filteredPaginationQuery(continuationRequest) == continuationQuery)
            }
        }
    }

    @Test("all filtered handlers reject every missing or changed originating value")
    func rejectsOriginatingQueryDrift() async throws {
        for fixture in filteredPaginationFixtures() {
            for variant in filteredPaginationVariants(for: fixture) {
                for name in variant.query.keys {
                    var missing = variant.query
                    missing.removeValue(forKey: name)
                    missing["cursor"] = "next"
                    try await expectFilteredPaginationRejection(
                        fixture,
                        arguments: variant.arguments,
                        nextURL: paginationMatrixURL(path: fixture.path, query: missing),
                        receipt: "missing \(name) [\(variant.name)]"
                    )

                    var changed = variant.query
                    changed[name] = "drift"
                    changed["cursor"] = "next"
                    try await expectFilteredPaginationRejection(
                        fixture,
                        arguments: variant.arguments,
                        nextURL: paginationMatrixURL(path: fixture.path, query: changed),
                        receipt: "changed \(name) [\(variant.name)]"
                    )
                }
            }
        }
    }

    @Test("all filtered handlers reject missing empty and blank cursors")
    func rejectsInvalidCursors() async throws {
        for fixture in filteredPaginationFixtures() {
            for variant in filteredPaginationVariants(for: fixture) {
                for cursor in [String?.none, .some(""), .some(" ")] {
                    var query = variant.query
                    if let cursor {
                        query["cursor"] = cursor
                    }
                    try await expectFilteredPaginationRejection(
                        fixture,
                        arguments: variant.arguments,
                        nextURL: paginationMatrixURL(path: fixture.path, query: query),
                        receipt: "invalid cursor [\(variant.name)]"
                    )
                }
            }
        }
    }

    @Test("all filtered handlers reject injection duplicates wrong paths and foreign origins")
    func rejectsBoundaryViolations() async throws {
        for fixture in filteredPaginationFixtures() {
            for variant in filteredPaginationVariants(for: fixture) {
                var validQuery = variant.query
                validQuery["cursor"] = "next"

                var injectedQuery = validQuery
                injectedQuery["filter[unexpected]"] = "drift"
                let validURL = paginationMatrixURL(path: fixture.path, query: validQuery)
                let invalidURLs = [
                    paginationMatrixURL(path: fixture.path, query: injectedQuery),
                    paginationMatrixURL(validURL, duplicate: "cursor", value: "again"),
                    paginationMatrixURL(
                        validURL,
                        duplicate: variant.query.keys.sorted().first ?? "limit",
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
                    try await expectFilteredPaginationRejection(
                        fixture,
                        arguments: variant.arguments,
                        nextURL: invalidURL,
                        receipt: "boundary violation [\(variant.name)]"
                    )
                }
            }
        }
    }

    @Test("all filtered handlers reject malformed next_url values before the page request")
    func rejectsMalformedNextURLs() async throws {
        for fixture in filteredPaginationFixtures() {
            let variant = filteredPaginationVariants(for: fixture)[0]
            for invalidValue in [Value.string(""), .string(" "), .string("/relative"), .int(1)] {
                let transport = TestHTTPTransport(
                    responses: filteredPaginationResponses(for: fixture, includePage: false)
                )
                var arguments = variant.arguments
                arguments["next_url"] = invalidValue
                let result = try await invokeFilteredPaginationFixture(
                    fixture,
                    arguments: arguments,
                    transport: transport
                )

                #expect(result.isError == true, "Expected malformed next_url rejection for \(fixture.tool)")
                #expect(await transport.requestCount() == filteredPaginationRequestIndex(for: fixture))
            }
        }
    }

    @Test("all 49 public manifest fields publish the strict continuation contract")
    func manifestDescribesStrictContinuationContract() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let toolNames = filteredPaginationToolNames + pathOnlyManifestPaginationToolNames + completeManifestPaginationToolNames
        #expect(toolNames.count == 49)
        #expect(Set(toolNames).count == 49)

        for toolName in toolNames {
            let mapping = try #require(manifest.mapping(for: toolName))
            let nextURL = try #require(mapping.fields.first { $0.toolField == "next_url" })
            #expect(nextURL.localRole == strictContinuationLocalRole, "Unexpected next_url contract for \(toolName)")
        }
    }

    @Test("all 44 path and filtered tool schemas explain the strict continuation contract")
    func toolSchemasDescribeStrictContinuationContract() async throws {
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: TestHTTPTransport(responses: []),
            maxRetries: 1
        )
        let tools = await pathAndFilteredPaginationTools(client: client)
        let toolNames = filteredPaginationToolNames + pathOnlyManifestPaginationToolNames

        for toolName in toolNames {
            let tool = try #require(tools.first { $0.name == toolName })
            let root = try #require(tool.inputSchema.objectValue)
            let properties = try #require(root["properties"]?.objectValue)
            let nextURL = try #require(properties["next_url"]?.objectValue)
            #expect(
                nextURL["description"]?.stringValue == strictContinuationToolDescription,
                "Unexpected next_url schema description for \(toolName)"
            )
        }
    }
}

private enum FilteredPaginationWorker {
    case accessibility
    case analytics
    case appEvents
    case appInfo
    case betaFeedback
    case betaGroups
    case betaLicense
    case betaTesters
    case buildBetaDetails
    case builds
    case metrics
    case preRelease
    case pricing
    case provisioning
    case reviews
    case users
    case webhooks
}

private struct FilteredPaginationVariant {
    let name: String
    let arguments: [String: Value]
    let query: [String: String]
}

private struct FilteredPaginationFixture {
    let worker: FilteredPaginationWorker
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
            ["limit": "31", "filter[deviceFamily]": "IPHONE,IPAD", "filter[state]": "DRAFT,PUBLISHED", "fields[accessibilityDeclarations]": "deviceFamily,state"]
        ),
        fixture(
            "analytics_list_report_requests",
            "/v1/apps/app-1/analyticsReportRequests",
            "/v1/apps/app-2/analyticsReportRequests",
            ["limit": "25"],
            ["limit": "31", "filter[accessType]": "ONGOING,ONE_TIME_SNAPSHOT", "include": "reports", "limit[reports]": "11"]
        ),
        fixture(
            "analytics_list_reports",
            "/v1/analyticsReportRequests/request-1/reports",
            "/v1/analyticsReportRequests/request-2/reports",
            ["limit": "25"],
            ["limit": "31", "filter[name]": "App Sessions,Sales", "filter[category]": "APP_USAGE,COMMERCE"]
        ),
        fixture(
            "analytics_list_instances",
            "/v1/analyticsReports/report-1/instances",
            "/v1/analyticsReports/report-2/instances",
            ["limit": "25"],
            ["limit": "31", "filter[granularity]": "DAILY,WEEKLY", "filter[processingDate]": "2026-07-19,2026-07-20"]
        ),
        fixture(
            "app_events_list",
            "/v1/apps/app-1/appEvents",
            "/v1/apps/app-2/appEvents",
            ["limit": "25"],
            ["limit": "31", "filter[eventState]": "DRAFT,PUBLISHED", "filter[id]": "event-1,event-2", "include": "localizations", "limit[localizations]": "11"]
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
            ["limit": "31", "include": "app,appInfoLocalizations,primaryCategory", "limit[appInfoLocalizations]": "11"]
        ),
        fixture(
            "app_info_list_localizations",
            "/v1/appInfos/info-1/appInfoLocalizations",
            "/v1/appInfos/info-2/appInfoLocalizations",
            ["limit": "25"],
            ["limit": "31", "filter[locale]": "en-US,fr-FR", "include": "appInfo"]
        ),
        fixture(
            "beta_feedback_list_crashes",
            "/v1/apps/app-1/betaFeedbackCrashSubmissions",
            "/v1/apps/app-2/betaFeedbackCrashSubmissions",
            ["limit": "25", "sort": "-createdDate"],
            [
                "limit": "31",
                "sort": "createdDate",
                "filter[build]": "build-1,build-2",
                "filter[build.preReleaseVersion]": "pre-release-1",
                "filter[tester]": "tester-1",
                "filter[deviceModel]": "iPhone 15 Pro",
                "filter[osVersion]": "18.0",
                "filter[appPlatform]": "IOS,MAC_OS",
                "filter[devicePlatform]": "IOS",
                "include": "build,tester"
            ]
        ),
        fixture(
            "beta_feedback_list_screenshots",
            "/v1/apps/app-1/betaFeedbackScreenshotSubmissions",
            "/v1/apps/app-2/betaFeedbackScreenshotSubmissions",
            ["limit": "25", "sort": "-createdDate"],
            [
                "limit": "31",
                "sort": "createdDate",
                "filter[build]": "build-1,build-2",
                "filter[build.preReleaseVersion]": "pre-release-1",
                "filter[tester]": "tester-1",
                "filter[deviceModel]": "iPhone 15 Pro",
                "filter[osVersion]": "18.0",
                "filter[appPlatform]": "IOS,MAC_OS",
                "filter[devicePlatform]": "IOS",
                "include": "build,tester"
            ]
        ),
        fixture(
            "beta_groups_list",
            "/v1/betaGroups",
            "/v1/users",
            ["filter[app]": "app-1", "limit": "25"],
            [
                "filter[app]": "app-1",
                "limit": "31",
                "filter[name]": "Internal,External",
                "filter[builds]": "build-1,build-2",
                "filter[id]": "group-1,group-2",
                "filter[publicLink]": "https://testflight.apple.com/join/example",
                "filter[isInternalGroup]": "true",
                "filter[publicLinkEnabled]": "true",
                "filter[publicLinkLimitEnabled]": "false",
                "sort": "name"
            ]
        ),
        fixture(
            "beta_license_list",
            "/v1/betaLicenseAgreements",
            "/v1/betaTesters",
            ["limit": "25"],
            ["limit": "31", "filter[app]": "app-1,app-2"]
        ),
        fixture(
            "beta_testers_list",
            "/v1/betaTesters",
            "/v1/betaGroups",
            ["limit": "25"],
            [
                "limit": "31",
                "filter[apps]": "app-1",
                "filter[firstName]": "Ada,Grace",
                "filter[lastName]": "Lovelace,Hopper",
                "filter[email]": "tester@example.com,second@example.com",
                "filter[inviteType]": "EMAIL,PUBLIC_LINK",
                "filter[betaGroups]": "group-1,group-2",
                "filter[builds]": "build-1,build-2",
                "filter[id]": "tester-1,tester-2",
                "sort": "email"
            ]
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
            [
                "filter[builds]": "build-1",
                "limit": "31",
                "filter[id]": "group-1,group-2",
                "filter[name]": "Internal,External",
                "filter[publicLink]": "https://testflight.apple.com/join/example",
                "filter[isInternalGroup]": "true",
                "filter[publicLinkEnabled]": "true",
                "filter[publicLinkLimitEnabled]": "false",
                "sort": "name"
            ]
        ),
        fixture(
            "builds_list",
            "/v1/builds",
            "/v1/users",
            ["filter[app]": "app-1", "include": "app,buildBetaDetail,preReleaseVersion", "limit": "25", "sort": "-uploadedDate"],
            [
                "filter[app]": "app-1",
                "include": "app,buildBetaDetail,preReleaseVersion",
                "limit": "31",
                "sort": "version",
                "filter[version]": "42,43",
                "filter[processingState]": "VALID,PROCESSING",
                "filter[expired]": "false",
                "filter[appStoreVersion]": "version-1,version-2",
                "filter[betaAppReviewSubmission.betaReviewState]": "APPROVED,IN_REVIEW",
                "filter[betaGroups]": "group-1,group-2",
                "filter[buildAudienceType]": "INTERNAL_ONLY,APP_STORE_ELIGIBLE",
                "filter[id]": "build-1,build-2",
                "filter[preReleaseVersion.platform]": "IOS,MAC_OS",
                "filter[preReleaseVersion.version]": "2.0,2.1",
                "filter[preReleaseVersion]": "pre-release-1,pre-release-2",
                "filter[usesNonExemptEncryption]": "true",
                "exists[usesNonExemptEncryption]": "true"
            ]
        ),
        fixture(
            "metrics_build_diagnostics",
            "/v1/builds/build-1/diagnosticSignatures",
            "/v1/builds/build-2/diagnosticSignatures",
            ["limit": "25"],
            ["limit": "31", "filter[diagnosticType]": "DISK_WRITES,HANGS,LAUNCHES"]
        ),
        fixture(
            "pre_release_list",
            "/v1/preReleaseVersions",
            "/v1/builds",
            ["limit": "25"],
            [
                "limit": "31",
                "filter[app]": "app-1",
                "filter[platform]": "IOS,MAC_OS",
                "filter[version]": "1.0,2.0",
                "filter[builds.buildAudienceType]": "INTERNAL_ONLY,APP_STORE_ELIGIBLE",
                "filter[builds.expired]": "false",
                "filter[builds.processingState]": "VALID,PROCESSING",
                "filter[builds.version]": "42,43",
                "filter[builds]": "build-1,build-2",
                "sort": "-version"
            ]
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
        fixture("provisioning_list_bundle_ids", "/v1/bundleIds", "/v1/devices", ["limit": "25"], ["limit": "31", "filter[platform]": "IOS,MAC_OS", "filter[identifier]": "com.example.app,com.example.other", "filter[name]": "Example,Other", "filter[seedId]": "seed-1,seed-2", "filter[id]": "bundle-1,bundle-2", "sort": "name,-identifier"]),
        fixture("provisioning_list_devices", "/v1/devices", "/v1/certificates", ["limit": "25"], ["limit": "31", "filter[platform]": "IOS,MAC_OS", "filter[status]": "ENABLED,DISABLED", "filter[name]": "Phone,Tablet", "filter[udid]": "udid-1,udid-2", "filter[id]": "device-1,device-2", "sort": "name,-udid"]),
        fixture("provisioning_list_certificates", "/v1/certificates", "/v1/profiles", ["limit": "25"], ["limit": "31", "filter[certificateType]": "IOS_DISTRIBUTION,DISTRIBUTION", "filter[displayName]": "Distribution One,Distribution Two", "filter[serialNumber]": "serial-1,serial-2", "filter[id]": "certificate-1,certificate-2", "sort": "displayName,-serialNumber"]),
        fixture("provisioning_list_profiles", "/v1/profiles", "/v1/certificates", ["limit": "25"], ["limit": "31", "filter[profileType]": "IOS_APP_STORE,MAC_APP_STORE", "filter[profileState]": "ACTIVE,INVALID", "filter[name]": "Profile One,Profile Two", "filter[id]": "profile-1,profile-2", "sort": "name,-id"]),
        fixture("provisioning_list_capabilities", "/v1/bundleIds/bundle-1/bundleIdCapabilities", "/v1/bundleIds/bundle-2/bundleIdCapabilities", ["limit": "25"], ["limit": "31"]),
        fixture(
            "reviews_list",
            "/v1/apps/app-1/customerReviews",
            "/v1/apps/app-2/customerReviews",
            ["limit": "100", "sort": "-createdDate"],
            ["limit": "31", "sort": "rating,-createdDate", "filter[rating]": "4,5", "filter[territory]": "USA,CAN", "include": "response", "exists[publishedResponse]": "true"]
        ),
        fixture(
            "reviews_list_for_version",
            "/v1/appStoreVersions/version-1/customerReviews",
            "/v1/appStoreVersions/version-2/customerReviews",
            ["limit": "100", "sort": "-createdDate"],
            ["limit": "31", "sort": "rating,-createdDate", "filter[rating]": "4,5", "filter[territory]": "USA,CAN", "include": "response", "exists[publishedResponse]": "true"]
        ),
        fixture(
            "reviews_summarizations",
            "/v1/apps/app-1/customerReviewSummarizations",
            "/v1/apps/app-2/customerReviewSummarizations",
            ["filter[platform]": "IOS", "limit": "25"],
            ["filter[platform]": "MAC_OS", "filter[territory]": "USA", "limit": "31"]
        ),
        fixture("users_list", "/v1/users", "/v1/userInvitations", ["limit": "25"], ["limit": "31", "filter[username]": "owner@example.com", "filter[roles]": "ADMIN,DEVELOPER", "filter[visibleApps]": "app-1,app-2", "include": "visibleApps", "limit[visibleApps]": "11", "sort": "username,-lastName"]),
        fixture("users_list_invitations", "/v1/userInvitations", "/v1/users", ["limit": "25"], ["limit": "31", "filter[email]": "invitee@example.com", "filter[roles]": "DEVELOPER,APP_MANAGER", "filter[visibleApps]": "app-1,app-2", "include": "visibleApps", "limit[visibleApps]": "11", "sort": "email,-lastName"]),
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
        worker: filteredPaginationWorker(for: tool),
        tool: tool,
        path: path,
        wrongPath: wrongPath,
        defaultQuery: defaultQuery,
        explicitQuery: explicitQuery
    )
}

private let filteredPaginationToolNames = [
    "accessibility_list",
    "analytics_list_report_requests",
    "analytics_list_reports",
    "analytics_list_instances",
    "app_events_list",
    "app_events_list_localizations",
    "app_info_list",
    "app_info_list_localizations",
    "beta_feedback_list_crashes",
    "beta_feedback_list_screenshots",
    "beta_groups_list",
    "beta_license_list",
    "beta_testers_list",
    "beta_testers_search",
    "builds_get_beta_groups",
    "builds_list",
    "metrics_build_diagnostics",
    "pre_release_list",
    "pricing_list_price_points",
    "pricing_list_territory_availability",
    "pricing_list_territory_availabilities",
    "provisioning_list_bundle_ids",
    "provisioning_list_devices",
    "provisioning_list_certificates",
    "provisioning_list_profiles",
    "provisioning_list_capabilities",
    "reviews_list",
    "reviews_list_for_version",
    "reviews_summarizations",
    "users_list",
    "users_list_invitations",
    "webhooks_list",
    "webhooks_list_deliveries"
]

private let pathOnlyManifestPaginationToolNames = [
    "accessibility_list_relationships",
    "analytics_list_segments",
    "beta_groups_list_testers",
    "beta_testers_list_apps",
    "builds_list_beta_localizations",
    "builds_get_beta_testers",
    "builds_list_individual_testers",
    "pre_release_list_builds",
    "pricing_list_territories",
    "sandbox_list",
    "users_list_visible_apps"
]

private let completeManifestPaginationToolNames = [
    "app_versions_list",
    "apps_list",
    "apps_list_localizations",
    "apps_list_versions",
    "review_attachments_list"
]

private let strictContinuationLocalRole = "Strict Apple continuation URL for this exact collection. The caller must repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated before sending the continuation request."

private let strictContinuationToolDescription = "Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated."

private func pathAndFilteredPaginationTools(client: HTTPClient) async -> [Tool] {
    var tools: [Tool] = []
    tools += await AccessibilityWorker(httpClient: client).getTools()
    tools += await AnalyticsWorker(httpClient: client).getTools()
    tools += await AppEventsWorker(httpClient: client).getTools()
    tools += await AppInfoWorker(httpClient: client).getTools()
    tools += await BetaFeedbackWorker(httpClient: client).getTools()
    tools += await BetaGroupsWorker(httpClient: client).getTools()
    tools += await BetaLicenseAgreementsWorker(httpClient: client).getTools()
    tools += await BetaTestersWorker(httpClient: client).getTools()
    tools += await BuildBetaDetailsWorker(httpClient: client).getTools()
    tools += await BuildsWorker(httpClient: client).getTools()
    tools += await MetricsWorker(httpClient: client).getTools()
    tools += await PreReleaseVersionsWorker(httpClient: client).getTools()
    tools += await PricingWorker(httpClient: client).getTools()
    tools += await ProvisioningWorker(httpClient: client).getTools()
    tools += await ReviewsWorker(httpClient: client).getTools()
    tools += await SandboxTestersWorker(httpClient: client).getTools()
    tools += await UsersWorker(httpClient: client).getTools()
    tools += await WebhooksWorker(httpClient: client).getTools()
    return tools
}

private func filteredPaginationWorker(for tool: String) -> FilteredPaginationWorker {
    switch tool {
    case "accessibility_list": .accessibility
    case "analytics_list_report_requests", "analytics_list_reports", "analytics_list_instances": .analytics
    case "app_events_list", "app_events_list_localizations": .appEvents
    case "app_info_list", "app_info_list_localizations": .appInfo
    case "beta_feedback_list_crashes", "beta_feedback_list_screenshots": .betaFeedback
    case "beta_groups_list": .betaGroups
    case "beta_license_list": .betaLicense
    case "beta_testers_list", "beta_testers_search": .betaTesters
    case "builds_get_beta_groups": .buildBetaDetails
    case "builds_list": .builds
    case "metrics_build_diagnostics": .metrics
    case "pre_release_list": .preRelease
    case "pricing_list_price_points", "pricing_list_territory_availability", "pricing_list_territory_availabilities": .pricing
    case "provisioning_list_bundle_ids", "provisioning_list_devices", "provisioning_list_certificates", "provisioning_list_profiles", "provisioning_list_capabilities": .provisioning
    case "reviews_list", "reviews_list_for_version", "reviews_summarizations": .reviews
    case "users_list", "users_list_invitations": .users
    case "webhooks_list", "webhooks_list_deliveries": .webhooks
    default: preconditionFailure("Missing filtered pagination worker for \(tool)")
    }
}

private func filteredPaginationVariants(
    for fixture: FilteredPaginationFixture
) -> [FilteredPaginationVariant] {
    [
        FilteredPaginationVariant(
            name: "effective defaults",
            arguments: filteredPaginationDefaultArguments(for: fixture.tool),
            query: fixture.defaultQuery
        ),
        FilteredPaginationVariant(
            name: "maximal explicit controls",
            arguments: filteredPaginationExplicitArguments(for: fixture.tool),
            query: fixture.explicitQuery
        )
    ]
}

private func filteredPaginationDefaultArguments(for tool: String) -> [String: Value] {
    switch tool {
    case "accessibility_list", "analytics_list_report_requests", "app_events_list", "app_info_list",
         "beta_feedback_list_crashes", "beta_feedback_list_screenshots", "beta_groups_list",
         "builds_list", "pricing_list_price_points", "pricing_list_territory_availability",
         "reviews_list", "reviews_summarizations", "webhooks_list":
        return ["app_id": .string("app-1")]
    case "analytics_list_reports":
        return ["request_id": .string("request-1")]
    case "analytics_list_instances":
        return ["report_id": .string("report-1")]
    case "app_events_list_localizations":
        return ["event_id": .string("event-1")]
    case "app_info_list_localizations":
        return ["info_id": .string("info-1")]
    case "beta_testers_search":
        return ["email": .string("tester@example.com")]
    case "builds_get_beta_groups", "metrics_build_diagnostics":
        return ["build_id": .string("build-1")]
    case "pricing_list_territory_availabilities":
        return ["availability_id": .string("availability-1")]
    case "provisioning_list_capabilities":
        return ["bundle_id_resource_id": .string("bundle-1")]
    case "reviews_list_for_version":
        return ["version_id": .string("version-1")]
    case "webhooks_list_deliveries":
        return ["webhook_id": .string("webhook-1")]
    case "beta_license_list", "beta_testers_list", "pre_release_list",
         "provisioning_list_bundle_ids", "provisioning_list_devices",
         "provisioning_list_certificates", "provisioning_list_profiles",
         "users_list", "users_list_invitations":
        return [:]
    default:
        preconditionFailure("Missing default arguments for \(tool)")
    }
}

private func filteredPaginationExplicitArguments(for tool: String) -> [String: Value] {
    switch tool {
    case "accessibility_list":
        return [
            "app_id": .string("app-1"),
            "device_family": .array([.string("IPHONE"), .string("IPAD")]),
            "state": .array([.string("DRAFT"), .string("PUBLISHED")]),
            "fields": .array([.string("deviceFamily"), .string("state")]),
            "limit": .int(31)
        ]
    case "analytics_list_report_requests":
        return [
            "app_id": .string("app-1"),
            "limit": .int(31),
            "access_types": .array([.string("ONGOING"), .string("ONE_TIME_SNAPSHOT")]),
            "include_reports": .bool(true),
            "limit_reports": .int(11)
        ]
    case "analytics_list_reports":
        return [
            "request_id": .string("request-1"),
            "limit": .int(31),
            "names": .array([.string("App Sessions"), .string("Sales")]),
            "categories": .array([.string("APP_USAGE"), .string("COMMERCE")])
        ]
    case "analytics_list_instances":
        return [
            "report_id": .string("report-1"),
            "limit": .int(31),
            "granularities": .array([.string("DAILY"), .string("WEEKLY")]),
            "processing_dates": .array([.string("2026-07-19"), .string("2026-07-20")])
        ]
    case "app_events_list":
        return [
            "app_id": .string("app-1"),
            "event_states": .array([.string("DRAFT"), .string("PUBLISHED")]),
            "event_ids": .array([.string("event-1"), .string("event-2")]),
            "include": .array([.string("localizations")]),
            "limit": .int(31),
            "localizations_limit": .int(11)
        ]
    case "app_events_list_localizations":
        return [
            "event_id": .string("event-1"),
            "include": .array([
                .string("appEvent"),
                .string("appEventScreenshots"),
                .string("appEventVideoClips")
            ]),
            "limit": .int(31),
            "screenshots_limit": .int(11),
            "video_clips_limit": .int(12)
        ]
    case "app_info_list":
        return [
            "app_id": .string("app-1"),
            "include": .array([.string("app"), .string("appInfoLocalizations"), .string("primaryCategory")]),
            "limit": .int(31),
            "localizations_limit": .int(11)
        ]
    case "app_info_list_localizations":
        return [
            "info_id": .string("info-1"),
            "locale": .array([.string("en-US"), .string("fr-FR")]),
            "include": .array([.string("appInfo")]),
            "limit": .int(31)
        ]
    case "beta_feedback_list_crashes", "beta_feedback_list_screenshots":
        return [
            "app_id": .string("app-1"),
            "build_id": .array([.string("build-1"), .string("build-2")]),
            "pre_release_version_id": .array([.string("pre-release-1")]),
            "tester_id": .array([.string("tester-1")]),
            "device_model": .array([.string("iPhone 15 Pro")]),
            "os_version": .array([.string("18.0")]),
            "app_platform": .array([.string("IOS"), .string("MAC_OS")]),
            "device_platform": .array([.string("IOS")]),
            "sort": .array([.string("createdDate")]),
            "include": .array([.string("build"), .string("tester")]),
            "include_related": .bool(true),
            "include_pii": .bool(true),
            "limit": .int(31)
        ]
    case "beta_groups_list":
        return [
            "app_id": .string("app-1"),
            "limit": .int(31),
            "is_internal": .bool(true),
            "name": .array([.string("Internal"), .string("External")]),
            "build_ids": .array([.string("build-1"), .string("build-2")]),
            "group_ids": .array([.string("group-1"), .string("group-2")]),
            "public_link": .array([.string("https://testflight.apple.com/join/example")]),
            "public_link_enabled": .bool(true),
            "public_link_limit_enabled": .bool(false),
            "sort": .string("name")
        ]
    case "beta_license_list":
        return [
            "app_id": .array([.string("app-1"), .string("app-2")]),
            "limit": .int(31)
        ]
    case "beta_testers_list":
        return [
            "app_id": .string("app-1"),
            "first_name": .array([.string("Ada"), .string("Grace")]),
            "last_name": .array([.string("Lovelace"), .string("Hopper")]),
            "email": .array([.string("tester@example.com"), .string("second@example.com")]),
            "invite_type": .array([.string("EMAIL"), .string("PUBLIC_LINK")]),
            "group_ids": .array([.string("group-1"), .string("group-2")]),
            "build_ids": .array([.string("build-1"), .string("build-2")]),
            "tester_ids": .array([.string("tester-1"), .string("tester-2")]),
            "sort": .string("email"),
            "limit": .int(31)
        ]
    case "beta_testers_search":
        return [
            "email": .string("tester@example.com"),
            "app_id": .string("app-1"),
            "limit": .int(31)
        ]
    case "builds_get_beta_groups":
        return [
            "build_id": .string("build-1"),
            "limit": .int(31),
            "group_ids": .array([.string("group-1"), .string("group-2")]),
            "name": .array([.string("Internal"), .string("External")]),
            "is_internal": .bool(true),
            "public_link_enabled": .bool(true),
            "public_link_limit_enabled": .bool(false),
            "public_link": .array([.string("https://testflight.apple.com/join/example")]),
            "sort": .string("name")
        ]
    case "builds_list":
        return [
            "app_id": .string("app-1"),
            "version": .array([.string("42"), .string("43")]),
            "processing_state": .array([.string("VALID"), .string("PROCESSING")]),
            "expired": .bool(false),
            "app_store_version_ids": .array([.string("version-1"), .string("version-2")]),
            "beta_review_states": .array([.string("APPROVED"), .string("IN_REVIEW")]),
            "beta_group_ids": .array([.string("group-1"), .string("group-2")]),
            "build_audience_types": .array([.string("INTERNAL_ONLY"), .string("APP_STORE_ELIGIBLE")]),
            "build_ids": .array([.string("build-1"), .string("build-2")]),
            "pre_release_platforms": .array([.string("IOS"), .string("MAC_OS")]),
            "pre_release_versions": .array([.string("2.0"), .string("2.1")]),
            "pre_release_version_ids": .array([.string("pre-release-1"), .string("pre-release-2")]),
            "uses_non_exempt_encryption": .bool(true),
            "uses_non_exempt_encryption_set": .bool(true),
            "limit": .int(31),
            "sort": .string("version")
        ]
    case "metrics_build_diagnostics":
        return [
            "build_id": .string("build-1"),
            "diagnostic_type": .array([.string("DISK_WRITES"), .string("HANGS"), .string("LAUNCHES")]),
            "limit": .int(31)
        ]
    case "pre_release_list":
        return [
            "app_id": .string("app-1"),
            "platform": .array([.string("IOS"), .string("MAC_OS")]),
            "version": .array([.string("1.0"), .string("2.0")]),
            "build_audience_types": .array([.string("INTERNAL_ONLY"), .string("APP_STORE_ELIGIBLE")]),
            "build_expired": .bool(false),
            "build_processing_states": .array([.string("VALID"), .string("PROCESSING")]),
            "build_versions": .array([.string("42"), .string("43")]),
            "build_ids": .array([.string("build-1"), .string("build-2")]),
            "sort": .string("-version"),
            "limit": .int(31)
        ]
    case "pricing_list_price_points":
        return ["app_id": .string("app-1"), "territory_id": .string("USA"), "limit": .int(31)]
    case "pricing_list_territory_availability":
        return ["app_id": .string("app-1"), "limit": .int(31)]
    case "pricing_list_territory_availabilities":
        return ["availability_id": .string("availability-1"), "limit": .int(31)]
    case "provisioning_list_bundle_ids":
        return [
            "limit": .int(31),
            "filter_platform": .string("IOS,MAC_OS"),
            "filter_identifier": .string("com.example.app,com.example.other"),
            "filter_name": .string("Example,Other"),
            "filter_seed_id": .string("seed-1,seed-2"),
            "filter_id": .string("bundle-1,bundle-2"),
            "sort": .string("name,-identifier")
        ]
    case "provisioning_list_devices":
        return [
            "limit": .int(31),
            "filter_platform": .string("IOS,MAC_OS"),
            "filter_status": .string("ENABLED,DISABLED"),
            "filter_name": .string("Phone,Tablet"),
            "filter_udid": .string("udid-1,udid-2"),
            "filter_id": .string("device-1,device-2"),
            "sort": .string("name,-udid")
        ]
    case "provisioning_list_certificates":
        return [
            "limit": .int(31),
            "filter_type": .string("IOS_DISTRIBUTION,DISTRIBUTION"),
            "filter_display_name": .string("Distribution One,Distribution Two"),
            "filter_serial_number": .string("serial-1,serial-2"),
            "filter_id": .string("certificate-1,certificate-2"),
            "sort": .string("displayName,-serialNumber")
        ]
    case "provisioning_list_profiles":
        return [
            "limit": .int(31),
            "filter_profile_type": .string("IOS_APP_STORE,MAC_APP_STORE"),
            "filter_profile_state": .string("ACTIVE,INVALID"),
            "filter_name": .string("Profile One,Profile Two"),
            "filter_id": .string("profile-1,profile-2"),
            "sort": .string("name,-id")
        ]
    case "provisioning_list_capabilities":
        return ["bundle_id_resource_id": .string("bundle-1"), "limit": .int(31)]
    case "reviews_list":
        return reviewPaginationArguments(parent: ("app_id", "app-1"))
    case "reviews_list_for_version":
        return reviewPaginationArguments(parent: ("version_id", "version-1"))
    case "reviews_summarizations":
        return [
            "app_id": .string("app-1"),
            "platform": .string("MAC_OS"),
            "territory_id": .string("USA"),
            "limit": .int(31)
        ]
    case "users_list":
        return [
            "limit": .int(31),
            "filter_username": .string("owner@example.com"),
            "filter_roles": .array([.string("ADMIN"), .string("DEVELOPER")]),
            "filter_visible_apps": .array([.string("app-1"), .string("app-2")]),
            "sort": .array([.string("username"), .string("-lastName")]),
            "include": .array([.string("visibleApps")]),
            "limit_visible_apps": .int(11)
        ]
    case "users_list_invitations":
        return [
            "limit": .int(31),
            "filter_email": .string("invitee@example.com"),
            "filter_roles": .array([.string("DEVELOPER"), .string("APP_MANAGER")]),
            "filter_visible_apps": .array([.string("app-1"), .string("app-2")]),
            "sort": .array([.string("email"), .string("-lastName")]),
            "include": .array([.string("visibleApps")]),
            "limit_visible_apps": .int(11)
        ]
    case "webhooks_list":
        return ["app_id": .string("app-1"), "limit": .int(31), "include_app": .bool(true)]
    case "webhooks_list_deliveries":
        return [
            "webhook_id": .string("webhook-1"),
            "delivery_state": .string("SUCCEEDED"),
            "created_after": .string("2026-07-01T00:00:00Z"),
            "created_before": .string("2026-07-21T00:00:00Z"),
            "include_event": .bool(false),
            "limit": .int(31)
        ]
    default:
        preconditionFailure("Missing explicit arguments for \(tool)")
    }
}

private func reviewPaginationArguments(parent: (String, String)) -> [String: Value] {
    [
        parent.0: .string(parent.1),
        "limit": .int(31),
        "ratings": .array([.int(4), .int(5)]),
        "territories": .array([.string("USA"), .string("CAN")]),
        "sort": .array([.string("rating"), .string("-createdDate")]),
        "include_response": .bool(true),
        "has_published_response": .bool(true)
    ]
}

private func invokeFilteredPaginationFixture(
    _ fixture: FilteredPaginationFixture,
    arguments: [String: Value],
    transport: TestHTTPTransport
) async throws -> CallTool.Result {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    let parameters = CallTool.Parameters(name: fixture.tool, arguments: arguments)

    switch fixture.worker {
    case .accessibility:
        return try await AccessibilityWorker(httpClient: client).handleTool(parameters)
    case .analytics:
        return try await AnalyticsWorker(httpClient: client).handleTool(parameters)
    case .appEvents:
        return try await AppEventsWorker(httpClient: client).handleTool(parameters)
    case .appInfo:
        return try await AppInfoWorker(httpClient: client).handleTool(parameters)
    case .betaFeedback:
        return try await BetaFeedbackWorker(httpClient: client).handleTool(parameters)
    case .betaGroups:
        return try await BetaGroupsWorker(httpClient: client).handleTool(parameters)
    case .betaLicense:
        return try await BetaLicenseAgreementsWorker(httpClient: client).handleTool(parameters)
    case .betaTesters:
        return try await BetaTestersWorker(httpClient: client).handleTool(parameters)
    case .buildBetaDetails:
        return try await BuildBetaDetailsWorker(httpClient: client).handleTool(parameters)
    case .builds:
        return try await BuildsWorker(httpClient: client).handleTool(parameters)
    case .metrics:
        return try await MetricsWorker(httpClient: client).handleTool(parameters)
    case .preRelease:
        return try await PreReleaseVersionsWorker(httpClient: client).handleTool(parameters)
    case .pricing:
        return try await PricingWorker(httpClient: client).handleTool(parameters)
    case .provisioning:
        return try await ProvisioningWorker(httpClient: client).handleTool(parameters)
    case .reviews:
        return try await ReviewsWorker(httpClient: client).handleTool(parameters)
    case .users:
        return try await UsersWorker(httpClient: client).handleTool(parameters)
    case .webhooks:
        return try await WebhooksWorker(httpClient: client).handleTool(parameters)
    }
}

private func filteredPaginationResponses(
    for fixture: FilteredPaginationFixture,
    includePage: Bool
) -> [TestHTTPTransport.Response] {
    var responses: [TestHTTPTransport.Response] = []
    if fixture.tool == "pricing_list_territory_availability" {
        responses.append(.init(
            statusCode: 200,
            body: #"{"data":{"type":"appAvailabilities","id":"availability-1"}}"#
        ))
    }
    if includePage {
        responses.append(.init(statusCode: 200, body: #"{"data":[]}"#))
    }
    return responses
}

private func filteredPaginationRequestIndex(for fixture: FilteredPaginationFixture) -> Int {
    fixture.tool == "pricing_list_territory_availability" ? 1 : 0
}

private func expectFilteredPaginationRejection(
    _ fixture: FilteredPaginationFixture,
    arguments: [String: Value],
    nextURL: String,
    receipt: String
) async throws {
    let transport = TestHTTPTransport(
        responses: filteredPaginationResponses(for: fixture, includePage: false)
    )
    var invocationArguments = arguments
    invocationArguments["next_url"] = .string(nextURL)
    let result = try await invokeFilteredPaginationFixture(
        fixture,
        arguments: invocationArguments,
        transport: transport
    )

    #expect(result.isError == true, "Expected \(receipt) rejection for \(fixture.tool)")
    #expect(await transport.requestCount() == filteredPaginationRequestIndex(for: fixture))
}

private func filteredPaginationQuery(_ request: URLRequest) -> [String: String] {
    let items = request.url.flatMap {
        URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems
    } ?? []
    return Dictionary(uniqueKeysWithValues: items.compactMap { item in
        item.value.map { (item.name, $0) }
    })
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

private extension Value {
    var objectValue: [String: Value]? {
        guard case .object(let object) = self else {
            return nil
        }
        return object
    }
}
