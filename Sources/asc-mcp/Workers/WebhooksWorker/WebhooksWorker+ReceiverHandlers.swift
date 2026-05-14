import Foundation
import MCP

extension WebhooksWorker {
    /// Verifies an App Store Connect webhook `x-apple-signature` header against the exact raw payload body.
    /// - Parameter params: Tool parameters containing `secret`, `signature`, and either `payload` or `payload_base64`.
    /// - Returns: JSON object with verification status, normalized signatures, and diagnostic reason.
    /// - Throws: No network errors; all validation failures are returned as MCP tool errors.
    func verifySignature(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let secret = arguments["secret"]?.stringValue,
              !secret.isEmpty,
              let signature = arguments["signature"]?.stringValue else {
            return MCPResult.error("Required parameters: secret, signature, and payload or payload_base64")
        }

        do {
            let payload = try payloadData(from: arguments)
            let verification = ASCWebhookSignatureVerifier.verify(
                secret: secret,
                payload: payload,
                signatureHeader: signature
            )
            return MCPResult.jsonObject(verification.dictionary)
        } catch {
            return MCPResult.error("Failed to verify webhook signature: \(error.localizedDescription)")
        }
    }

    /// Parses a raw App Store Connect webhook payload and normalizes the event and nested payload information.
    /// - Parameter params: Tool parameters containing `payload` or `payload_base64`, and optional signature verification values.
    /// - Returns: JSON object with event type, related resource, parsed nested payload, and recommended lookup tools.
    /// - Throws: No network errors; parsing failures are returned as MCP tool errors.
    func parsePayload(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter: payload or payload_base64")
        }

        do {
            let payload = try payloadData(from: arguments)
            let parsed = try ASCWebhookReceiverParser.parse(payload)
            var result = parsed.dictionary

            if let secret = arguments["secret"]?.stringValue,
               let signature = arguments["signature"]?.stringValue {
                let verification = ASCWebhookSignatureVerifier.verify(
                    secret: secret,
                    payload: payload,
                    signatureHeader: signature
                )
                result["signature"] = verification.dictionary
            }

            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to parse webhook payload: \(error.localizedDescription)")
        }
    }

    /// Builds an actionable triage plan for an App Store Connect webhook event or delivery failure.
    /// - Parameter params: Tool parameters containing a raw payload or explicit event/delivery fields.
    /// - Returns: JSON object with severity, summary, next steps, and suggested MCP tool calls.
    /// - Throws: No network errors; validation failures are returned as MCP tool errors.
    func triageEvent(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Provide event_type or payload/payload_base64")
        }

        do {
            let parsed = try parseOptionalPayload(arguments)
            let eventType = arguments["event_type"]?.stringValue ?? parsed?.eventType
            let relatedResource = explicitRelatedResource(arguments) ?? parsed?.relatedResource

            guard eventType != nil || parsed != nil else {
                return MCPResult.error("Provide event_type or payload/payload_base64")
            }

            let delivery = ASCWebhookDeliveryContext(
                deliveryID: arguments["delivery_id"]?.stringValue,
                webhookID: arguments["webhook_id"]?.stringValue,
                deliveryState: arguments["delivery_state"]?.stringValue,
                httpStatusCode: arguments["http_status_code"]?.intValue,
                errorMessage: arguments["error_message"]?.stringValue
            )

            let result = ASCWebhookTriagePolicy.triage(
                eventType: eventType,
                relatedResource: relatedResource,
                delivery: delivery
            )
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to triage webhook event: \(error.localizedDescription)")
        }
    }

    private func parseOptionalPayload(_ arguments: [String: Value]) throws -> ASCWebhookParsedPayload? {
        guard arguments["payload"] != nil || arguments["payload_base64"] != nil else {
            return nil
        }
        return try ASCWebhookReceiverParser.parse(payloadData(from: arguments))
    }

    private func explicitRelatedResource(_ arguments: [String: Value]) -> ASCWebhookRelatedResource? {
        guard let resourceID = arguments["resource_id"]?.stringValue else {
            return nil
        }
        return ASCWebhookRelatedResource(
            type: arguments["resource_type"]?.stringValue ?? "unknown",
            id: resourceID
        )
    }

    private func payloadData(from arguments: [String: Value]) throws -> Data {
        if let base64 = arguments["payload_base64"]?.stringValue {
            guard let data = Data(base64Encoded: base64) else {
                throw ASCError.parsing("payload_base64 is not valid base64")
            }
            return data
        }
        if let payload = arguments["payload"]?.stringValue,
           let data = payload.data(using: .utf8) {
            return data
        }
        throw ASCError.parsing("Provide payload as a raw UTF-8 string or payload_base64 as exact raw request bytes")
    }
}
