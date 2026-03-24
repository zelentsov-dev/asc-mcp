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

            if let nextUrl = arguments?["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCSandboxTestersResponse.self)
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
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list sandbox testers: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'sandbox_tester_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateSandboxTesterRequest(
                data: UpdateSandboxTesterRequest.UpdateData(
                    id: sandboxTesterId,
                    attributes: UpdateSandboxTesterRequest.Attributes(
                        territory: arguments["territory"]?.stringValue,
                        interruptPurchases: arguments["interrupt_purchases"]?.boolValue,
                        subscriptionRenewalRate: arguments["subscription_renewal_rate"]?.stringValue
                    )
                )
            )

            let response: ASCSandboxTesterResponse = try await httpClient.patch(
                "/v2/sandboxTesters/\(sandboxTesterId)",
                body: request,
                as: ASCSandboxTesterResponse.self
            )

            let tester = formatSandboxTester(response.data)

            let result = [
                "success": true,
                "sandbox_tester": tester
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update sandbox tester: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'sandbox_tester_ids' is missing")],
                isError: true
            )
        }

        let testerIds = testerIdsArray.compactMap { $0.stringValue }

        guard !testerIds.isEmpty else {
            return CallTool.Result(
                content: [.text("Error: 'sandbox_tester_ids' must contain at least one tester ID")],
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

            let bodyData = try JSONEncoder().encode(request)
            _ = try await httpClient.post("/v2/sandboxTestersClearPurchaseHistoryRequest", body: bodyData)

            let result = [
                "success": true,
                "message": "Purchase history cleared for \(testerIds.count) sandbox tester(s)"
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to clear purchase history: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatSandboxTester(_ tester: ASCSandboxTester) -> [String: Any] {
        return [
            "id": tester.id,
            "type": tester.type,
            "firstName": tester.attributes.firstName.jsonSafe,
            "lastName": tester.attributes.lastName.jsonSafe,
            "acAccountName": tester.attributes.acAccountName.jsonSafe,
            "territory": tester.attributes.territory.jsonSafe,
            "applePayCompatible": tester.attributes.applePayCompatible.jsonSafe,
            "interruptPurchases": tester.attributes.interruptPurchases.jsonSafe,
            "subscriptionRenewalRate": tester.attributes.subscriptionRenewalRate.jsonSafe
        ]
    }
}
