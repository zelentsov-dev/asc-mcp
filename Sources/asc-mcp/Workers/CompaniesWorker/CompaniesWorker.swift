import Foundation
import MCP

/// Worker for managing multiple companies
public final class CompaniesWorker: Sendable {

    let manager: CompaniesManager
    
    public init(
        manager: CompaniesManager
    ) {
        self.manager = manager
    }
    
    public func getTools() async -> [Tool] {
        return [
            listCompaniesTool(),
            switchCompanyTool(),
            currentCompanyTool()
        ]
    }
    
    /// Handle tool calls (for WorkerManager)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "company_list":
            return try await listCompanies(params)
        case "company_switch":
            return try await switchCompany(params)
        case "company_current":
            return try await getCurrentCompany(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }

}
