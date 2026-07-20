import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("App Store Connect Path Segment Tests")
struct ASCPathSegmentTests {
    @Test("opaque identifiers are encoded exactly once")
    func opaqueIdentifiersAreEncodedExactlyOnce() throws {
        #expect(try ASCPathSegment.encode("opaque_ID-123.~") == "opaque_ID-123.~")
        #expect(try ASCPathSegment.encode("opaque:id with ü") == "opaque%3Aid%20with%20%C3%BC")
    }

    @Test("ambiguous or scope-changing identifiers are rejected")
    func ambiguousIdentifiersAreRejected() {
        let invalidValues = [
            "",
            ".",
            "..",
            "parent/child",
            "parent\\child",
            "item?include=apps",
            "item#fragment",
            "item\u{0000}control",
            "%2Fapps",
            "%2e%2e",
            "%252Fapps"
        ]

        for value in invalidValues {
            #expect(throws: ASCError.self) {
                try ASCPathSegment.encode(value)
            }
        }
    }

    @Test("endpoint validation rejects canonicalization ambiguity")
    func endpointValidationRejectsCanonicalizationAmbiguity() {
        let invalidEndpoints = [
            "/v1/apps/",
            "/v1/apps//victim",
            "/v1/apps/./victim",
            "/v1/apps/../victim",
            "/v1/apps/item?include=victim",
            "/v1/apps/item#fragment",
            "/v1/apps/item\\victim",
            "/v1/apps/%2Fvictim",
            "/v1/apps/%2evictim",
            "/v1/apps/%252Fvictim"
        ]

        for endpoint in invalidEndpoints {
            #expect(throws: ASCError.self) {
                try validatedASCAPIEndpoint(endpoint)
            }
        }
    }

    @Test("HTTP client rejects an unsafe endpoint before authentication or transport")
    func clientRejectsUnsafeEndpointBeforeTransport() async throws {
        let transport = TestHTTPTransport(responses: [])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )

        await #expect(throws: ASCError.self) {
            try await client.delete("/v1/apps/safe/../victim")
        }
        #expect(await transport.requestCount() == 0)
    }

    @Test("HTTP client preserves one encoded opaque path segment")
    func clientPreservesEncodedOpaqueSegment() async throws {
        let transport = TestHTTPTransport(responses: [
            .init(statusCode: 200, body: #"{"data":[]}"#)
        ])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let segment = try ASCPathSegment.encode("opaque:id with ü")

        _ = try await client.get("/v1/apps/\(segment)")

        let request = try #require(await transport.recordedRequests().first)
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        #expect(components.percentEncodedPath == "/v1/apps/opaque%3Aid%20with%20%C3%BC")
    }
}

@Suite("Worker Path Segment Safety Tests")
struct WorkerPathSegmentSafetyTests {
    @Test("destructive workers reject scope-changing identifiers without a request")
    func destructiveWorkersRejectUnsafeIdentifiers() async throws {
        let transport = TestHTTPTransport(responses: [])
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )

        let iapResult = try await InAppPurchasesWorker(
            httpClient: client,
            uploadService: UploadService()
        ).handleTool(CallTool.Parameters(
            name: "iap_delete",
            arguments: ["iap_id": .string("../../apps/victim")]
        ))
        #expect(iapResult.isError == true)

        let subscriptionResult = try await SubscriptionsWorker(
            httpClient: client,
            uploadService: UploadService()
        ).handleTool(CallTool.Parameters(
            name: "subscriptions_delete",
            arguments: ["subscription_id": .string("%2Fapps%2Fvictim")]
        ))
        #expect(subscriptionResult.isError == true)

        let attachmentResult = try await ReviewAttachmentsWorker(
            httpClient: client,
            uploadService: UploadService()
        ).handleTool(CallTool.Parameters(
            name: "review_attachments_delete",
            arguments: ["attachment_id": .string("attachment?include=apps")]
        ))
        #expect(attachmentResult.isError == true)

        let screenshotResult = try await ScreenshotsWorker(
            httpClient: client,
            uploadService: UploadService()
        ).handleTool(CallTool.Parameters(
            name: "screenshots_delete",
            arguments: ["screenshot_id": .string("screenshot#fragment")]
        ))
        #expect(screenshotResult.isError == true)

        #expect(await transport.requestCount() == 0)
    }

    @Test("worker endpoint interpolation requires path-segment encoding")
    func workerEndpointInterpolationRequiresEncoding() throws {
        let workersURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/asc-mcp/Workers", isDirectory: true)
        let enumerator = FileManager.default.enumerator(
            at: workersURL,
            includingPropertiesForKeys: nil
        )
        let unsafeInterpolation = try NSRegularExpression(
            pattern: #""/v[12]/[^"\n]*\\\((?!try ASCPathSegment\.encode)"#
        )
        var violations: [String] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            guard unsafeInterpolation.firstMatch(in: source, range: range) != nil else { continue }
            violations.append(fileURL.path.replacingOccurrences(
                of: FileManager.default.currentDirectoryPath + "/",
                with: ""
            ))
        }

        #expect(
            violations.isEmpty,
            "Dynamic App Store Connect path segments must use ASCPathSegment.encode: \(violations)"
        )
    }
}
