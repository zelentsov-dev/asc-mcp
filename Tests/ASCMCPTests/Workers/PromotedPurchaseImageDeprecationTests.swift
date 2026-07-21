import MCP
import Testing
@testable import asc_mcp

@Suite("Promoted Purchase Image Deprecation Tests")
struct PromotedPurchaseImageDeprecationTests {
    @Test("removed image tools return migration guidance without Apple requests")
    func removedImageToolsReturnMigrationGuidance() async throws {
        let transport = TestHTTPTransport(responses: [])
        let worker = try await makePromotedWorker(transport: transport)
        let invocations: [(String, [String: Value])] = [
            (
                "promoted_upload_image",
                ["promoted_purchase_id": .string("promoted-1"), "file_path": .string("/tmp/image.png")]
            ),
            ("promoted_get_image", ["image_id": .string("image-1")]),
            ("promoted_delete_image", ["image_id": .string("image-1")]),
            ("promoted_get_image_for_purchase", ["promoted_purchase_id": .string("promoted-1")])
        ]

        for (tool, arguments) in invocations {
            let result = try await worker.handleTool(
                CallTool.Parameters(name: tool, arguments: arguments)
            )

            #expect(result.isError == true)
            #expect(promotedDeprecationText(result).contains("no longer provides"))
            let details = try promotedDeprecationDetails(result)
            #expect(details["deprecated"] == .bool(true))
            #expect(details["tool"] == .string(tool))
            guard case .array(let replacements) = details["replacement_tools"] else {
                Issue.record("Expected replacement tool list")
                continue
            }
            #expect(replacements.contains(.string("iap_upload_version_image")))
            #expect(replacements.contains(.string("subscriptions_upload_version_image")))
            #expect(!replacements.contains(.string("iap_upload_image")))
            #expect(!replacements.contains(.string("subscriptions_upload_image")))
        }

        #expect(await transport.requestCount() == 0)
    }

    @Test("removed image tool descriptions disclose deprecation")
    func removedImageToolDescriptionsDiscloseDeprecation() async throws {
        let worker = try await makePromotedWorker(
            transport: TestHTTPTransport(responses: [])
        )
        let imageTools = await worker.getTools().filter { $0.name.contains("image") }

        #expect(imageTools.count == 4)
        for tool in imageTools {
            #expect(tool.description?.contains("Deprecated") == true)
        }

        for toolName in ["promoted_get_image", "promoted_delete_image"] {
            let tool = try #require(imageTools.first { $0.name == toolName })
            let properties = try promotedDeprecationObject(
                try promotedDeprecationObject(tool.inputSchema)["properties"]
            )
            let imageID = try promotedDeprecationObject(properties["image_id"])
            #expect(imageID["pattern"] == .string(#"^(?!\.{1,2}$)[A-Za-z0-9._~-]+$"#))
        }

        let upload = try #require(imageTools.first { $0.name == "promoted_upload_image" })
        let uploadProperties = try promotedDeprecationObject(
            try promotedDeprecationObject(upload.inputSchema)["properties"]
        )
        let filePath = try promotedDeprecationObject(uploadProperties["file_path"])
        #expect(filePath["minLength"] == .int(1))
        #expect(filePath["pattern"] == .string(#"^\S(?:[\s\S]*\S)?$"#))
    }
}

private func makePromotedWorker(
    transport: TestHTTPTransport
) async throws -> PromotedPurchasesWorker {
    let client = await HTTPClient(
        jwtService: try TestFactory.makeJWTService(),
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    return PromotedPurchasesWorker(
        httpClient: client,
        uploadService: UploadService()
    )
}

private func promotedDeprecationText(_ result: CallTool.Result) -> String {
    for content in result.content {
        if case .text(let text, _, _) = content {
            return text
        }
    }
    return ""
}

private func promotedDeprecationDetails(
    _ result: CallTool.Result
) throws -> [String: Value] {
    guard case .object(let root) = result.structuredContent,
          case .object(let details) = root["details"] else {
        Issue.record("Expected structured deprecation details")
        throw PromotedPurchaseImageDeprecationTestError.missingDetails
    }
    return details
}

private func promotedDeprecationObject(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected schema object")
        throw PromotedPurchaseImageDeprecationTestError.missingDetails
    }
    return object
}

private enum PromotedPurchaseImageDeprecationTestError: Error {
    case missingDetails
}
