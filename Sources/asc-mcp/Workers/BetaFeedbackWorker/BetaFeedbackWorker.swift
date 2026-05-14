import Foundation
import MCP

/// Reads and manages TestFlight beta feedback crash and screenshot submissions.
public final class BetaFeedbackWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get list of available beta feedback tools.
    /// - Returns: Tool definitions for crash feedback, screenshot feedback, crash logs, and cleanup.
    public func getTools() async -> [Tool] {
        [
            listCrashesTool(),
            getCrashTool(),
            getCrashLogTool(),
            getCrashLogByIDTool(),
            deleteCrashTool(),
            listScreenshotsTool(),
            getScreenshotTool(),
            deleteScreenshotTool()
        ]
    }

    /// Handle beta feedback tool calls.
    /// - Parameter params: MCP tool call parameters.
    /// - Returns: MCP tool result with JSON text and structured content.
    /// - Throws: `MCPError.methodNotFound` for unknown tool names.
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "beta_feedback_list_crashes":
            return try await listCrashes(params)
        case "beta_feedback_get_crash":
            return try await getCrash(params)
        case "beta_feedback_get_crash_log":
            return try await getCrashLog(params)
        case "beta_feedback_get_crash_log_by_id":
            return try await getCrashLogByID(params)
        case "beta_feedback_delete_crash":
            return try await deleteCrash(params)
        case "beta_feedback_list_screenshots":
            return try await listScreenshots(params)
        case "beta_feedback_get_screenshot":
            return try await getScreenshot(params)
        case "beta_feedback_delete_screenshot":
            return try await deleteScreenshot(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
