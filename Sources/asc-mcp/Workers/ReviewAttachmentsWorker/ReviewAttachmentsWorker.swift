import Foundation
import MCP

/// ReviewAttachmentsWorker manages app store review attachments with upload support
public final class ReviewAttachmentsWorker: Sendable {
    let httpClient: HTTPClient
    let uploadService: UploadService
    let deliveryPollAttempts: Int
    let deliveryPollIntervalNanoseconds: UInt64

    private static let allowedArguments: [String: Set<String>] = [
        "review_attachments_upload": ["review_detail_id", "file_path"],
        "review_attachments_get": ["attachment_id"],
        "review_attachments_delete": ["attachment_id", "confirm_attachment_id"],
        "review_attachments_list": ["review_detail_id", "limit", "next_url"]
    ]

    public init(httpClient: HTTPClient, uploadService: UploadService) {
        self.httpClient = httpClient
        self.uploadService = uploadService
        self.deliveryPollAttempts = 10
        self.deliveryPollIntervalNanoseconds = 1_000_000_000
    }

    init(
        httpClient: HTTPClient,
        uploadService: UploadService,
        deliveryPollAttempts: Int,
        deliveryPollIntervalNanoseconds: UInt64
    ) {
        self.httpClient = httpClient
        self.uploadService = uploadService
        self.deliveryPollAttempts = max(1, deliveryPollAttempts)
        self.deliveryPollIntervalNanoseconds = deliveryPollIntervalNanoseconds
    }

    /// Get list of available tools
    public func getTools() async -> [Tool] {
        return [
            uploadAttachmentTool(),
            getAttachmentTool(),
            deleteAttachmentTool(),
            listAttachmentsTool()
        ]
    }

    /// Handle tool calls (for WorkerManager routing)
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        if let allowed = Self.allowedArguments[params.name],
           let unknown = params.arguments?.keys.sorted().first(where: { !allowed.contains($0) }) {
            return MCPResult.error(
                "Unsupported parameter '\(unknown)' for tool '\(params.name)'"
            )
        }

        switch params.name {
        case "review_attachments_upload":
            return try await uploadAttachment(params)
        case "review_attachments_get":
            return try await getAttachment(params)
        case "review_attachments_delete":
            return try await deleteAttachment(params)
        case "review_attachments_list":
            return try await listAttachments(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
