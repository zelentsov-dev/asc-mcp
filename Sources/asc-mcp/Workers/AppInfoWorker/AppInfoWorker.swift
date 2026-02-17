//
//  AppInfoWorker.swift
//  asc-mcp
//
//  App info and localizations management for App Store Connect
//

import Foundation
import MCP

/// AppInfoWorker manages app info and localizations (subtitle, privacy URL) in App Store Connect
public final class AppInfoWorker: Sendable {
    let httpClient: HTTPClient

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Get all available tools for app info management
    public func getTools() async -> [Tool] {
        return [
            listAppInfosTool(),
            getAppInfoTool(),
            updateAppInfoTool(),
            listAppInfoLocalizationsTool(),
            updateAppInfoLocalizationTool(),
            createAppInfoLocalizationTool()
        ]
    }

    /// Handle tool call for app info operations
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "app_info_list":
            return try await listAppInfos(params)
        case "app_info_get":
            return try await getAppInfo(params)
        case "app_info_update":
            return try await updateAppInfo(params)
        case "app_info_list_localizations":
            return try await listAppInfoLocalizations(params)
        case "app_info_update_localization":
            return try await updateAppInfoLocalization(params)
        case "app_info_create_localization":
            return try await createAppInfoLocalization(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
