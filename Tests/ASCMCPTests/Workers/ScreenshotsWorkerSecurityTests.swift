import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Screenshots Worker Security Tests")
struct ScreenshotsWorkerSecurityTests {
    @Test("screenshot and preview results omit upload credentials")
    func resultsOmitUploadCredentials() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: Self.screenshotResponse),
            .init(statusCode: 200, body: Self.previewResponse)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = ScreenshotsWorker(httpClient: client, uploadService: UploadService())

        let screenshot = try await worker.handleTool(
            CallTool.Parameters(
                name: "screenshots_get",
                arguments: ["screenshot_id": .string("screenshot-1")]
            )
        )
        try assertSafeUploadProjection(
            screenshot,
            resourceKey: "screenshot",
            forbiddenValues: Self.screenshotSecrets
        )

        let preview = try await worker.handleTool(
            CallTool.Parameters(
                name: "screenshots_get_preview",
                arguments: ["preview_id": .string("preview-1")]
            )
        )
        try assertSafeUploadProjection(
            preview,
            resourceKey: "preview",
            forbiddenValues: Self.previewSecrets
        )
    }

    private func assertSafeUploadProjection(
        _ result: CallTool.Result,
        resourceKey: String,
        forbiddenValues: [String]
    ) throws {
        #expect(result.isError == nil)

        let text = textContent(result)
        let structured = try #require(result.structuredContent)
        let structuredData = try JSONEncoder().encode(structured)
        let structuredText = try #require(String(data: structuredData, encoding: .utf8))

        for forbidden in forbiddenValues {
            #expect(!text.contains(forbidden))
            #expect(!structuredText.contains(forbidden))
        }

        let root = try #require(structured.objectValue)
        let resource = try #require(root[resourceKey]?.objectValue)
        #expect(resource["uploadOperationCount"] == .int(1))

        let operations = try #require(resource["uploadOperations"]?.arrayValue)
        let operation = try #require(operations.first?.objectValue)
        #expect(operation["method"] == .string("PUT"))
        #expect(operation["length"] == .int(4096))
        #expect(operation["offset"] == .int(0))
        #expect(operation["url"] == nil)
        #expect(operation["requestHeaders"] == nil)
    }

    private func textContent(_ result: CallTool.Result) -> String {
        result.content.compactMap { content in
            if case .text(let text, _, _) = content {
                return text
            }
            return nil
        }.joined(separator: "\n")
    }

    private static let screenshotSecrets = [
        "upload-screenshot.example.test",
        "screenshot-query-signature",
        "screenshot-query-token",
        "screenshot-header-secret",
        "screenshot-header-token",
        "X-Amz-Signature",
        "Authorization",
        "x-amz-security-token",
        "requestHeaders"
    ]

    private static let previewSecrets = [
        "upload-preview.example.test",
        "preview-query-signature",
        "preview-query-token",
        "preview-header-secret",
        "preview-header-token",
        "X-Amz-Signature",
        "Authorization",
        "x-amz-security-token",
        "requestHeaders"
    ]

    private static let screenshotResponse = #"""
    {
      "data": {
        "type": "appScreenshots",
        "id": "screenshot-1",
        "attributes": {
          "fileName": "screenshot.png",
          "fileSize": 4096,
          "uploadOperations": [{
            "method": "PUT",
            "url": "https://upload-screenshot.example.test/chunk?X-Amz-Signature=screenshot-query-signature&X-Amz-Security-Token=screenshot-query-token",
            "length": 4096,
            "offset": 0,
            "requestHeaders": [
              {"name": "Authorization", "value": "Bearer screenshot-header-secret"},
              {"name": "x-amz-security-token", "value": "screenshot-header-token"}
            ]
          }]
        }
      }
    }
    """#

    private static let previewResponse = #"""
    {
      "data": {
        "type": "appPreviews",
        "id": "preview-1",
        "attributes": {
          "fileName": "preview.mp4",
          "fileSize": 4096,
          "mimeType": "video/mp4",
          "uploadOperations": [{
            "method": "PUT",
            "url": "https://upload-preview.example.test/chunk?X-Amz-Signature=preview-query-signature&X-Amz-Security-Token=preview-query-token",
            "length": 4096,
            "offset": 0,
            "requestHeaders": [
              {"name": "Authorization", "value": "Bearer preview-header-secret"},
              {"name": "x-amz-security-token", "value": "preview-header-token"}
            ]
          }]
        }
      }
    }
    """#
}

private extension Value {
    var objectValue: [String: Value]? {
        guard case .object(let object) = self else {
            return nil
        }
        return object
    }
}
