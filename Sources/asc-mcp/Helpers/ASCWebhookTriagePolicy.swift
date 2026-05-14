import Foundation

enum ASCWebhookTriagePolicy {
    static func triage(
        eventType: String?,
        relatedResource: ASCWebhookRelatedResource?,
        delivery: ASCWebhookDeliveryContext
    ) -> [String: Any] {
        let base = baseAssessment(eventType: eventType)
        let deliverySeverity = delivery.severity
        let severity = strongestSeverity(base.severity, deliverySeverity)
        let recommendations = recommendations(eventType: eventType, relatedResource: relatedResource, delivery: delivery)

        return [
            "success": true,
            "eventType": eventType.jsonSafe,
            "severity": severity,
            "title": base.title,
            "summary": base.summary,
            "relatedResource": relatedResource?.dictionary ?? NSNull(),
            "delivery": delivery.dictionary,
            "recommendedToolCalls": recommendations.map(\.dictionary),
            "nextSteps": nextSteps(eventType: eventType, delivery: delivery, hasRelatedResource: relatedResource != nil),
            "confidence": eventType == nil ? "low" : "high"
        ]
    }

    static func recommendations(
        eventType: String?,
        relatedResource: ASCWebhookRelatedResource?,
        delivery: ASCWebhookDeliveryContext
    ) -> [ASCWebhookToolRecommendation] {
        var recommendations: [ASCWebhookToolRecommendation] = []

        switch eventType {
        case "APP_STORE_VERSION_APP_VERSION_STATE_UPDATED":
            if relatedResource?.type == "appStoreVersions", let id = relatedResource?.id {
                recommendations.append(.init(
                    tool: "app_versions_get",
                    reason: "Read the current App Store version state after the webhook notification.",
                    arguments: ["version_id": id]
                ))
            }
        case "BUILD_UPLOAD_STATE_UPDATED":
            if relatedResource?.type == "builds", let id = relatedResource?.id {
                recommendations.append(.init(
                    tool: "builds_get",
                    reason: "Inspect the uploaded build state and related beta detail after processing changes.",
                    arguments: ["build_id": id, "include_beta_detail": true]
                ))
            } else {
                recommendations.append(.init(
                    tool: "builds_list",
                    reason: "Find the build affected by the upload state change.",
                    arguments: [:]
                ))
            }
        case "BUILD_BETA_DETAIL_EXTERNAL_BUILD_STATE_UPDATED":
            if relatedResource?.type == "builds", let id = relatedResource?.id {
                recommendations.append(.init(
                    tool: "builds_get_beta_detail",
                    reason: "Inspect external TestFlight state for the affected build.",
                    arguments: ["build_id": id]
                ))
                recommendations.append(.init(
                    tool: "builds_get",
                    reason: "Read build metadata alongside the external beta state.",
                    arguments: ["build_id": id, "include_beta_detail": true]
                ))
            }
        case "BETA_FEEDBACK_CRASH_SUBMISSION_CREATED":
            if let id = relatedResource?.id {
                recommendations.append(.init(
                    tool: "beta_feedback_get_crash",
                    reason: "Read the new TestFlight crash submission and related build/tester metadata.",
                    arguments: ["submission_id": id, "include_related": true]
                ))
                recommendations.append(.init(
                    tool: "beta_feedback_get_crash_log",
                    reason: "Fetch the crash log text for diagnosis.",
                    arguments: ["submission_id": id]
                ))
            } else {
                recommendations.append(.init(
                    tool: "beta_feedback_list_crashes",
                    reason: "Find the crash submission created by this webhook.",
                    arguments: [:]
                ))
            }
        case "BETA_FEEDBACK_SCREENSHOT_SUBMISSION_CREATED":
            if let id = relatedResource?.id {
                recommendations.append(.init(
                    tool: "beta_feedback_get_screenshot",
                    reason: "Read the new TestFlight screenshot feedback submission.",
                    arguments: ["submission_id": id, "include_related": true]
                ))
            } else {
                recommendations.append(.init(
                    tool: "beta_feedback_list_screenshots",
                    reason: "Find the screenshot submission created by this webhook.",
                    arguments: [:]
                ))
            }
        case .some(let value) where value.hasPrefix("BACKGROUND_ASSET_"):
            recommendations.append(.init(
                tool: "webhooks_list_deliveries",
                reason: "Confirm delivery history; dedicated background asset tools are not yet implemented.",
                arguments: delivery.webhookID.map { ["webhook_id": $0] } ?? [:]
            ))
        case .some(let value) where value.hasPrefix("ALTERNATIVE_DISTRIBUTION_"):
            recommendations.append(.init(
                tool: "webhooks_list_deliveries",
                reason: "Confirm delivery history; dedicated alternative distribution tools are not yet implemented.",
                arguments: delivery.webhookID.map { ["webhook_id": $0] } ?? [:]
            ))
        default:
            recommendations.append(.init(
                tool: "webhooks_list_deliveries",
                reason: "Use delivery history to correlate this webhook event with App Store Connect state.",
                arguments: delivery.webhookID.map { ["webhook_id": $0] } ?? [:]
            ))
        }

        if recommendations.isEmpty {
            recommendations.append(.init(
                tool: "webhooks_list_deliveries",
                reason: "Use delivery history or the raw event payload to identify the affected App Store Connect resource.",
                arguments: delivery.webhookID.map { ["webhook_id": $0] } ?? [:]
            ))
        }

        if delivery.requiresRecovery, let deliveryID = delivery.deliveryID {
            recommendations.append(.init(
                tool: "webhooks_redeliver",
                reason: "Retry the failed webhook delivery after fixing receiver availability.",
                arguments: ["delivery_id": deliveryID]
            ))
        }
        if delivery.requiresRecovery, let webhookID = delivery.webhookID {
            recommendations.append(.init(
                tool: "webhooks_ping",
                reason: "Send a test ping after receiver changes to verify the endpoint is healthy.",
                arguments: ["webhook_id": webhookID]
            ))
        }

        return recommendations
    }

