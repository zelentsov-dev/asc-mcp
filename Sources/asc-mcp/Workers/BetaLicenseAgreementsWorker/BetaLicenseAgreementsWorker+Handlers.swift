import Foundation
import MCP

// MARK: - Tool Handlers
extension BetaLicenseAgreementsWorker {

    /// Lists beta license agreements with optional app filtering
    /// - Returns: JSON array of beta license agreements with agreement text
    func listBetaLicenseAgreements(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments

        do {
            let response: ASCBetaLicenseAgreementsResponse
            var queryParams: [String: String] = [:]

            if let appId = arguments?["app_id"]?.stringValue {
                queryParams["filter[app]"] = appId
            }
            if let limit = arguments?["limit"]?.intValue {
                queryParams["limit"] = String(min(max(limit, 1), 200))
            } else {
                queryParams["limit"] = "25"
            }

            if let nextUrl = try paginationURL(from: arguments?["next_url"]) {
                var requiredParameters = queryParams
                requiredParameters.removeValue(forKey: "limit")
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(
                        path: "/v1/betaLicenseAgreements",
                        requiredParameters: requiredParameters
                    ),
                    as: ASCBetaLicenseAgreementsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v1/betaLicenseAgreements",
                    parameters: queryParams,
                    as: ASCBetaLicenseAgreementsResponse.self
                )
            }

            let agreements = response.data.map { formatBetaLicenseAgreement($0) }

            var result: [String: Any] = [
                "success": true,
                "beta_license_agreements": agreements,
                "count": agreements.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list beta license agreements: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets a single beta license agreement by ID
    /// - Returns: JSON with beta license agreement details
    func getBetaLicenseAgreement(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let agreementId = arguments["beta_license_agreement_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'beta_license_agreement_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBetaLicenseAgreementResponse = try await httpClient.get(
                "/v1/betaLicenseAgreements/\(agreementId)",
                parameters: [:],
                as: ASCBetaLicenseAgreementResponse.self
            )

            let agreement = formatBetaLicenseAgreement(response.data)

            let result = [
                "success": true,
                "beta_license_agreement": agreement
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get beta license agreement: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Updates a beta license agreement text
    /// - Returns: JSON with updated beta license agreement details
    func updateBetaLicenseAgreement(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let agreementId = arguments["beta_license_agreement_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'beta_license_agreement_id' is missing")],
                isError: true
            )
        }

        do {
            let request = UpdateBetaLicenseAgreementRequest(
                data: UpdateBetaLicenseAgreementRequest.UpdateData(
                    id: agreementId,
                    attributes: UpdateBetaLicenseAgreementRequest.Attributes(
                        agreementText: arguments["agreement_text"]?.stringValue
                    )
                )
            )

            let response: ASCBetaLicenseAgreementResponse = try await httpClient.patch(
                "/v1/betaLicenseAgreements/\(agreementId)",
                body: request,
                as: ASCBetaLicenseAgreementResponse.self
            )

            let agreement = formatBetaLicenseAgreement(response.data)

            let result = [
                "success": true,
                "beta_license_agreement": agreement
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to update beta license agreement: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatBetaLicenseAgreement(_ agreement: ASCBetaLicenseAgreement) -> [String: Any] {
        return [
            "id": agreement.id,
            "type": agreement.type,
            "agreementText": (agreement.attributes?.agreementText).jsonSafe
        ]
    }
}
