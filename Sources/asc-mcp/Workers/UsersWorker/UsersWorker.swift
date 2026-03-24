import Foundation
import MCP

/// UsersWorker manages team members and invitations in App Store Connect
public final class UsersWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            listUsersTool(),
            getUserTool(),
            updateUserTool(),
            removeUserTool(),
            inviteUserTool(),
            listInvitationsTool(),
            cancelInvitationTool(),
            listVisibleAppsTool(),
            addVisibleAppsTool(),
            removeVisibleAppsTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "users_list":
            return try await listUsers(params)
        case "users_get":
            return try await getUser(params)
        case "users_update":
            return try await updateUser(params)
        case "users_remove":
            return try await removeUser(params)
        case "users_invite":
            return try await inviteUser(params)
        case "users_list_invitations":
            return try await listInvitations(params)
        case "users_cancel_invitation":
            return try await cancelInvitation(params)
        case "users_list_visible_apps":
            return try await listVisibleApps(params)
        case "users_add_visible_apps":
            return try await addVisibleApps(params)
        case "users_remove_visible_apps":
            return try await removeVisibleApps(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
