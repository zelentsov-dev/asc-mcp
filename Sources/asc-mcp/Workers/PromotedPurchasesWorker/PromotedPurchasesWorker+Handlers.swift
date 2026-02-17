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
                content: [.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCPromotedPurchasesResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCPromotedPurchasesResponse.self)
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list promoted purchases: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'promoted_purchase_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCPromotedPurchaseResponse = try await httpClient.get(
                "/v1/promotedPurchases/\(promotedPurchaseId)",
                as: ASCPromotedPurchaseResponse.self
            )

            let purchase = formatPromotedPurchase(response.data)

            let result = [
                "success": true,
                "promoted_purchase": purchase
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get promoted purchase: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameters: app_id, visible, enabled")],
                isError: true
            )
        }

        let iapId = arguments["iap_id"]?.stringValue
        let subscriptionId = arguments["subscription_id"]?.stringValue

        guard iapId != nil || subscriptionId != nil else {
            return CallTool.Result(
                content: [.text("Error: Either 'iap_id' or 'subscription_id' must be provided")],
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create promoted purchase: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'promoted_purchase_id' is missing")],
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update promoted purchase: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'promoted_purchase_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/promotedPurchases/\(promotedPurchaseId)")

            let result = [
                "success": true,
                "message": "Promoted purchase '\(promotedPurchaseId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete promoted purchase: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists promotion images for a promoted purchase
    /// - Returns: JSON array of images with file details and delivery state
    /// - Throws: On network or decoding errors
    func listPromotionImages(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let promotedPurchaseId = arguments["promoted_purchase_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'promoted_purchase_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCPromotionImagesResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCPromotionImagesResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/promotedPurchases/\(promotedPurchaseId)/promotionImages",
                    parameters: queryParams,
                    as: ASCPromotionImagesResponse.self
                )
            }

            let images = response.data.map { formatPromotionImage($0) }

            var result: [String: Any] = [
                "success": true,
                "promotion_images": images,
                "count": images.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list promotion images: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatPromotedPurchase(_ purchase: ASCPromotedPurchase) -> [String: Any] {
        return [
            "id": purchase.id,
            "type": purchase.type,
            "visibleForAllUsers": purchase.attributes?.visibleForAllUsers.jsonSafe ?? NSNull(),
            "enabled": purchase.attributes?.enabled.jsonSafe ?? NSNull(),
            "state": purchase.attributes?.state.jsonSafe ?? NSNull()
        ]
    }

    private func formatPromotionImage(_ image: ASCPromotionImage) -> [String: Any] {
        var result: [String: Any] = [
            "id": image.id,
            "type": image.type,
            "fileSize": image.attributes?.fileSize.jsonSafe ?? NSNull(),
            "fileName": image.attributes?.fileName.jsonSafe ?? NSNull(),
            "assetToken": image.attributes?.assetToken.jsonSafe ?? NSNull(),
            "sourceFileChecksum": image.attributes?.sourceFileChecksum.jsonSafe ?? NSNull()
        ]

        if let imageAsset = image.attributes?.imageAsset {
            result["imageAsset"] = [
                "templateUrl": imageAsset.templateUrl.jsonSafe,
                "width": imageAsset.width.jsonSafe,
                "height": imageAsset.height.jsonSafe
            ] as [String: Any]
        }

        if let deliveryState = image.attributes?.assetDeliveryState {
            result["assetDeliveryState"] = [
                "state": deliveryState.state.jsonSafe,
                "errors": (deliveryState.errors?.map { [
                    "code": $0.code.jsonSafe,
                    "description": $0.description.jsonSafe
                ] as [String: Any] }).jsonSafe
            ] as [String: Any]
        }

        return result
    }
}