    private static func baseAssessment(eventType: String?) -> (severity: String, title: String, summary: String) {
        switch eventType {
        case "BETA_FEEDBACK_CRASH_SUBMISSION_CREATED":
            return ("high", "New TestFlight crash feedback", "A tester submitted crash feedback; inspect the submission and crash log before shipping.")
        case "BETA_FEEDBACK_SCREENSHOT_SUBMISSION_CREATED":
            return ("medium", "New TestFlight screenshot feedback", "A tester submitted screenshot feedback; inspect the submission and related build context.")
        case "APP_STORE_VERSION_APP_VERSION_STATE_UPDATED":
            return ("medium", "App version state changed", "Review the affected App Store version state and decide whether release workflow action is needed.")
        case "BUILD_BETA_DETAIL_EXTERNAL_BUILD_STATE_UPDATED":
            return ("medium", "External TestFlight state changed", "Review external beta readiness and tester availability for the affected build.")
        case "BUILD_UPLOAD_STATE_UPDATED":
            return ("info", "Build upload state changed", "Inspect the build when processing reaches a terminal state.")
        case .some(let value) where value.hasPrefix("BACKGROUND_ASSET_"):
            return ("medium", "Background asset event", "The event belongs to Apple-hosted background assets; this server currently only provides webhook diagnostics for that domain.")
        case .some(let value) where value.hasPrefix("ALTERNATIVE_DISTRIBUTION_"):
            return ("medium", "Alternative distribution event", "The event belongs to alternative distribution; this server currently only provides webhook diagnostics for that domain.")
        case .some:
            return ("info", "Webhook event received", "The event type is recognized as webhook input but has no specialized triage playbook yet.")
        case nil:
            return ("info", "Webhook event type missing", "Provide event_type or a raw payload to generate a more specific triage plan.")
        }
    }

    private static func nextSteps(eventType: String?, delivery: ASCWebhookDeliveryContext, hasRelatedResource: Bool) -> [String] {
        var steps: [String] = []
        if delivery.requiresRecovery {
            steps.append("Fix receiver availability or response handling, then redeliver the failed delivery.")
        }
        if eventType == nil {
            steps.append("Parse the raw webhook body with webhooks_parse_payload to identify the event type.")
        }
        if !hasRelatedResource {
            steps.append("Use the event payload or delivery history to identify the affected App Store Connect resource ID.")
        }
        if steps.isEmpty {
            steps.append("Run the recommended read-only lookup tools and compare the current ASC state with the webhook payload.")
        }
        return steps
    }

    private static func strongestSeverity(_ lhs: String, _ rhs: String) -> String {
        let rank = ["info": 0, "medium": 1, "high": 2]
        return (rank[lhs, default: 0] >= rank[rhs, default: 0]) ? lhs : rhs
    }
}

struct ASCWebhookDeliveryContext: Sendable {
    let deliveryID: String?
    let webhookID: String?
    let deliveryState: String?
    let httpStatusCode: Int?
    let errorMessage: String?

    static let empty = ASCWebhookDeliveryContext(
        deliveryID: nil,
        webhookID: nil,
        deliveryState: nil,
        httpStatusCode: nil,
        errorMessage: nil
    )

    var requiresRecovery: Bool {
        if deliveryState == "FAILED" {
            return true
        }
        if let httpStatusCode, httpStatusCode >= 400 {
            return true
        }
        return false
    }

    var severity: String {
        if deliveryState == "FAILED" || (httpStatusCode ?? 0) >= 500 {
            return "high"
        }
        if (httpStatusCode ?? 0) >= 400 {
            return "medium"
        }
        return "info"
    }

    var dictionary: [String: Any] {
        [
            "deliveryId": deliveryID.jsonSafe,
            "webhookId": webhookID.jsonSafe,
            "deliveryState": deliveryState.jsonSafe,
            "httpStatusCode": httpStatusCode.jsonSafe,
            "errorMessage": errorMessage.jsonSafe,
            "requiresRecovery": requiresRecovery
        ]
    }
}

struct ASCWebhookToolRecommendation {
    let tool: String
    let reason: String
    let arguments: [String: Any]

    var dictionary: [String: Any] {
        [
            "tool": tool,
            "reason": reason,
            "arguments": arguments
        ]
    }
}
