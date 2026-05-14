import Foundation
import MCP

/// Manages App Store accessibility declarations for each supported device family.
public final class AccessibilityWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available accessibility declaration tools.
    /// - Returns: Tool definitions for listing, reading, creating, updating, publishing, and deleting declarations.
    public func getTools() async -> [Tool] {
        [
            listDeclarationsTool(),
            getDeclarationTool(),
            createDeclarationTool(),
            updateDeclarationTool(),
            deleteDeclarationTool(),
            listDeclarationRelationshipsTool()
        ]
    }

    /// Handle accessibility declaration tool calls.
    /// - Parameter params: MCP tool call parameters.
    /// - Returns: MCP tool result with JSON text and structured content when available.
    /// - Throws: `MCPError.methodNotFound` for unknown tool names.
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "accessibility_list":
            return try await listDeclarations(params)
        case "accessibility_get":
            return try await getDeclaration(params)
        case "accessibility_create":
            return try await createDeclaration(params)
        case "accessibility_update":
            return try await updateDeclaration(params)
        case "accessibility_delete":
            return try await deleteDeclaration(params)
        case "accessibility_list_relationships":
            return try await listDeclarationRelationships(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
