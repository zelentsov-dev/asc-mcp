import Foundation
import MCP

// MARK: - Tool Handlers
extension SandboxTestersWorker {

    /// Lists sandbox testers for the current account
    /// - Returns: JSON array of sandbox testers with attributes
    func listSandboxTesters(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments

        do {
            let response: ASCSandboxTestersResponse

            if let nextUrl = try paginationURL(from: arguments?["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: "/v2/sandboxTesters"),
                    as: ASCSandboxTestersResponse.self
                )
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments?["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v2/sandboxTesters",
                    parameters: queryParams,
                    as: ASCSandboxTestersResponse.self
                )
            }

            let testers = response.data.map { formatSandboxTester($0) }

            var result: [String: Any] = [
                "success": true,
                "sandbox_testers": testers,
                "count": testers.count
            ]
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list sandbox testers: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates a sandbox tester's settings
    /// - Returns: JSON with updated sandbox tester details
    func updateSandboxTester(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let sandboxTesterId = arguments["sandbox_tester_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'sandbox_tester_id' is missing")],
                isError: true
            )
        }

        var attributes: [String: JSONValue] = [:]
        if let territory = arguments["territory"] {
            if territory.isNull {
                attributes["territory"] = .null
            } else if let value = territory.stringValue,
                      SandboxTesterTerritoryValues.all.contains(value) {
                attributes["territory"] = .string(value)
            } else {
                return MCPResult.error("Parameter 'territory' must be a documented Apple territory code or null")
            }
        }
        if let interruptPurchases = arguments["interrupt_purchases"] {
            if interruptPurchases.isNull {
                attributes["interruptPurchases"] = .null
            } else if let value = interruptPurchases.boolValue {
                attributes["interruptPurchases"] = .bool(value)
            } else {
                return MCPResult.error("Parameter 'interrupt_purchases' must be a boolean or null")
            }
        }
        if let renewalRate = arguments["subscription_renewal_rate"] {
            if renewalRate.isNull {
                attributes["subscriptionRenewalRate"] = .null
            } else if let value = renewalRate.stringValue,
                      Self.subscriptionRenewalRates.contains(value) {
                attributes["subscriptionRenewalRate"] = .string(value)
            } else {
                return MCPResult.error("Parameter 'subscription_renewal_rate' must be null or a documented renewal rate")
            }
        }
        guard !attributes.isEmpty else {
            return MCPResult.error("At least one update field is required: territory, interrupt_purchases, or subscription_renewal_rate")
        }

        do {
            let request = UpdateSandboxTesterRequest(
                data: UpdateSandboxTesterRequest.UpdateData(
                    id: sandboxTesterId,
                    attributes: attributes
                )
            )

            let response: ASCSandboxTesterResponse = try await httpClient.patch(
                "/v2/sandboxTesters/\(try ASCPathSegment.encode(sandboxTesterId))",
                body: request,
                as: ASCSandboxTesterResponse.self
            )

            let tester = formatSandboxTester(response.data)

            let result = [
                "success": true,
                "sandbox_tester": tester
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to update sandbox tester: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Clears purchase history for sandbox testers
    /// - Returns: JSON confirmation
    func clearPurchaseHistory(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let testerIdsArray = arguments["sandbox_tester_ids"]?.arrayValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'sandbox_tester_ids' is missing")],
                isError: true
            )
        }

        let testerIds = testerIdsArray.compactMap { value -> String? in
            guard let id = value.stringValue,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return id
        }

        guard !testerIds.isEmpty,
              testerIds.count == testerIdsArray.count,
              Set(testerIds).count == testerIds.count else {
            return CallTool.Result(
                content: [MCPContent.text("Error: 'sandbox_tester_ids' must contain unique, non-empty tester ID strings")],
                isError: true
            )
        }

        do {
            let resourceIds = testerIds.map { ASCResourceIdentifier(type: "sandboxTesters", id: $0) }

            let request = ClearPurchaseHistoryRequest(
                data: ClearPurchaseHistoryRequest.RequestData(
                    relationships: ClearPurchaseHistoryRequest.Relationships(
                        sandboxTesters: ClearPurchaseHistoryRequest.SandboxTestersRelationship(
                            data: resourceIds
                        )
                    )
                )
            )

            let response: ASCClearPurchaseHistoryResponse = try await httpClient.post(
                "/v2/sandboxTestersClearPurchaseHistoryRequest",
                body: request,
                as: ASCClearPurchaseHistoryResponse.self
            )

            let result = [
                "success": true,
                "request_id": response.data.id,
                "message": "Clear purchase history request created for \(testerIds.count) sandbox tester(s)"
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to clear purchase history: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatSandboxTester(_ tester: ASCSandboxTester) -> [String: Any] {
        return [
            "id": tester.id,
            "type": tester.type,
            "firstName": (tester.attributes?.firstName).jsonSafe,
            "lastName": (tester.attributes?.lastName).jsonSafe,
            "acAccountName": (tester.attributes?.acAccountName).jsonSafe,
            "territory": (tester.attributes?.territory).jsonSafe,
            "applePayCompatible": (tester.attributes?.applePayCompatible).jsonSafe,
            "interruptPurchases": (tester.attributes?.interruptPurchases).jsonSafe,
            "subscriptionRenewalRate": (tester.attributes?.subscriptionRenewalRate).jsonSafe
        ]
    }

    private static let subscriptionRenewalRates: Set<String> = [
        "MONTHLY_RENEWAL_EVERY_ONE_HOUR",
        "MONTHLY_RENEWAL_EVERY_THIRTY_MINUTES",
        "MONTHLY_RENEWAL_EVERY_FIFTEEN_MINUTES",
        "MONTHLY_RENEWAL_EVERY_FIVE_MINUTES",
        "MONTHLY_RENEWAL_EVERY_THREE_MINUTES"
    ]
}
