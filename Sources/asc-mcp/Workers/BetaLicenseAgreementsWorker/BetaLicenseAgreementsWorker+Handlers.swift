import Foundation
import MCP

// MARK: - Tool Handlers
extension BetaLicenseAgreementsWorker {

    /// Lists beta license agreements with optional app filtering
    /// - Returns: JSON array of beta license agreements with agreement text
    func listBetaLicenseAgreements(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments

        let limit: Int
        if let value = arguments?["limit"] {
            guard let parsed = value.intValue, (1...200).contains(parsed) else {
                return MCPResult.error("'limit' must be an integer from 1 through 200")
            }
            limit = parsed
        } else {
            limit = 25
        }

        do {
            let response: ASCBetaLicenseAgreementsResponse
            var queryParams: [String: String] = [:]

            if let appIDs = try commaSeparatedAppIDs(arguments?["app_id"]) {
                queryParams["filter[app]"] = appIDs
            }
            queryParams["limit"] = String(limit)

            if let nextUrl = try paginationURL(from: arguments?["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(
                        path: "/v1/betaLicenseAgreements",
                        query: queryParams
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
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }
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
                "/v1/betaLicenseAgreements/\(try ASCPathSegment.encode(agreementId))",
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

        guard let agreementTextValue = arguments["agreement_text"] else {
            return MCPResult.error("At least one update field is required: agreement_text")
        }
        let agreementText: JSONValue
        if agreementTextValue.isNull {
            agreementText = .null
        } else if let value = agreementTextValue.stringValue {
            agreementText = .string(value)
        } else {
            return MCPResult.error("Parameter 'agreement_text' must be a string or null")
        }

        do {
            let request = UpdateBetaLicenseAgreementRequest(
                data: UpdateBetaLicenseAgreementRequest.UpdateData(
                    id: agreementId,
                    attributes: UpdateBetaLicenseAgreementRequest.Attributes(
                        agreementText: agreementText
                    )
                )
            )

            let response: ASCBetaLicenseAgreementResponse = try await httpClient.patch(
                "/v1/betaLicenseAgreements/\(try ASCPathSegment.encode(agreementId))",
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
            return MCPResult.error(error, prefix: "Failed to update beta license agreement")
        }
    }

    // MARK: - Formatting

    private func formatBetaLicenseAgreement(_ agreement: ASCBetaLicenseAgreement) -> [String: Any] {
        return [
            "id": agreement.id,
            "type": agreement.type,
            "agreementText": (agreement.attributes?.agreementText).jsonSafe,
            "appId": (agreement.relationships?.app?.data?.id).jsonSafe,
            "appRelatedURL": (agreement.relationships?.app?.links?.related).jsonSafe
        ]
    }

    private func commaSeparatedAppIDs(_ value: Value?) throws -> String? {
        guard let value else {
            return nil
        }
        let ids: [String]
        if let string = value.stringValue {
            ids = [string]
        } else if let values = value.arrayValue {
            guard !values.isEmpty,
                  values.allSatisfy({ $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }) else {
                throw BetaLicenseArgumentError("app_id must be a non-empty string or array of non-empty strings")
            }
            ids = values.compactMap(\.stringValue)
        } else {
            throw BetaLicenseArgumentError("app_id must be a non-empty string or array of non-empty strings")
        }
        guard ids.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw BetaLicenseArgumentError("app_id must be a non-empty string or array of non-empty strings")
        }
        guard Set(ids).count == ids.count,
              ids.allSatisfy({ !$0.contains(",") }) else {
            throw BetaLicenseArgumentError("app_id must contain unique values without commas")
        }
        return ids.joined(separator: ",")
    }
}

private struct BetaLicenseArgumentError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
