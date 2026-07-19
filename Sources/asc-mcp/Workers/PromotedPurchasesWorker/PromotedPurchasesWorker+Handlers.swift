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

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: "/v1/apps/\(appId)/promotedPurchases"),
                    as: ASCPromotedPurchasesResponse.self
                )
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/apps/\(appId)/promotedPurchases",
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
                "/v1/promotedPurchases/\(promotedPurchaseId)",
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
              let visible = arguments["visible"]?.boolValue,
              let enabled = arguments["enabled"]?.boolValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters: app_id, visible, enabled")],
                isError: true
            )
        }

        let iapId = arguments["iap_id"]?.stringValue
        let subscriptionId = arguments["subscription_id"]?.stringValue

        guard iapId != nil || subscriptionId != nil else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Either 'iap_id' or 'subscription_id' must be provided")],
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

            let purchase = formatPromotedPurchase(response.data)

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

        do {
            let request = UpdatePromotedPurchaseRequest(
                data: UpdatePromotedPurchaseRequest.UpdateData(
                    id: promotedPurchaseId,
                    attributes: UpdatePromotedPurchaseRequest.Attributes(
                        visibleForAllUsers: arguments["visible"]?.boolValue,
                        enabled: arguments["enabled"]?.boolValue
                    )
                )
            )

            let response: ASCPromotedPurchaseResponse = try await httpClient.patch(
                "/v1/promotedPurchases/\(promotedPurchaseId)",
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
            _ = try await httpClient.delete("/v1/promotedPurchases/\(promotedPurchaseId)")

            let result = [
                "success": true,
                "message": "Promoted purchase '\(promotedPurchaseId)' deleted"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to delete promoted purchase: \(error.localizedDescription)")],
                isError: true
            )
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

    private func formatPromotedPurchase(_ purchase: ASCPromotedPurchase, included: [PromotedPurchaseIncludedResource]? = nil) -> [String: Any] {
        var result: [String: Any] = [
            "id": purchase.id,
            "type": purchase.type,
            "visibleForAllUsers": (purchase.attributes?.visibleForAllUsers).jsonSafe,
            "enabled": (purchase.attributes?.enabled).jsonSafe,
            "state": (purchase.attributes?.state).jsonSafe
        ]

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
}
