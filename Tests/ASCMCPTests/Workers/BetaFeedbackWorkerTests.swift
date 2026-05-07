import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Beta Feedback Worker Tests")
struct BetaFeedbackWorkerTests {
    @Test("missing required parameters return isError")
    func missingRequiredParametersReturnErrors() async throws {
        let worker = BetaFeedbackWorker(httpClient: try await TestFactory.makeHTTPClient())

        let listCrashes = try await worker.handleTool(CallTool.Parameters(name: "beta_feedback_list_crashes", arguments: nil))
        let getCrash = try await worker.handleTool(CallTool.Parameters(name: "beta_feedback_get_crash", arguments: nil))
        let getCrashLog = try await worker.handleTool(CallTool.Parameters(name: "beta_feedback_get_crash_log", arguments: nil))
        let getCrashLogByID = try await worker.handleTool(CallTool.Parameters(name: "beta_feedback_get_crash_log_by_id", arguments: nil))
        let deleteCrash = try await worker.handleTool(CallTool.Parameters(name: "beta_feedback_delete_crash", arguments: nil))
        let listScreenshots = try await worker.handleTool(CallTool.Parameters(name: "beta_feedback_list_screenshots", arguments: nil))
        let getScreenshot = try await worker.handleTool(CallTool.Parameters(name: "beta_feedback_get_screenshot", arguments: nil))
        let deleteScreenshot = try await worker.handleTool(CallTool.Parameters(name: "beta_feedback_delete_screenshot", arguments: nil))

        #expect(listCrashes.isError == true)
        #expect(getCrash.isError == true)
        #expect(getCrashLog.isError == true)
        #expect(getCrashLogByID.isError == true)
        #expect(deleteCrash.isError == true)
        #expect(listScreenshots.isError == true)
        #expect(getScreenshot.isError == true)
        #expect(deleteScreenshot.isError == true)
    }

    @Test("crash log result is truncated by max_log_chars")
    func crashLogResultIsTruncated() async throws {
        let transport = BetaFeedbackMockTransport(body: """
        {
          "data": {
            "type": "betaCrashLogs",
            "id": "crash-log-1",
            "attributes": { "logText": "0123456789" }
          },
          "links": { "self": "https://api.example.test/v1/betaCrashLogs/crash-log-1" }
        }
        """)
        let client = await HTTPClient(
            jwtService: try TestFactory.makeJWTService(),
            baseURL: "https://api.example.test",
            transport: transport,
            maxRetries: 1
        )
        let worker = BetaFeedbackWorker(httpClient: client)

        let result = try await worker.handleTool(
            CallTool.Parameters(
                name: "beta_feedback_get_crash_log_by_id",
                arguments: [
                    "crash_log_id": .string("crash-log-1"),
                    "max_log_chars": .int(5)
                ]
            )
        )

        #expect(result.isError == nil)
        guard case .object(let root)? = result.structuredContent,
              case .object(let crashLog)? = root["crashLog"] else {
            Issue.record("Expected structured crash log object")
            return
        }

        #expect(crashLog["logText"] == .string("01234"))
        #expect(crashLog["totalCharacters"] == .int(10))
        #expect(crashLog["returnedCharacters"] == .int(5))
        #expect(crashLog["truncated"] == .bool(true))
    }

    @Test("model decodes screenshot images and crash attributes")
    func modelDecoding() throws {
        let crashJSON = Data("""
        {
          "data": [{
            "type": "betaFeedbackCrashSubmissions",
            "id": "crash-1",
            "attributes": {
              "createdDate": "2026-05-06T10:00:00Z",
              "comment": "It crashed",
              "email": "tester@example.com",
              "deviceModel": "iPhone",
              "osVersion": "18.0",
              "appUptimeInMilliseconds": 1234
            },
            "relationships": {
              "build": { "data": { "type": "builds", "id": "build-1" } },
              "tester": { "data": { "type": "betaTesters", "id": "tester-1" } }
            }
          }],
          "links": { "self": "https://api.example.test/v1/apps/app-1/betaFeedbackCrashSubmissions" }
        }
        """.utf8)
        let crashResponse = try JSONDecoder().decode(ASCBetaFeedbackCrashSubmissionsResponse.self, from: crashJSON)
        #expect(crashResponse.data.first?.attributes?.email == "tester@example.com")
        #expect(crashResponse.data.first?.relationships?.build?.data?.id == "build-1")

        let screenshotJSON = Data("""
        {
          "data": {
            "type": "betaFeedbackScreenshotSubmissions",
            "id": "shot-1",
            "attributes": {
              "screenshots": [{
                "url": "https://example.com/screenshot.png",
                "width": 1170,
                "height": 2532,
                "expirationDate": "2026-05-07T10:00:00Z"
              }]
            }
          },
          "links": { "self": "https://api.example.test/v1/betaFeedbackScreenshotSubmissions/shot-1" }
        }
        """.utf8)
        let screenshotResponse = try JSONDecoder().decode(ASCBetaFeedbackScreenshotSubmissionResponse.self, from: screenshotJSON)
        #expect(screenshotResponse.data.attributes?.screenshots?.first?.width == 1170)
    }
}

private actor BetaFeedbackMockTransport: HTTPTransport {
    private let body: String

    init(body: String) {
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.test")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        return (Data(body.utf8), response)
    }
}
