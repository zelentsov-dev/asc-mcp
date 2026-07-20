import Testing
import Foundation
import MCP
@testable import asc_mcp

@Suite("Worker Routing Tests")
struct WorkerRoutingTests {
    @Test("WorkerManager routes overlapping builds prefixes correctly")
    func workerManagerRoutesOverlappingBuildsPrefixes() async throws {
        let manager = try await TestFactory.makeWorkerManager()

        let beta = try await manager.routeTool(CallTool.Parameters(name: "builds_get_beta_detail", arguments: nil))
        #expect(beta.isError == true)

        let processing = try await manager.routeTool(CallTool.Parameters(name: "builds_get_processing_state", arguments: nil))
        #expect(processing.isError == true)

        let plain = try await manager.routeTool(CallTool.Parameters(name: "builds_find_by_number", arguments: nil))
        #expect(plain.isError == true)
    }

    @Test("WorkerManager routes app versions and review attachments before fallback")
    func workerManagerRoutesDistinctLongPrefixes() async throws {
        let manager = try await TestFactory.makeWorkerManager()

        let accessibility = try await manager.routeTool(CallTool.Parameters(name: "accessibility_get", arguments: nil))
        #expect(accessibility.isError == true)

        let version = try await manager.routeTool(CallTool.Parameters(name: "app_versions_get", arguments: nil))
        #expect(version.isError == true)

        let attachment = try await manager.routeTool(CallTool.Parameters(name: "review_attachments_get", arguments: nil))
        #expect(attachment.isError == true)
    }

    @Test("WorkerManager read-only mode blocks mutation tools before handler execution")
    func workerManagerReadOnlyBlocksMutationTools() async throws {
        let manager = try await TestFactory.makeWorkerManager(readOnlyMode: true)

        let result = try await manager.routeTool(CallTool.Parameters(name: "app_versions_release", arguments: nil))

        #expect(result.isError == true)
        #expect(result._meta?.fields["asc/readOnlyMode"] == .bool(true))
        #expect(result._meta?.fields["asc/blockedTool"] == .string("app_versions_release"))

        guard case .text(let text, _, _) = result.content.first else {
            Issue.record("Expected text error content")
            return
        }
        #expect(text.contains("Read-only mode is enabled"))
    }

    @Test("WorkerManager read-only mode allows read-only tools to reach handlers")
    func workerManagerReadOnlyAllowsReadOnlyTools() async throws {
        let manager = try await TestFactory.makeWorkerManager(readOnlyMode: true)

        let result = try await manager.routeTool(CallTool.Parameters(name: "auth_token_status", arguments: nil))

        #expect(result._meta?.fields["asc/blockedTool"] == nil)
        #expect(result._meta?.fields["asc/readOnlyMode"] == nil)
    }

    @Test("WorkerManager normalizes direct worker errors at the routing boundary")
    func workerManagerNormalizesDirectWorkerErrors() async throws {
        let manager = try await TestFactory.makeWorkerManager(enabledWorkers: ["builds"])

        let result = try await manager.routeTool(CallTool.Parameters(name: "builds_get", arguments: nil))

        #expect(result.isError == true)
        #expect(result.content.count == 2)
        guard case .text(let humanText, _, _) = result.content.first,
              case .object(let payload)? = result.structuredContent else {
            Issue.record("Expected normalized worker error")
            return
        }

        #expect(humanText == "Error: Required parameter 'build_id' is missing")
        #expect(payload["success"] == .bool(false))
        #expect(payload["error"] == .string("Required parameter 'build_id' is missing"))
        #expect(payload["details"] == .null)
        #expect(try routingJSONMirror(from: result) == routingStructuredJSON(from: result))
    }

    @Test("registered WorkerManager error survives an in-memory SDK round trip")
    func registeredWorkerManagerErrorRoundTrip() async throws {
        let manager = try await TestFactory.makeWorkerManager(enabledWorkers: ["builds"])
        let server = Server(
            name: "asc-mcp-test",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )
        await manager.registerWorkers(in: server)
        let transports = await InMemoryTransport.createConnectedPair()
        let client = Client(name: "asc-mcp-test-client", version: "1.0.0")

        try await server.start(transport: transports.server)
        let result: CallTool.Result
        let thrownResult: CallTool.Result
        do {
            _ = try await client.connect(transport: transports.client)
            let request = CallTool.request(.init(name: "builds_get", arguments: nil))
            let context: RequestContext<CallTool.Result> = try await client.send(request)
            result = try await context.value
            let thrownRequest = CallTool.request(.init(name: "builds_nonexistent", arguments: nil))
            let thrownContext: RequestContext<CallTool.Result> = try await client.send(thrownRequest)
            thrownResult = try await thrownContext.value
            await client.disconnect()
            await server.stop()
        } catch {
            await client.disconnect()
            await server.stop()
            throw error
        }

        #expect(result.isError == true)
        #expect(result.content.count == 2)
        guard case .object(let payload)? = result.structuredContent else {
            Issue.record("Expected wire-decoded structured error")
            return
        }
        #expect(payload["success"] == .bool(false))
        #expect(payload["error"] == .string("Required parameter 'build_id' is missing"))
        #expect(payload["details"] == .null)
        #expect(try routingJSONMirror(from: result) == routingStructuredJSON(from: result))

        #expect(thrownResult.isError == true)
        guard case .object(let thrownPayload)? = thrownResult.structuredContent,
              case .string(let thrownError)? = thrownPayload["error"] else {
            Issue.record("Expected converted thrown error")
            return
        }
        #expect(thrownPayload["success"] == .bool(false))
        #expect(thrownPayload["details"] == .null)
        #expect(thrownError.contains("Unknown tool: builds_nonexistent"))
        #expect(try routingJSONMirror(from: thrownResult) == routingStructuredJSON(from: thrownResult))
    }

