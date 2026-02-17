import Foundation
import MCP

// MARK: - Tool Handlers
extension CompaniesWorker {

    /// Masks a sensitive value, showing only the last few characters
    private func masked(_ value: String, visibleSuffix: Int = 4) -> String {
        guard value.count > visibleSuffix else { return value }
        return "****" + value.suffix(visibleSuffix)
    }
    
    /// Lists all available companies configured in the MCP server
    /// - Returns: Formatted list of companies with their IDs, names, and active status
    /// - Throws: CallTool.Result with warning if no companies configured
    func listCompanies(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let companies = await manager.listCompanies()
        let current = try? await manager.getCurrentCompany()

        if companies.isEmpty {
            return CallTool.Result(content: [
                .text("Error: No companies found. Please configure companies.json file.")
            ])
        }

        var result = "**Available Companies**\n\n"

        for (index, company) in companies.enumerated() {
            let isCurrent = company.id == current?.id
            let status = isCurrent ? " **[ACTIVE]**" : ""

            result += "\(index + 1). **\(company.name)**\(status)\n"
            result += "   • ID: `\(company.id)`\n"
            result += "   • Key ID: \(company.keyID)\n"


            result += "\n"
        }

        if let current = current {
            result += "---\n"
            result += "**Current Active:** \(current.name)\n"
        } else {
            result += "---\n"
            result += "Warning: No company selected. Use `company_switch` to select one.\n"
        }

        return CallTool.Result(content: [.text(result)])
    }

    /// Switches to a different company for all subsequent API operations
    /// - Returns: Confirmation with switched company details
    /// - Throws: CallTool.Result with error if company parameter missing or switch fails
    func switchCompany(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let companyValue = arguments["company"],
              let companyIdOrName = companyValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'company' (ID or name)")],
                isError: true
            )
        }

        do {
            let company = try await manager.switchToCompany(companyIdOrName)

            let result = """
            **Switched to Company**

            **\(company.name)**
            • ID: `\(company.id)`
            • Key ID: \(company.keyID)
            • Issuer ID: \(masked(company.issuerID))

            All subsequent API calls will use this company's credentials.
            """

            return CallTool.Result(content: [.text(result)])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Error switching company: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets information about the currently active company
    /// - Returns: Details of the current company including ID, name, and credentials info
    /// - Throws: CallTool.Result with warning if no company is currently selected
    func getCurrentCompany(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let company = try? await manager.getCurrentCompany() else {
            return CallTool.Result(content: [
                .text("Warning: No company currently selected.\n\nUse `company_list` to see available companies and `company_switch` to select one.")
            ])
        }

        let result = """
        **Current Active Company**
        
        **\(company.name)**
        • ID: `\(company.id)`
        • NAME: \(company.name)
        • Key ID: \(company.keyID)
        • Issuer ID: \(masked(company.issuerID))
        """

        return CallTool.Result(content: [.text(result)])
    }
}
