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
            "nextSteps": nextSteps(
                eventType: eventType,
                relatedResource: relatedResource,
                delivery: delivery,
                hasRecommendations: !recommendations.isEmpty
            ),
            "confidence": eventType == nil ? "low" : "high"
        ]
    }

    static func recommendations(
        eventType: String?,
        relatedResource: ASCWebhookRelatedResource?,
        delivery: ASCWebhookDeliveryContext
    ) -> [ASCWebhookToolRecommendation] {
        var recommendations: [ASCWebhookToolRecommendation] = []
        let relatedResourceID = canonicalRecommendationIdentifier(relatedResource?.id)
        let deliveryID = canonicalRecommendationIdentifier(delivery.deliveryID)
        let webhookID = canonicalRecommendationIdentifier(delivery.webhookID)

        switch eventType {
        case "APP_STORE_VERSION_APP_VERSION_STATE_UPDATED":
            if relatedResource?.type == "appStoreVersions", let id = relatedResourceID {
                recommendations.append(.init(
                    tool: "app_versions_get",
                    reason: "Read the current App Store version state after the webhook notification.",
                    arguments: ["version_id": id]
                ))
            }
        case "BUILD_UPLOAD_STATE_UPDATED":
            if relatedResource?.type == "buildUploads", let id = relatedResourceID {
                recommendations.append(.init(
                    tool: "build_uploads_get",
                    reason: "Inspect the BuildUpload state reported by the webhook.",
                    arguments: ["build_upload_id": id]
                ))
            }
        case "BUILD_BETA_DETAIL_EXTERNAL_BUILD_STATE_UPDATED":
            if relatedResource?.type == "buildBetaDetails", let webhookID {
                recommendations.append(.init(
                    tool: "webhooks_list_deliveries",
                    reason: "Correlate the BuildBetaDetail event with delivery payload data; its resource ID is not a Build ID.",
                    arguments: ["webhook_id": webhookID]
                ))
            }
        case "BETA_FEEDBACK_CRASH_SUBMISSION_CREATED":
            if relatedResource?.type == "betaFeedbackCrashSubmissions", let id = relatedResourceID {
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
            }
        case "BETA_FEEDBACK_SCREENSHOT_SUBMISSION_CREATED":
            if relatedResource?.type == "betaFeedbackScreenshotSubmissions", let id = relatedResourceID {
                recommendations.append(.init(
                    tool: "beta_feedback_get_screenshot",
                    reason: "Read the new TestFlight screenshot feedback submission.",
                    arguments: ["submission_id": id, "include_related": true]
                ))
            }
        case .some(let value) where value.hasPrefix("BACKGROUND_ASSET_"):
            if let webhookID {
                recommendations.append(.init(
                    tool: "webhooks_list_deliveries",
                    reason: "Confirm delivery history; dedicated background asset tools are not yet implemented.",
                    arguments: ["webhook_id": webhookID]
                ))
            }
        case .some(let value) where value.hasPrefix("ALTERNATIVE_DISTRIBUTION_"):
            if let webhookID {
                recommendations.append(.init(
                    tool: "webhooks_list_deliveries",
                    reason: "Confirm delivery history; dedicated alternative distribution tools are not yet implemented.",
                    arguments: ["webhook_id": webhookID]
                ))
            }
        default:
            if let webhookID {
                recommendations.append(.init(
                    tool: "webhooks_list_deliveries",
                    reason: "Use delivery history to correlate this webhook event with App Store Connect state.",
                    arguments: ["webhook_id": webhookID]
                ))
            }
        }

        if recommendations.isEmpty, let webhookID {
            recommendations.append(.init(
                tool: "webhooks_list_deliveries",
                reason: "Use delivery history or the raw event payload to identify the affected App Store Connect resource.",
                arguments: ["webhook_id": webhookID]
            ))
        }

        if delivery.requiresRecovery, let deliveryID {
            recommendations.append(.init(
                tool: "webhooks_redeliver",
                reason: "Mutating recovery action: create a new delivery attempt after fixing receiver availability.",
                arguments: ["delivery_id": deliveryID],
                effect: .mutating
            ))
        }
        if delivery.requiresRecovery, let webhookID {
            recommendations.append(.init(
                tool: "webhooks_ping",
                reason: "Mutating recovery action: create and send a test ping after receiver changes.",
                arguments: ["webhook_id": webhookID],
                effect: .mutating
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
            return ("info", "Build upload state changed", "Inspect the BuildUpload resource when processing reaches a terminal state.")
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

    private static func nextSteps(
        eventType: String?,
        relatedResource: ASCWebhookRelatedResource?,
        delivery: ASCWebhookDeliveryContext,
        hasRecommendations: Bool
    ) -> [String] {
        var steps: [String] = []
        var unavailableLookupExplained = false
        if delivery.requiresRecovery {
            steps.append("Fix receiver availability or response handling, then redeliver the failed delivery.")
        }
        if eventType == nil {
            steps.append("Parse the raw webhook body with webhooks_parse_payload to identify the event type.")
        }
        if let relatedResource,
           canonicalRecommendationIdentifier(relatedResource.id) == nil {
            steps.append("No executable resource lookup was recommended because the related resource ID is not canonical: it is empty, changes when trimmed or URL-encoded, contains a separator, percent escape, or control character, or is a dot segment. Inspect the raw event payload and supply a canonical resource ID.")
            unavailableLookupExplained = true
        } else if let expectedType = expectedFeedbackResourceType(for: eventType),
           relatedResource?.type != expectedType {
            let actualType = relatedResource.map { "'\($0.type)'" } ?? "no related resource type"
            steps.append("No executable feedback lookup was recommended because this event requires relatedResource.type '\(expectedType)', but the input provided \(actualType). Inspect the raw event payload and supply the exact related resource type and ID.")
            unavailableLookupExplained = true
        } else if relatedResource == nil {
            steps.append("Use the event payload or delivery history to identify the affected App Store Connect resource ID.")
        }
        if delivery.deliveryID != nil,
           canonicalRecommendationIdentifier(delivery.deliveryID) == nil {
            steps.append("webhooks_redeliver was not recommended because delivery_id is not canonical: it is empty, changes when trimmed or URL-encoded, contains a separator, percent escape, or control character, or is a dot segment. Supply the canonical delivery ID before requesting redelivery.")
            unavailableLookupExplained = true
        }
        if delivery.webhookID != nil,
           canonicalRecommendationIdentifier(delivery.webhookID) == nil {
            steps.append("Webhook delivery lookup and webhooks_ping were not recommended because webhook_id is not canonical: it is empty, changes when trimmed or URL-encoded, contains a separator, percent escape, or control character, or is a dot segment. Supply the canonical webhook ID first.")
            unavailableLookupExplained = true
        }
        if !hasRecommendations && !unavailableLookupExplained {
            steps.append("No executable lookup can be derived without the required resource or webhook ID; inspect the raw event payload and supply the missing ID before calling another tool.")
        }
        if steps.isEmpty {
            steps.append("Run the recommended read-only lookup tools and compare the current ASC state with the webhook payload.")
        }
        return steps
    }

    private static func canonicalRecommendationIdentifier(_ value: String?) -> String? {
        guard let value,
              !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let encoded = try? ASCPathSegment.encode(value),
              encoded == value else {
            return nil
        }
        return value
    }

    private static func expectedFeedbackResourceType(for eventType: String?) -> String? {
        switch eventType {
        case "BETA_FEEDBACK_CRASH_SUBMISSION_CREATED":
            return "betaFeedbackCrashSubmissions"
        case "BETA_FEEDBACK_SCREENSHOT_SUBMISSION_CREATED":
            return "betaFeedbackScreenshotSubmissions"
        default:
            return nil
        }
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
    let effect: ASCWebhookRecommendationEffect

    init(
        tool: String,
        reason: String,
        arguments: [String: Any],
        effect: ASCWebhookRecommendationEffect = .readOnly
    ) {
        self.tool = tool
        self.reason = reason
        self.arguments = arguments
        self.effect = effect
    }

    var dictionary: [String: Any] {
        [
            "tool": tool,
            "reason": reason,
            "arguments": arguments,
            "effect": effect.rawValue
        ]
    }
}

enum ASCWebhookRecommendationEffect: String, Sendable {
    case readOnly = "read_only"
    case mutating
}
