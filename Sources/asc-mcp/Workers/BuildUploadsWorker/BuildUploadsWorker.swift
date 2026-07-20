import Foundation
import MCP

public final class BuildUploadsWorker: Sendable {
    let httpClient: HTTPClient
    let uploadService: UploadService
    let pollAttempts: Int
    let pollIntervalNanoseconds: UInt64
    let maxTransferAttempts: Int
    let transferRetryDelayNanoseconds: UInt64

    private static let allowedArguments: [String: Set<String>] = [
        "build_uploads_list": [
            "app_id", "short_version_strings", "build_versions", "platforms", "states", "sort",
            "fields_build_uploads", "fields_builds", "fields_build_upload_files", "include",
            "include_sensitive_details", "limit", "next_url"
        ],
        "build_uploads_get": [
            "build_upload_id", "fields_build_uploads", "fields_builds", "fields_build_upload_files",
            "include", "include_sensitive_details"
        ],
        "build_uploads_create": ["app_id", "short_version", "build_version", "platform"],
        "build_uploads_delete": ["build_upload_id", "confirm_build_upload_id"],
        "build_uploads_list_files": [
            "build_upload_id", "fields_build_upload_files", "include_sensitive_details", "limit", "next_url"
        ],
        "build_uploads_get_file": ["file_id", "fields_build_upload_files", "include_sensitive_details"],
        "build_uploads_reserve_file": [
            "build_upload_id", "asset_type", "file_name", "file_size", "uti", "include_sensitive_details"
        ],
        "build_uploads_commit_file": ["file_id", "source_file_checksums", "uploaded"],
        "build_uploads_upload_file": [
            "build_upload_id", "file_id", "file_path", "expected_md5", "asset_type", "uti",
            "max_transfer_attempts"
        ],
        "build_uploads_upload": [
            "app_id", "file_path", "short_version", "build_version", "platform", "asset_type", "uti",
            "max_transfer_attempts"
        ]
    ]

    /// Creates a build-upload worker backed by authenticated ASC requests and presigned transfers.
    /// - Parameters:
    ///   - httpClient: Authenticated App Store Connect API client.
    ///   - uploadService: Service that sends immutable snapshots to Apple's presigned URLs.
    public init(httpClient: HTTPClient, uploadService: UploadService) {
        self.httpClient = httpClient
        self.uploadService = uploadService
        self.pollAttempts = 10
        self.pollIntervalNanoseconds = 1_000_000_000
        self.maxTransferAttempts = 3
        self.transferRetryDelayNanoseconds = 250_000_000
    }

    init(
        httpClient: HTTPClient,
        uploadService: UploadService,
        pollAttempts: Int,
        pollIntervalNanoseconds: UInt64,
        maxTransferAttempts: Int,
        transferRetryDelayNanoseconds: UInt64
    ) {
        self.httpClient = httpClient
        self.uploadService = uploadService
        self.pollAttempts = max(1, pollAttempts)
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.maxTransferAttempts = max(1, maxTransferAttempts)
        self.transferRetryDelayNanoseconds = transferRetryDelayNanoseconds
    }

    /// Returns Build Upload and Build Upload File tools.
    /// - Returns: Ten tools for direct resource access and safe compound upload workflows.
    public func getTools() async -> [Tool] {
        [
            listBuildUploadsTool(),
            getBuildUploadTool(),
            createBuildUploadTool(),
            deleteBuildUploadTool(),
            listBuildUploadFilesTool(),
            getBuildUploadFileTool(),
            reserveBuildUploadFileTool(),
            commitBuildUploadFileTool(),
            uploadBuildFileTool(),
            uploadBuildTool()
        ]
    }

    /// Routes a Build Upload tool call to its handler.
    /// - Parameter params: MCP tool name and arguments.
    /// - Returns: Structured Build Upload result or error content.
    /// - Throws: `MCPError.methodNotFound` for unknown tool names.
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        if let allowed = Self.allowedArguments[params.name],
           let unknown = params.arguments?.keys.sorted().first(where: { !allowed.contains($0) }) {
            return MCPResult.error("Unsupported parameter '\(unknown)' for tool '\(params.name)'")
        }

        switch params.name {
        case "build_uploads_list":
            return try await listBuildUploads(params)
        case "build_uploads_get":
            return try await getBuildUpload(params)
        case "build_uploads_create":
            return try await createBuildUpload(params)
        case "build_uploads_delete":
            return try await deleteBuildUpload(params)
        case "build_uploads_list_files":
            return try await listBuildUploadFiles(params)
        case "build_uploads_get_file":
            return try await getBuildUploadFile(params)
        case "build_uploads_reserve_file":
            return try await reserveBuildUploadFile(params)
        case "build_uploads_commit_file":
            return try await commitBuildUploadFile(params)
        case "build_uploads_upload_file":
            return try await uploadBuildFile(params)
        case "build_uploads_upload":
            return try await uploadBuild(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}
