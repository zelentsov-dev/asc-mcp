import Foundation
import MCP

/// ReviewAttachmentsWorker manages app store review attachments with upload support
public final class ReviewAttachmentsWorker: Sendable {
    let httpClient: HTTPClient
    let uploadService: UploadService

    public init(httpClient: HTTPClient, uploadService: UploadService) {
        self.httpClient = httpClient
        self.uploadService = uploadService
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
