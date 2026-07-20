import Foundation

enum ASCCoverageStatus: String, Codable, Sendable {
    case covered
    case partial
    case missing
}

enum ASCCoveragePriority: String, Codable, Sendable, Comparable {
    case p0 = "P0"
    case p1 = "P1"
    case p2 = "P2"
    case p3 = "P3"

    static func < (lhs: ASCCoveragePriority, rhs: ASCCoveragePriority) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }

    private var sortIndex: Int {
        switch self {
        case .p0: 0
        case .p1: 1
        case .p2: 2
        case .p3: 3
        }
    }
}

struct ASCCoverageArea: Sendable {
    let name: String
    let appleDocumentationURL: String
    let status: ASCCoverageStatus
    let priority: ASCCoveragePriority
    let workerKeys: [String]
    let coveredCapabilities: [String]
    let missingCapabilities: [String]
    let notes: String
}

enum ASCCoverageInventory {
    static let snapshotDate = "2026-07-20"
    static let appleAPIVersionBaseline = "4.4.1"

    static let areas: [ASCCoverageArea] = [
        ASCCoverageArea(
            name: "Essentials: auth, errors, paging, uploads, rate limits",
            appleDocumentationURL: "https://developer.apple.com/documentation/appstoreconnectapi",
            status: .partial,
            priority: .p1,
            workerKeys: ["auth"],
            coveredCapabilities: [
                "JWT generation and status",
                "Apple API error decoding",
                "pagination helpers",
                "bounded upload flow",
                "rate-limit metadata capture",
                "automated OpenAPI spec coverage report generation"
            ],
            missingCapabilities: [
                "first-class API key revocation/read inventory helpers"
            ],
            notes: "Core runtime behavior is covered; OpenAPI drift is now generated from Apple's official specification."
        ),
        ASCCoverageArea(
            name: "App Store app metadata and release operations",
            appleDocumentationURL: "https://developer.apple.com/documentation/appstoreconnectapi/app-store",
            status: .partial,
            priority: .p0,
            workerKeys: [
                "apps", "accessibility", "versions", "app_info", "pricing", "app_events",
                "screenshots", "custom_pages", "ppo", "promoted", "review_attachments",
                "review_submissions", "reviews", "export_compliance"
            ],
            coveredCapabilities: [
                "apps, app info, version lifecycle, review responses",
                "age rating questionnaire updates and reads",
                "territory-specific calculated age ratings",
                "confirmed phased release controls",
                "accessibility declarations",
                "pricing and availability",
                "in-app events",
                "screenshots and app previews",
                "custom product pages",
                "product page optimization",
                "promoted purchases",
                "review attachments",
                "generic review submission assembly, submission, cancellation, and recovery",
                "export-compliance release gate"
            ],
            missingCapabilities: [
                "App Clips and advanced App Clip experiences",
                "background assets",
                "app tags",
                "routing app coverages",
                "customer review summary endpoint"
            ],
            notes: "The common release workflow includes strict version filtering and paging, safe phased-release controls, generic review submissions, and App Info-owned age-rating inspection. API 4.0 app-surface additions remain the highest App Store coverage gap."
        ),
        ASCCoverageArea(
            name: "TestFlight builds, testers, groups, and beta app review",
            appleDocumentationURL: "https://developer.apple.com/documentation/appstoreconnectapi/prerelease-versions-and-beta-testers",
            status: .partial,
            priority: .p0,
            workerKeys: [
                "builds", "build_processing", "export_compliance", "build_beta", "beta_groups",
                "beta_feedback", "beta_testers", "beta_app", "pre_release", "beta_license"
            ],
            coveredCapabilities: [
                "build list/find",
                "build processing and encryption",
                "export-compliance declarations, documents, and verified build linkage",
                "beta localizations and build notifications",
                "beta groups and testers",
                "beta feedback crash submissions",
                "beta feedback screenshot submissions",
                "beta crash log reads",
                "beta app review submissions",
                "pre-release versions",
                "beta license agreements"
            ],
            missingCapabilities: [
                "beta recruitment criteria",
                "beta app clip invocation/localization APIs"
            ],
            notes: "Core TestFlight administration and dedicated beta feedback retrieval are covered; recruitment criteria and beta App Clip APIs remain the main gaps."
        ),
        ASCCoverageArea(
            name: "Webhook notifications",
            appleDocumentationURL: "https://developer.apple.com/documentation/appstoreconnectapi/webhook-notifications",
            status: .covered,
            priority: .p2,
            workerKeys: ["webhooks"],
            coveredCapabilities: [
                "list app webhooks",
                "get webhook",
                "create webhook",
                "update webhook",
                "delete webhook",
                "list deliveries",
                "redeliver webhook delivery",
                "send webhook ping"
            ],
            missingCapabilities: [],
            notes: "Covers app webhooks, individual webhook reads, create/update/delete, delivery listing, redelivery, ping testing, and local receiver diagnostics."
        ),
        ASCCoverageArea(
            name: "Webhook notification receiver resources",
            appleDocumentationURL: "https://developer.apple.com/documentation/appstoreconnectapi/webhook-notifications",
            status: .partial,
            priority: .p1,
            workerKeys: ["webhooks"],
            coveredCapabilities: [
                "receiver-side x-apple-signature verification",
                "webhook event payload decoder",
                "event and delivery triage recommendations"
            ],
            missingCapabilities: [
                "hosted receiver server templates",
                "MCP prompt/resource templates for reusable event playbooks"
            ],
            notes: "Local receiver helpers are now available and remain read-only; future work can add deployable receiver templates and reusable playbooks."
        ),
        ASCCoverageArea(
            name: "In-app purchases, subscriptions, and offers",
            appleDocumentationURL: "https://developer.apple.com/documentation/appstoreconnectapi/app-store",
            status: .partial,
            priority: .p2,
            workerKeys: ["iap", "subscriptions"],
            coveredCapabilities: [
                "IAP and subscription CRUD with versioned metadata",
                "subscription group versions and version-owned localizations",
                "singular and paginated plural version-owned IAP review images and subscription promotional images",
                "territory-aware prices, price points, adjusted equalizations, and plan-type-aware availability",
                "legacy localization, image, submission, and availability compatibility with explicit migration guidance",
                "IAP and subscription offer codes",
                "win-back offers",
                "introductory offers",
                "promotional offers",
                "pricing summaries and compatibility inventory helper",
                "review screenshot and image uploads"
            ],
            missingCapabilities: [
                "authoritative fully paginated subscription inventory"
            ],
            notes: "Apple 4.4.1 versioned metadata, generic review submission handoff, plan-type-aware subscription availability, and adjusted equalizations are covered. Legacy product-scoped tools remain explicit compatibility paths; an authoritative fully paginated subscription inventory is still pending."
        ),
        ASCCoverageArea(
            name: "Provisioning and identifiers",
            appleDocumentationURL: "https://developer.apple.com/documentation/appstoreconnectapi/bundle-ids",
            status: .partial,
            priority: .p1,
            workerKeys: ["provisioning"],
            coveredCapabilities: [
                "bundle IDs",
                "bundle ID capabilities",
                "devices",
                "certificates",
                "profiles"
            ],
            missingCapabilities: [
                "merchant IDs",
                "pass type IDs"
            ],
            notes: "Core signing automation exists; Wallet and Apple Pay identifiers are useful next additions."
        ),
        ASCCoverageArea(
            name: "Users, access, and sandbox testers",
            appleDocumentationURL: "https://developer.apple.com/documentation/appstoreconnectapi/users",
            status: .partial,
            priority: .p2,
            workerKeys: ["users", "sandbox"],
            coveredCapabilities: [
                "team users",
                "roles and visible apps",
                "user invitations",
                "sandbox testers"
            ],
            missingCapabilities: [
                "API key inventory helpers",
                "API key revocation workflow"
            ],
            notes: "User management is serviceable; API key operations should remain carefully annotated as high-risk."
        ),
        ASCCoverageArea(
            name: "Reporting, analytics, metrics, and diagnostics",
            appleDocumentationURL: "https://developer.apple.com/documentation/appstoreconnectapi/analytics",
            status: .partial,
            priority: .p1,
            workerKeys: ["analytics", "metrics"],
            coveredCapabilities: [
                "sales reports",
                "financial reports",
                "analytics reports and snapshots",
                "performance and power metrics"
            ],
            missingCapabilities: [
                "analytics segment discovery ergonomics",
                "customer review summarization",
                "recommendations exposed by perf power metrics"
            ],
            notes: "Read-heavy workflows are safe and valuable; summaries and recommendations are high UX leverage."
        ),
        ASCCoverageArea(
            name: "Xcode Cloud workflows and builds",
            appleDocumentationURL: "https://developer.apple.com/documentation/appstoreconnectapi/xcode-cloud-workflows-and-builds",
            status: .partial,
            priority: .p1,
            workerKeys: ["xcode_cloud"],
            coveredCapabilities: [
                "list/get Xcode Cloud products",
                "list/get workflows",
                "start/rebuild build runs",
                "list/get build runs and actions",
                "inspect artifacts, issues, and test results",
                "list Xcode and macOS versions",
                "read SCM providers, repositories, git references, and pull requests"
            ],
            missingCapabilities: [
                "workflow create/update/delete",
                "Xcode Cloud product delete",
                "relationship-only linkage endpoints"
            ],
            notes: "Covers read-heavy CI dashboards plus start/rebuild build runs; destructive workflow/product management remains intentionally deferred."
        ),
        ASCCoverageArea(
            name: "Game Center",
            appleDocumentationURL: "https://developer.apple.com/documentation/appstoreconnectapi/game-center",
            status: .missing,
            priority: .p2,
            workerKeys: [],
            coveredCapabilities: [],
            missingCapabilities: [
                "Game Center details",
                "leaderboards",
                "achievements",
                "activities",
                "challenges"
            ],
            notes: "Large domain; should be added only after OpenAPI-driven scaffolding is in place."
        ),
        ASCCoverageArea(
            name: "Alternative distribution",
            appleDocumentationURL: "https://developer.apple.com/documentation/appstoreconnectapi/alternative-marketplaces-and-web-distribution",
            status: .missing,
            priority: .p2,
            workerKeys: [],
            coveredCapabilities: [],
            missingCapabilities: [
                "alternative marketplace resources",
                "web distribution resources",
                "eligibility and marketplace workflow helpers"
            ],
            notes: "Region- and entitlement-sensitive APIs should be opt-in and strongly documented."
        )
    ]

    static var highPriorityGaps: [ASCCoverageArea] {
        areas
            .filter { $0.priority <= .p1 && $0.status != .covered }
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.name < rhs.name
                }
                return lhs.priority < rhs.priority
            }
    }
}
