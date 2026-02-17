import Testing
import Foundation
import MCP
@testable import asc_mcp

@Suite("Worker Routing Tests")
struct WorkerRoutingTests {

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

    // MARK: - InAppPurchasesWorker

    @Test("InAppPurchasesWorker throws MCPError.methodNotFound for unknown tool")
    func inAppPurchasesWorkerUnknownTool() async throws {
        let client = try await TestFactory.makeHTTPClient()
        let worker = InAppPurchasesWorker(httpClient: client)
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
}
