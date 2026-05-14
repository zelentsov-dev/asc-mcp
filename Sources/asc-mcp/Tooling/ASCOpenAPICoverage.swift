import Foundation

struct ASCOpenAPICoverageRule: Sendable, Equatable {
    let domain: String
    let priority: ASCCoveragePriority
    let status: ASCCoverageStatus
    let pathPrefixes: [String]
    let workerKeys: [String]
    let toolPrefixes: [String]
    let notes: String
}

struct ASCOpenAPIDomainCoverage: Sendable, Equatable {
    let rule: ASCOpenAPICoverageRule
    let paths: [String]
    let operations: [ASCOpenAPIOperation]

    var pathCount: Int {
        paths.count
    }

    var operationCount: Int {
        operations.count
    }
}

struct ASCOpenAPICoverageReport: Sendable, Equatable {
    let spec: ASCOpenAPISpec
    let generatedAt: String
    let domains: [ASCOpenAPIDomainCoverage]
    let unclassifiedPaths: [String]

    var coveredPathCount: Int {
        Set(domains.flatMap(\.paths)).count
    }

    var unclassifiedPathCount: Int {
        unclassifiedPaths.count
    }

    var highPriorityAppleGaps: [ASCOpenAPIDomainCoverage] {
        domains
            .filter { $0.rule.priority <= .p1 && $0.rule.status != .covered && !$0.paths.isEmpty }
            .sorted(by: ASCOpenAPIDomainCoverage.prioritySort)
    }

    var missingAppleDomains: [ASCOpenAPIDomainCoverage] {
        domains
            .filter { $0.rule.status == .missing && !$0.paths.isEmpty }
            .sorted(by: ASCOpenAPIDomainCoverage.prioritySort)
    }
}

extension ASCOpenAPIDomainCoverage {
    static func prioritySort(lhs: ASCOpenAPIDomainCoverage, rhs: ASCOpenAPIDomainCoverage) -> Bool {
        if lhs.rule.priority == rhs.rule.priority {
            return lhs.rule.domain < rhs.rule.domain
        }
        return lhs.rule.priority < rhs.rule.priority
    }
}

struct ASCOpenAPICoverageAnalyzer: Sendable {
    let rules: [ASCOpenAPICoverageRule]

    /// Analyze an OpenAPI spec against the maintained product-domain coverage rules.
    /// - Parameters:
    ///   - spec: Parsed OpenAPI specification.
    ///   - generatedAt: Human-readable date string written to generated reports.
    /// - Returns: Coverage report with domain matches and unclassified Apple paths.
    func analyze(spec: ASCOpenAPISpec, generatedAt: String) -> ASCOpenAPICoverageReport {
        let domains = rules.map { rule in
            let matchedPaths = spec.paths
                .filter { path in rule.matches(path: path) }
                .sorted()
            let matchedPathSet = Set(matchedPaths)
            let matchedOperations = spec.operations
                .filter { matchedPathSet.contains($0.path) }
                .sorted { lhs, rhs in
                    if lhs.path == rhs.path {
                        return lhs.method < rhs.method
                    }
                    return lhs.path < rhs.path
                }
            return ASCOpenAPIDomainCoverage(rule: rule, paths: matchedPaths, operations: matchedOperations)
        }

        let classifiedPaths = Set(domains.flatMap(\.paths))
        let unclassifiedPaths = spec.paths
            .filter { !classifiedPaths.contains($0) }
            .sorted()

        return ASCOpenAPICoverageReport(
            spec: spec,
            generatedAt: generatedAt,
            domains: domains.sorted(by: ASCOpenAPIDomainCoverage.prioritySort),
            unclassifiedPaths: unclassifiedPaths
        )
    }
}

extension ASCOpenAPICoverageRule {
    func matches(path: String) -> Bool {
        pathPrefixes.contains { prefix in
            if prefix.hasSuffix("*") {
                return path.hasPrefix(String(prefix.dropLast()))
            }
            return path.hasPrefix(prefix)
        }
    }
}

enum ASCOpenAPICoverageRules {
    static var defaultRules: [ASCOpenAPICoverageRule] {
        ASCCoverageInventory.areas.map { area in
            ASCOpenAPICoverageRule(
                domain: area.name,
                priority: area.priority,
                status: area.status,
                pathPrefixes: pathPrefixesByArea[area.name] ?? [],
                workerKeys: area.workerKeys,
                toolPrefixes: toolPrefixes(for: area.workerKeys),
                notes: area.notes
            )
        }
    }

