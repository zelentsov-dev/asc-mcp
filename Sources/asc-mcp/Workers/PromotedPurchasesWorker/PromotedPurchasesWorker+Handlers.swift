import Foundation
import MCP

// MARK: - Tool Handlers
extension PromotedPurchasesWorker {

    /// Lists promoted purchases for an app
    /// - Returns: JSON array of promoted purchases with visibility, enabled state, and status
    /// - Throws: On network or decoding errors
    func listPromotedPurchases(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCPromotedPurchasesResponse
            let endpoint = "/v1/apps/\(try ASCPathSegment.encode(appId))/promotedPurchases"
            let limit = arguments["limit"]?.intValue ?? 25
            let queryParams = ["limit": String(min(max(limit, 1), 200))]

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: promotedPurchasePaginationScope(path: endpoint, query: queryParams),
                    as: ASCPromotedPurchasesResponse.self
                )
            } else {
                response = try await httpClient.get(
                    endpoint,
                    parameters: queryParams,
                    as: ASCPromotedPurchasesResponse.self
                )
            }

            let purchases = response.data.map { formatPromotedPurchase($0) }

            var result: [String: Any] = [
                "success": true,
                "promoted_purchases": purchases,
                "count": purchases.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list promoted purchases: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets details of a specific promoted purchase
    /// - Returns: JSON with promoted purchase details (visibility, enabled, state)
    /// - Throws: On network or decoding errors
    func getPromotedPurchase(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let promotedPurchaseId = arguments["promoted_purchase_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'promoted_purchase_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCPromotedPurchaseResponse = try await httpClient.get(
                "/v1/promotedPurchases/\(try ASCPathSegment.encode(promotedPurchaseId))",
                parameters: ["include": "inAppPurchaseV2,subscription"],
                as: ASCPromotedPurchaseResponse.self
            )

            let purchase = formatPromotedPurchase(response.data, included: response.included)

            let result = [
                "success": true,
                "promoted_purchase": purchase
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get promoted purchase: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a promoted purchase for an IAP or subscription
    /// - Returns: JSON with created promoted purchase details
    /// - Throws: On network or encoding errors
    func createPromotedPurchase(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appId = arguments["app_id"]?.stringValue,
              let visible = arguments["visible"]?.boolValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters: app_id, visible")],
                isError: true
            )
        }

        let enabled: PromotedPurchaseNullableBool?
        do {
            enabled = try nullableBool("enabled", from: arguments)
        } catch {
            return MCPResult.error(error.localizedDescription)
        }
        let iapId = arguments["iap_id"]?.stringValue
        let subscriptionId = arguments["subscription_id"]?.stringValue

        guard (iapId != nil) != (subscriptionId != nil) else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Provide exactly one of 'iap_id' or 'subscription_id'")],
                isError: true
            )
        }

        do {
            let iapRelationship: CreatePromotedPurchaseRequest.IAPRelationship?
            if let iapId = iapId {
                iapRelationship = CreatePromotedPurchaseRequest.IAPRelationship(
                    data: ASCResourceIdentifier(type: "inAppPurchases", id: iapId)
                )
            } else {
                iapRelationship = nil
            }

            let subscriptionRelationship: CreatePromotedPurchaseRequest.SubscriptionRelationship?
            if let subscriptionId = subscriptionId {
                subscriptionRelationship = CreatePromotedPurchaseRequest.SubscriptionRelationship(
                    data: ASCResourceIdentifier(type: "subscriptions", id: subscriptionId)
                )
            } else {
                subscriptionRelationship = nil
            }

            let request = CreatePromotedPurchaseRequest(
                data: CreatePromotedPurchaseRequest.CreateData(
                    attributes: CreatePromotedPurchaseRequest.Attributes(
                        visibleForAllUsers: visible,
                        enabled: enabled
                    ),
                    relationships: CreatePromotedPurchaseRequest.Relationships(
                        app: CreatePromotedPurchaseRequest.AppRelationship(
                            data: ASCResourceIdentifier(type: "apps", id: appId)
                        ),
                        inAppPurchaseV2: iapRelationship,
                        subscription: subscriptionRelationship
                    )
                )
            )

            let response: ASCPromotedPurchaseResponse = try await httpClient.post(
                "/v1/promotedPurchases",
                body: request,
                as: ASCPromotedPurchaseResponse.self
            )

            let purchase = formatPromotedPurchase(
                response.data,
                fallbackIAPId: iapId,
                fallbackSubscriptionId: subscriptionId
            )

            let result = [
                "success": true,
                "promoted_purchase": purchase
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create promoted purchase: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates a promoted purchase
    /// - Returns: JSON with updated promoted purchase details
    /// - Throws: On network or encoding errors
    func updatePromotedPurchase(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let promotedPurchaseId = arguments["promoted_purchase_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'promoted_purchase_id' is missing")],
                isError: true
            )
        }

        let visible: PromotedPurchaseNullableBool?
        let enabled: PromotedPurchaseNullableBool?
        do {
            visible = try nullableBool("visible", from: arguments)
            enabled = try nullableBool("enabled", from: arguments)
        } catch {
            return MCPResult.error(error.localizedDescription)
        }
        guard visible != nil || enabled != nil else {
            return MCPResult.error("At least one update field is required: visible or enabled")
        }

        do {
            let request = UpdatePromotedPurchaseRequest(
                data: UpdatePromotedPurchaseRequest.UpdateData(
                    id: promotedPurchaseId,
                    attributes: UpdatePromotedPurchaseRequest.Attributes(
                        visibleForAllUsers: visible,
                        enabled: enabled
                    )
                )
            )

            let response: ASCPromotedPurchaseResponse = try await httpClient.patch(
                "/v1/promotedPurchases/\(try ASCPathSegment.encode(promotedPurchaseId))",
                body: request,
                as: ASCPromotedPurchaseResponse.self
            )

            let purchase = formatPromotedPurchase(response.data)

            let result = [
                "success": true,
                "promoted_purchase": purchase
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to update promoted purchase: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a promoted purchase
    /// - Returns: JSON confirmation
    /// - Throws: On network errors
    func deletePromotedPurchase(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let promotedPurchaseId = arguments["promoted_purchase_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'promoted_purchase_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/promotedPurchases/\(try ASCPathSegment.encode(promotedPurchaseId))")

            let result = [
                "success": true,
                "message": "Promoted purchase '\(promotedPurchaseId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return MCPResult.error(error, prefix: "Failed to delete promoted purchase")
        }
    }

    // MARK: - Image Handlers

    /// Returns migration guidance for the removed promoted purchase image upload endpoint.
    /// - Returns: A structured deprecation error with supported replacement tools.
    /// - Throws: This handler does not throw.
    func uploadPromotedPurchaseImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              arguments["promoted_purchase_id"]?.stringValue != nil,
              arguments["file_path"]?.stringValue != nil else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters: promoted_purchase_id, file_path")],
                isError: true
            )
        }
        return promotedImageDeprecation(tool: "promoted_upload_image")
    }

    /// Returns migration guidance for the removed promoted purchase image resource.
    /// - Returns: A structured deprecation error with supported replacement tools.
    /// - Throws: This handler does not throw.
    func getPromotedPurchaseImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              arguments["image_id"]?.stringValue != nil else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'image_id' is missing")],
                isError: true
            )
        }
        return promotedImageDeprecation(tool: "promoted_get_image")
    }

    /// Returns migration guidance for the removed promoted purchase image delete endpoint.
    /// - Returns: A structured deprecation error with supported replacement tools.
    /// - Throws: This handler does not throw.
    func deletePromotedPurchaseImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              arguments["image_id"]?.stringValue != nil else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'image_id' is missing")],
                isError: true
            )
        }
        return promotedImageDeprecation(tool: "promoted_delete_image")
    }

    /// Returns migration guidance for the removed promoted purchase image relationship.
    /// - Returns: A structured deprecation error with supported replacement tools.
    /// - Throws: This handler does not throw.
    func getPromotedPurchaseImageForPurchase(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              arguments["promoted_purchase_id"]?.stringValue != nil else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'promoted_purchase_id' is missing")],
                isError: true
            )
        }
        return promotedImageDeprecation(tool: "promoted_get_image_for_purchase")
    }

    // MARK: - Formatting

    private func promotedImageDeprecation(tool: String) -> CallTool.Result {
        MCPResult.error(
            "Apple App Store Connect API 4.4.1 no longer provides promoted purchase image endpoints.",
            details: .object([
                "deprecated": .bool(true),
                "tool": .string(tool),
                "migration": .string("Use promoted_get to resolve the linked product, then use the matching IAP or subscription image tools."),
                "replacement_tools": .array([
                    .string("iap_upload_image"),
                    .string("iap_get_image"),
                    .string("iap_list_images"),
                    .string("iap_delete_image"),
                    .string("subscriptions_upload_image"),
                    .string("subscriptions_get_image"),
                    .string("subscriptions_list_images"),
                    .string("subscriptions_delete_image")
                ])
            ])
        )
    }

    private func formatPromotedPurchase(
        _ purchase: ASCPromotedPurchase,
        included: [PromotedPurchaseIncludedResource]? = nil,
        fallbackIAPId: String? = nil,
        fallbackSubscriptionId: String? = nil
    ) -> [String: Any] {
        var result: [String: Any] = [
            "id": purchase.id,
            "type": purchase.type,
            "visibleForAllUsers": (purchase.attributes?.visibleForAllUsers).jsonSafe,
            "enabled": (purchase.attributes?.enabled).jsonSafe,
            "state": (purchase.attributes?.state).jsonSafe
        ]

        let includedIAPId = included?.first(where: { $0.type == "inAppPurchases" })?.id
        let includedSubscriptionId = included?.first(where: { $0.type == "subscriptions" })?.id
        result["inAppPurchaseId"] = (purchase.relationships?.inAppPurchaseV2?.data?.id ?? fallbackIAPId ?? includedIAPId).jsonSafe
        result["subscriptionId"] = (purchase.relationships?.subscription?.data?.id ?? fallbackSubscriptionId ?? includedSubscriptionId).jsonSafe

        // Add linked product info from included resources
        if let included = included, let resource = included.first {
            result["linkedProduct"] = [
                "type": resource.type,
                "id": resource.id,
                "name": (resource.attributes?.name).jsonSafe,
                "productId": (resource.attributes?.productId).jsonSafe
            ] as [String: Any]
        }

        return result
    }

    private func nullableBool(
        _ name: String,
        from arguments: [String: Value]
    ) throws -> PromotedPurchaseNullableBool? {
        guard let value = arguments[name] else {
            return nil
        }
        if value.isNull {
            return .null
        }
        guard let bool = value.boolValue else {
            throw PromotedPurchaseInputError("Parameter '\(name)' must be a boolean or null")
        }
        return .value(bool)
    }

    private func promotedPurchasePaginationScope(path: String, query: [String: String]) -> PaginationScope {
        PaginationScope(
            path: path,
            requiredParameters: query,
            allowedParameters: Set(query.keys).union(["cursor"]),
            requiredNonEmptyParameters: ["cursor"]
        )
    }
}

private struct PromotedPurchaseInputError: LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
