import Foundation
import MCP

/// BuildProcessingWorker manages build processing states and encryption compliance
public final class BuildProcessingWorker: Sendable {
    let httpClient: HTTPClient
    
    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }
    
    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            getProcessingStateTool(),
            updateEncryptionTool(),
            getProcessingStatusTool(),
            checkReadinessTool()
        ]
    }

    /// Handle tool calls (for WorkerManager)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "builds_get_processing_state":
            return try await getProcessingState(params)
        case "builds_update_encryption":
            return try await updateEncryption(params)
        case "builds_get_processing_status":
            return try await getProcessingStatus(params)
        case "builds_check_readiness":
            return try await checkReadiness(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}