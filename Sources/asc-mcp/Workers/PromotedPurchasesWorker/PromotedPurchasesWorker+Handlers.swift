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
                parameters: ["include": "inAppPurchaseV2,subscription"],
                as: ASCPromotedPurchaseResponse.self
            )

            let purchase = formatPromotedPurchase(response.data, included: response.included)

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

    // MARK: - Image Handlers

    /// Uploads a promotional image for a promoted purchase (full cycle: reserve → upload → commit)
    /// - Returns: JSON with uploaded image details including state and asset info
    /// - Throws: On file read, upload, or API errors
    func uploadPromotedPurchaseImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let promotedPurchaseId = arguments["promoted_purchase_id"]?.stringValue,
              let filePath = arguments["file_path"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters: promoted_purchase_id, file_path")],
                isError: true
            )
        }

        do {
            // Step 1: Get file info
            let fileSize = try await uploadService.fileSize(at: filePath)
            let fileName = await uploadService.fileName(at: filePath)

            // Step 2: Reserve — POST to create image resource with upload operations
            let createRequest = CreatePromotedPurchaseImageRequest(
                data: CreatePromotedPurchaseImageRequest.CreateData(
                    attributes: CreatePromotedPurchaseImageRequest.Attributes(
                        fileSize: fileSize,
                        fileName: fileName
                    ),
                    relationships: CreatePromotedPurchaseImageRequest.Relationships(
                        promotedPurchase: CreatePromotedPurchaseImageRequest.PromotedPurchaseRelationship(
                            data: ASCResourceIdentifier(type: "promotedPurchases", id: promotedPurchaseId)
                        )
                    )
                )
            )

            let reserveResponse: ASCPromotedPurchaseImageResponse = try await httpClient.post(
                "/v1/promotedPurchaseImages",
                body: createRequest,
                as: ASCPromotedPurchaseImageResponse.self
            )

            let imageId = reserveResponse.data.id
            guard let uploadOperations = reserveResponse.data.attributes?.uploadOperations,
                  !uploadOperations.isEmpty else {
                return CallTool.Result(
                    content: [.text("Error: No upload operations returned for image '\(imageId)'")],
                    isError: true
                )
            }

            // Step 3: Upload file chunks
            let md5 = try await uploadService.uploadFile(filePath: filePath, uploadOperations: uploadOperations)

            // Step 4: Commit — PATCH with checksum and uploaded=true
            let commitRequest = CommitPromotedPurchaseImageRequest(
                data: CommitPromotedPurchaseImageRequest.CommitData(
                    id: imageId,
                    attributes: CommitPromotedPurchaseImageRequest.Attributes(
                        sourceFileChecksum: md5,
                        uploaded: true
                    )
                )
            )

            let commitResponse: ASCPromotedPurchaseImageResponse = try await httpClient.patch(
                "/v1/promotedPurchaseImages/\(imageId)",
                body: commitRequest,
                as: ASCPromotedPurchaseImageResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "image": formatPromotedPurchaseImage(commitResponse.data)
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to upload promoted purchase image: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets details of a promoted purchase image
    /// - Returns: JSON with image details including state and asset info
    /// - Throws: On network or decoding errors
    func getPromotedPurchaseImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let imageId = arguments["image_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'image_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCPromotedPurchaseImageResponse = try await httpClient.get(
                "/v1/promotedPurchaseImages/\(imageId)",
                as: ASCPromotedPurchaseImageResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "image": formatPromotedPurchaseImage(response.data)
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get promoted purchase image: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a promoted purchase image
    /// - Returns: JSON confirmation
    /// - Throws: On network errors
    func deletePromotedPurchaseImage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let imageId = arguments["image_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'image_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/promotedPurchaseImages/\(imageId)")

            let result = [
                "success": true,
                "message": "Promoted purchase image '\(imageId)' deleted"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete promoted purchase image: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets the promotional image for a promoted purchase by parent ID (singular resource)
    /// - Returns: JSON with image details
    /// - Throws: On network or decoding errors
    func getPromotedPurchaseImageForPurchase(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let promotedPurchaseId = arguments["promoted_purchase_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'promoted_purchase_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCPromotedPurchaseImageResponse = try await httpClient.get(
                "/v1/promotedPurchases/\(promotedPurchaseId)/promotionImage",
                as: ASCPromotedPurchaseImageResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "image": formatPromotedPurchaseImage(response.data)
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get promoted purchase image: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatPromotedPurchaseImage(_ image: ASCPromotedPurchaseImage) -> [String: Any] {
        var result: [String: Any] = [
            "id": image.id,
            "type": image.type,
            "fileSize": image.attributes?.fileSize.jsonSafe ?? NSNull(),
            "fileName": image.attributes?.fileName.jsonSafe ?? NSNull(),
            "sourceFileChecksum": image.attributes?.sourceFileChecksum.jsonSafe ?? NSNull(),
            "state": image.attributes?.state.jsonSafe ?? NSNull()
        ]

        if let asset = image.attributes?.imageAsset {
            result["imageAsset"] = [
                "templateUrl": asset.templateUrl.jsonSafe,
                "width": asset.width.jsonSafe,
                "height": asset.height.jsonSafe
            ] as [String: Any]
        }

        return result
    }

    private func formatPromotedPurchase(_ purchase: ASCPromotedPurchase, included: [PromotedPurchaseIncludedResource]? = nil) -> [String: Any] {
        var result: [String: Any] = [
            "id": purchase.id,
            "type": purchase.type,
            "visibleForAllUsers": purchase.attributes?.visibleForAllUsers.jsonSafe ?? NSNull(),
            "enabled": purchase.attributes?.enabled.jsonSafe ?? NSNull(),
            "state": purchase.attributes?.state.jsonSafe ?? NSNull()
        ]

        // Add linked product info from included resources
        if let included = included, let resource = included.first {
            result["linkedProduct"] = [
                "type": resource.type,
                "id": resource.id,
                "name": resource.attributes?.name.jsonSafe ?? NSNull(),
                "productId": resource.attributes?.productId.jsonSafe ?? NSNull()
            ] as [String: Any]
        }

        return result
    }
}