    // MARK: - AppsWorker

    @Test("AppsWorker throws MCPError.methodNotFound for unknown tool")
    func appsWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppsWorker(client: client)
        let params = CallTool.Parameters(name: "apps_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - AccessibilityWorker

    @Test("AccessibilityWorker throws MCPError.methodNotFound for unknown tool")
    func accessibilityWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AccessibilityWorker(httpClient: client)
        let params = CallTool.Parameters(name: "accessibility_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - WebhooksWorker

    @Test("WebhooksWorker throws MCPError.methodNotFound for unknown tool")
    func webhooksWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = WebhooksWorker(httpClient: client)
        let params = CallTool.Parameters(name: "webhooks_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - XcodeCloudWorker

    @Test("XcodeCloudWorker throws MCPError.methodNotFound for unknown tool")
    func xcodeCloudWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = XcodeCloudWorker(httpClient: client)
        let params = CallTool.Parameters(name: "xcode_cloud_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - BuildsWorker

    @Test("BuildsWorker throws MCPError.methodNotFound for unknown tool")
    func buildsWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BuildsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "builds_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - BuildProcessingWorker

    @Test("BuildProcessingWorker throws MCPError.methodNotFound for unknown tool")
    func buildProcessingWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BuildProcessingWorker(httpClient: client)
        let params = CallTool.Parameters(name: "builds_nonexistent_processing", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - BuildBetaDetailsWorker

    @Test("BuildBetaDetailsWorker throws MCPError.methodNotFound for unknown tool")
    func buildBetaDetailsWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BuildBetaDetailsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "builds_nonexistent_beta", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - AppLifecycleWorker

    @Test("AppLifecycleWorker throws MCPError.methodNotFound for unknown tool")
    func appLifecycleWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppLifecycleWorker(httpClient: client)
        let params = CallTool.Parameters(name: "app_versions_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - ReviewsWorker

    @Test("ReviewsWorker throws MCPError.methodNotFound for unknown tool")
    func reviewsWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ReviewsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "reviews_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - BetaGroupsWorker

    @Test("BetaGroupsWorker throws MCPError.methodNotFound for unknown tool")
    func betaGroupsWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BetaGroupsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "beta_groups_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - BetaFeedbackWorker

    @Test("BetaFeedbackWorker throws MCPError.methodNotFound for unknown tool")
    func betaFeedbackWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BetaFeedbackWorker(httpClient: client)
        let params = CallTool.Parameters(name: "beta_feedback_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - InAppPurchasesWorker

    @Test("InAppPurchasesWorker throws MCPError.methodNotFound for unknown tool")
    func inAppPurchasesWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = InAppPurchasesWorker(httpClient: client, uploadService: UploadService())
        let params = CallTool.Parameters(name: "iap_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - ProvisioningWorker

    @Test("ProvisioningWorker throws MCPError.methodNotFound for unknown tool")
    func provisioningWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ProvisioningWorker(httpClient: client)
        let params = CallTool.Parameters(name: "provisioning_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - BetaTestersWorker

    @Test("BetaTestersWorker throws MCPError.methodNotFound for unknown tool")
    func betaTestersWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BetaTestersWorker(httpClient: client)
        let params = CallTool.Parameters(name: "beta_testers_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - AppInfoWorker

    @Test("AppInfoWorker throws MCPError.methodNotFound for unknown tool")
    func appInfoWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppInfoWorker(httpClient: client)
        let params = CallTool.Parameters(name: "app_info_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - PricingWorker

    @Test("PricingWorker throws MCPError.methodNotFound for unknown tool")
    func pricingWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = PricingWorker(httpClient: client)
        let params = CallTool.Parameters(name: "pricing_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - UsersWorker

    @Test("UsersWorker throws MCPError.methodNotFound for unknown tool")
    func usersWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = UsersWorker(httpClient: client)
        let params = CallTool.Parameters(name: "users_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - AppEventsWorker

    @Test("AppEventsWorker throws MCPError.methodNotFound for unknown tool")
    func appEventsWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AppEventsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "app_events_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - AnalyticsWorker

    @Test("AnalyticsWorker throws MCPError.methodNotFound for unknown tool")
    func analyticsWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = AnalyticsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "analytics_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - AuthWorker

    @Test("AuthWorker throws MCPError.methodNotFound for unknown tool")
    func authWorkerUnknownTool() async throws {
        let jwt = try TestFactory.makeJWTService()
        let worker = AuthWorker(jwtService: jwt)
        let params = CallTool.Parameters(name: "auth_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - SubscriptionsWorker

    @Test("SubscriptionsWorker throws MCPError.methodNotFound for unknown tool")
    func subscriptionsWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = SubscriptionsWorker(httpClient: client, uploadService: UploadService())
        let params = CallTool.Parameters(name: "subscriptions_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - OfferCodesWorker

    @Test("OfferCodesWorker throws MCPError.methodNotFound for unknown tool")
    func offerCodesWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = OfferCodesWorker(httpClient: client)
        let params = CallTool.Parameters(name: "offer_codes_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - WinBackOffersWorker

    @Test("WinBackOffersWorker throws MCPError.methodNotFound for unknown tool")
    func winBackOffersWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = WinBackOffersWorker(httpClient: client)
        let params = CallTool.Parameters(name: "winback_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - IntroductoryOffersWorker

    @Test("IntroductoryOffersWorker throws MCPError.methodNotFound for unknown tool")
    func introductoryOffersWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = IntroductoryOffersWorker(httpClient: client)
        let params = CallTool.Parameters(name: "intro_offers_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - PromotionalOffersWorker

    @Test("PromotionalOffersWorker throws MCPError.methodNotFound for unknown tool")
    func promotionalOffersWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = PromotionalOffersWorker(httpClient: client)
        let params = CallTool.Parameters(name: "promo_offers_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - SandboxTestersWorker

    @Test("SandboxTestersWorker throws MCPError.methodNotFound for unknown tool")
    func sandboxTestersWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = SandboxTestersWorker(httpClient: client)
        let params = CallTool.Parameters(name: "sandbox_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - BetaAppWorker

    @Test("BetaAppWorker throws MCPError.methodNotFound for unknown tool")
    func betaAppWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BetaAppWorker(httpClient: client)
        let params = CallTool.Parameters(name: "beta_app_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - PreReleaseVersionsWorker

    @Test("PreReleaseVersionsWorker throws MCPError.methodNotFound for unknown tool")
    func preReleaseVersionsWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = PreReleaseVersionsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "pre_release_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - BetaLicenseAgreementsWorker

    @Test("BetaLicenseAgreementsWorker throws MCPError.methodNotFound for unknown tool")
    func betaLicenseAgreementsWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = BetaLicenseAgreementsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "beta_license_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - ScreenshotsWorker

    @Test("ScreenshotsWorker throws MCPError.methodNotFound for unknown tool")
    func screenshotsWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ScreenshotsWorker(httpClient: client, uploadService: UploadService())
        let params = CallTool.Parameters(name: "screenshots_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - CustomProductPagesWorker

    @Test("CustomProductPagesWorker throws MCPError.methodNotFound for unknown tool")
    func customProductPagesWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = CustomProductPagesWorker(httpClient: client)
        let params = CallTool.Parameters(name: "custom_pages_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - ProductPageOptimizationWorker

    @Test("ProductPageOptimizationWorker throws MCPError.methodNotFound for unknown tool")
    func productPageOptimizationWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ProductPageOptimizationWorker(httpClient: client)
        let params = CallTool.Parameters(name: "ppo_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - PromotedPurchasesWorker

    @Test("PromotedPurchasesWorker throws MCPError.methodNotFound for unknown tool")
    func promotedPurchasesWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = PromotedPurchasesWorker(httpClient: client, uploadService: UploadService())
        let params = CallTool.Parameters(name: "promoted_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - MetricsWorker

    @Test("MetricsWorker throws MCPError.methodNotFound for unknown tool")
    func metricsWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = MetricsWorker(httpClient: client)
        let params = CallTool.Parameters(name: "metrics_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }

    // MARK: - ReviewAttachmentsWorker

    @Test("ReviewAttachmentsWorker throws MCPError.methodNotFound for unknown tool")
    func reviewAttachmentsWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = ReviewAttachmentsWorker(httpClient: client, uploadService: UploadService())
        let params = CallTool.Parameters(name: "review_attachments_nonexistent", arguments: nil)
        await #expect(throws: MCPError.self) {
            _ = try await worker.handleTool(params)
        }
    }
}

private func routingJSONMirror(from result: CallTool.Result) throws -> String {
    guard case .text(let mirror, _, _) = result.content.last else {
        Issue.record("Expected JSON mirror as the last text content block")
        throw WorkerRoutingTestFailure.missingMirror
    }
    return mirror
}

private func routingStructuredJSON(from result: CallTool.Result) throws -> String {
    guard let structuredContent = result.structuredContent else {
        Issue.record("Expected structured content")
        throw WorkerRoutingTestFailure.missingStructuredContent
    }
    return try MCPValue.compactJSONString(from: structuredContent)
}

private enum WorkerRoutingTestFailure: Error {
    case missingMirror
    case missingStructuredContent
}
