import Foundation
import MCP

/// Manages App Store review submissions and their heterogeneous review items.
public final class ReviewSubmissionsWorker: Sendable {
    let httpClient: HTTPClient
    private static let allowedArguments: [String: Set<String>] = [
        "review_submissions_list": [
            "app_id", "states", "platforms", "include", "item_limit", "limit", "next_url"
        ],
        "review_submissions_get": ["submission_id", "include", "item_limit"],
        "review_submissions_create": ["app_id", "platform"],
        "review_submissions_list_items": ["submission_id", "limit", "next_url"],
        "review_submissions_add_item": [
            "submission_id",
            "app_store_version_id",
            "app_custom_product_page_version_id",
            "app_store_version_experiment_v2_id",
            "app_event_id",
            "background_asset_version_id",
            "in_app_purchase_version_id",
            "subscription_version_id",
            "subscription_group_version_id"
        ],
        "review_submissions_update_item": ["submission_id", "item_id", "resolved", "removed"],
        "review_submissions_remove_item": ["submission_id", "item_id", "confirm_item_id"],
        "review_submissions_submit": ["submission_id"],
        "review_submissions_cancel": ["submission_id"]
    ]

    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    /// Returns the review submission tools exposed by this worker.
    /// - Returns: Nine tools for submission discovery, recovery, assembly, and state transitions.
    public func getTools() async -> [Tool] {
        [
            listSubmissionsTool(),
            getSubmissionTool(),
            createSubmissionTool(),
            listItemsTool(),
            addItemTool(),
            updateItemTool(),
            removeItemTool(),
            submitTool(),
            cancelTool()
        ]
    }

    /// Routes a review submission tool call to its handler.
    /// - Parameter params: MCP tool call parameters.
    /// - Returns: The handler result.
    /// - Throws: `MCPError.methodNotFound` for an unknown tool name.
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        if let allowed = Self.allowedArguments[params.name],
           let unknown = params.arguments?.keys.sorted().first(where: { !allowed.contains($0) }) {
            return MCPResult.error(
                "Unsupported parameter '\(unknown)' for tool '\(params.name)'"
            )
        }

        switch params.name {
        case "review_submissions_list":
            return try await listSubmissions(params)
        case "review_submissions_get":
            return try await getSubmission(params)
        case "review_submissions_create":
            return try await createSubmission(params)
        case "review_submissions_list_items":
            return try await listItems(params)
        case "review_submissions_add_item":
            return try await addItem(params)
        case "review_submissions_update_item":
            return try await updateItem(params)
        case "review_submissions_remove_item":
            return try await removeItem(params)
        case "review_submissions_submit":
            return try await submit(params)
        case "review_submissions_cancel":
            return try await cancel(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
