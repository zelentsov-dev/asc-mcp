import Foundation
import MCP

/// Manages export-compliance declarations, documents, and build linkage.
public final class ExportComplianceWorker: Sendable {
    let httpClient: HTTPClient
    let uploadService: UploadService
    let deliveryPollAttempts: Int
    let deliveryPollIntervalNanoseconds: UInt64

    /// Creates an export-compliance worker.
    /// - Parameters:
    ///   - httpClient: Authenticated App Store Connect client.
    ///   - uploadService: Service used for signed document transfers.
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

    /// Returns the export-compliance MCP tool definitions.
    /// - Returns: Eleven tools for declarations, documents, build linkage, and readiness.
    public func getTools() async -> [Tool] {
        [
            listDeclarationsTool(),
            getDeclarationTool(),
            createDeclarationTool(),
            createDocumentTool(),
            getDocumentTool(),
            updateDocumentTool(),
            uploadDocumentTool(),
            inspectDocumentTool(),
            getBuildDeclarationTool(),
            attachBuildDeclarationTool(),
            checkReleaseReadinessTool()
        ]
    }

    /// Routes an export-compliance MCP tool call.
    /// - Parameter params: MCP tool name and arguments.
    /// - Returns: Structured tool output or a structured error.
    /// - Throws: `MCPError.methodNotFound` for an unknown tool name.
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "export_compliance_list_declarations":
            return try await listDeclarations(params)
        case "export_compliance_get_declaration":
            return try await getDeclaration(params)
        case "export_compliance_create_declaration":
            return try await createDeclaration(params)
        case "export_compliance_create_document":
            return try await createDocument(params)
        case "export_compliance_get_document":
            return try await getDocument(params)
        case "export_compliance_update_document":
            return try await updateDocument(params)
        case "export_compliance_upload_document":
            return try await uploadDocument(params)
        case "export_compliance_inspect_document":
            return try await inspectDocument(params)
        case "export_compliance_get_build_declaration":
            return try await getBuildDeclaration(params)
        case "export_compliance_attach_build_declaration":
            return try await attachBuildDeclaration(params)
        case "export_compliance_check_release_readiness":
            return try await checkReleaseReadiness(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
