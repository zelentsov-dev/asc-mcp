import Foundation
import MCP

// MARK: - Tool Handlers
extension CompaniesWorker {

    /// Masks a sensitive value, showing only the last few characters
    private func masked(_ value: String, visibleSuffix: Int = 4) -> String {
        Redactor.maskIdentifier(value, visibleSuffix: visibleSuffix)
    }

    /// Human-readable description of the API key type for display.
    private func keyTypeDescription(_ company: Company) -> String {
        if let issuerID = company.issuerID {
            return "Team Key (Issuer: \(masked(issuerID)))"
        } else {
            return "Individual Key"
        }
    }
    
    /// Lists all available companies configured in the MCP server
    /// - Returns: Formatted list of companies with their IDs, names, and active status
    /// - Throws: CallTool.Result with warning if no companies configured
    func listCompanies(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let companies = await manager.listCompanies()
        let current = try? await manager.getCurrentCompany()

        if companies.isEmpty {
            return MCPResult.error("No companies found. Please configure companies.json file.")
        }

        var result = "**Available Companies**\n\n"
        var structuredCompanies: [Value] = []

        for (index, company) in companies.enumerated() {
            let isCurrent = company.id == current?.id
            let status = isCurrent ? " **[ACTIVE]**" : ""

            result += "\(index + 1). **\(company.name)**\(status)\n"
            result += "   • ID: `\(company.id)`\n"
            result += "   • Key ID: \(masked(company.keyID))\n"
            result += "   • Type: \(keyTypeDescription(company))\n"
            result += "\n"

            structuredCompanies.append(.object([
                "id": .string(company.id),
                "name": .string(company.name),
                "keyID": .string(masked(company.keyID)),
                "isCurrent": .bool(isCurrent)
            ]))
        }

        if let current = current {
            result += "---\n"
            result += "**Current Active:** \(current.name)\n"
        } else {
            result += "---\n"
            result += "Warning: No company selected. Use `company_switch` to select one.\n"
        }

        return MCPResult.json(
            .object([
                "success": .bool(true),
                "companies": .array(structuredCompanies),
                "currentCompanyId": current.map { .string($0.id) } ?? .null
            ]),
            text: result
        )
    }

    /// Switches to a different company for all subsequent API operations
    /// - Returns: Confirmation with switched company details
    /// - Throws: CallTool.Result with error if company parameter missing or switch fails
    func switchCompany(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let companyValue = arguments["company"],
              let companyIdOrName = companyValue.stringValue else {
            return MCPResult.error("Required parameter 'company' (ID or name)")
        }

        do {
            let company = try await manager.switchToCompany(companyIdOrName)

            let result = """
            **Switched to Company**

            **\(company.name)**
            • ID: `\(company.id)`
            • Key ID: \(masked(company.keyID))
            • Type: \(keyTypeDescription(company))

            All subsequent API calls will use this company's credentials.
            """

            return MCPResult.json(
                .object([
                    "success": .bool(true),
                    "company": .object([
                        "id": .string(company.id),
                        "name": .string(company.name),
                        "keyID": .string(masked(company.keyID)),
                        "issuerID": company.issuerID.map { .string(masked($0)) } ?? .null,
                        "keyType": .string(company.isIndividualKey ? "individual" : "team")
                    ])
                ]),
                text: result
            )

        } catch {
            return MCPResult.error("Error switching company: \(error.localizedDescription)")
        }
    }

    /// Gets information about the currently active company
    /// - Returns: Details of the current company including ID, name, and credentials info
    /// - Throws: CallTool.Result with warning if no company is currently selected
    func getCurrentCompany(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let company = try? await manager.getCurrentCompany() else {
            return MCPResult.json(
                .object([
                    "success": .bool(false),
                    "currentCompany": .null
                ]),
                text: "Warning: No company currently selected.\n\nUse `company_list` to see available companies and `company_switch` to select one."
            )
        }

        let result = """
        **Current Active Company**
        
        **\(company.name)**
        • ID: `\(company.id)`
        • NAME: \(company.name)
        • Key ID: \(masked(company.keyID))
        • Type: \(keyTypeDescription(company))
        """

        return MCPResult.json(
            .object([
                "success": .bool(true),
                "currentCompany": .object([
                    "id": .string(company.id),
                    "name": .string(company.name),
                    "keyID": .string(masked(company.keyID)),
                    "issuerID": company.issuerID.map { .string(masked($0)) } ?? .null,
                    "keyType": .string(company.isIndividualKey ? "individual" : "team")
                ])
            ]),
            text: result
        )
    }
}