    private static let pathPrefixesByArea: [String: [String]] = [
        "Essentials: auth, errors, paging, uploads, rate limits": [],
        "App Store app metadata and release operations": [
            "/v1/accessibilityDeclarations",
            "/v1/ageRatingDeclarations",
            "/v1/androidToIosAppMappingDetails",
            "/v1/appCategories",
            "/v1/appClip",
            "/v1/appClips",
            "/v1/appCustomProductPage",
            "/v1/appEvent",
            "/v1/appInfo",
            "/v1/appPrice",
            "/v1/appPreview",
            "/v1/appScreenshot",
            "/v1/appStoreReview",
            "/v1/appStoreVersion",
            "/v1/appTags",
            "/v1/apps",
            "/v1/backgroundAsset",
            "/v1/customerReview",
            "/v1/endAppAvailabilityPreOrders",
            "/v1/endUserLicenseAgreements",
            "/v1/marketplaceSearchDetails",
            "/v1/nominations",
            "/v1/promotedPurchases",
            "/v1/reviewSubmission",
            "/v1/routingAppCoverages",
            "/v1/territories",
            "/v1/territoryAvailabilities",
            "/v2/appAvailabilities",
            "/v2/appStoreVersionExperiments",
            "/v3/appPricePoints"
        ],
        "TestFlight builds, testers, groups, and beta app review": [
            "/v1/appEncryption",
            "/v1/beta",
            "/v1/buildBeta",
            "/v1/buildBundles",
            "/v1/buildUpload",
            "/v1/builds",
            "/v1/preReleaseVersions"
        ],
        "Webhook notifications": [
            "/v1/webhookDeliveries",
            "/v1/webhookPings",
            "/v1/webhooks"
        ],
        "Webhook notification receiver resources": [],
        "In-app purchases, subscriptions, and offers": [
            "/v1/inAppPurchase",
            "/v1/subscription",
            "/v1/subscriptions",
            "/v1/winBackOffers",
            "/v2/inAppPurchases"
        ],
        "Provisioning and identifiers": [
            "/v1/bundleId",
            "/v1/certificates",
            "/v1/devices",
            "/v1/merchantIds",
            "/v1/passTypeIds",
            "/v1/profiles"
        ],
        "Users, access, and sandbox testers": [
            "/v1/actors",
            "/v1/userInvitations",
            "/v1/users",
            "/v2/sandboxTesters"
        ],
        "Reporting, analytics, metrics, and diagnostics": [
            "/v1/analyticsReport",
            "/v1/apps/{id}/metrics",
            "/v1/apps/{id}/perfPowerMetrics",
            "/v1/betaGroups/{id}/metrics",
            "/v1/betaTesters/{id}/metrics",
            "/v1/builds/{id}/diagnosticSignatures",
            "/v1/builds/{id}/metrics",
            "/v1/builds/{id}/perfPowerMetrics",
            "/v1/diagnosticSignatures",
            "/v1/financeReports",
            "/v1/gameCenterDetails/{id}/metrics",
            "/v1/gameCenterMatchmaking",
            "/v1/salesReports"
        ],
        "Xcode Cloud workflows and builds": [
            "/v1/ci",
            "/v1/scm"
        ],
        "Game Center": [
            "/v1/gameCenter",
            "/v2/gameCenter"
        ],
        "Alternative distribution": [
            "/v1/alternativeDistribution",
            "/v1/apps/{id}/alternativeDistributionKey",
            "/v1/apps/{id}/marketplaceSearchDetail",
            "/v1/marketplace",
            "/v1/marketplaceWebhooks"
        ]
    ]

    private static func toolPrefixes(for workerKeys: [String]) -> [String] {
        workerKeys.map { key in
            switch key {
            case "versions":
                "app_versions_"
            case "build_processing", "build_beta":
                "builds_"
            case "xcode_cloud":
                "xcode_cloud_"
            case "custom_pages":
                "custom_pages_"
            case "review_attachments":
                "review_attachments_"
            case "intro_offers":
                "intro_offers_"
            case "promo_offers":
                "promo_offers_"
            default:
                "\(key)_"
            }
        }
    }
}
