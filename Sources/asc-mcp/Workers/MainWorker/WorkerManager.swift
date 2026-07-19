import Foundation
import MCP

/// Dependencies container for WorkerManager
public actor WorkerDependencies: Sendable {
    public let companiesWorker: CompaniesWorker
    public var jwtService: JWTService
    public var httpClient: HTTPClient
    public var authWorker: AuthWorker
    
    public init(
        companiesWorker: CompaniesWorker,
        jwtService: JWTService,
        httpClient: HTTPClient,
        authWorker: AuthWorker
    ) {
        self.companiesWorker = companiesWorker
        self.jwtService = jwtService
        self.httpClient = httpClient
        self.authWorker = authWorker
    }
    
    /// Update dependencies for a company after all replacement services are built successfully.
    /// - Parameter company: Company configuration to use for new auth and HTTP dependencies.
    /// - Throws: JWT/private-key errors if the candidate company cannot initialize authentication.
    public func updateForCompany(_ company: Company) async throws {
        let defaultURL = await companiesWorker.manager.getDefaultURL()

        print("Reinitializing workers for company: \(company.name)", to: &standardError)
        print("  Key ID: \(Redactor.maskIdentifier(company.keyID))", to: &standardError)
        print("  Issuer ID: \(Redactor.maskIdentifier(company.issuerID))", to: &standardError)

        let newJWTService = try JWTService(company: company)
        let newHTTPClient = await HTTPClient(
            jwtService: newJWTService,
            baseURL: defaultURL
        )
        let newAuthWorker = AuthWorker(jwtService: newJWTService)

        self.jwtService = newJWTService
        self.httpClient = newHTTPClient
        self.authWorker = newAuthWorker
        
        print("Dependencies updated for company: \(company.name)", to: &standardError)
    }
}

/// Manager for all workers
public actor WorkerManager {
    static let validWorkerFilterKeys: Set<String> = [
        "company", "auth", "apps", "accessibility", "webhooks", "xcode_cloud",
        "builds", "build_processing", "build_beta", "versions", "reviews",
        "beta_groups", "beta_feedback", "beta_testers", "iap", "provisioning",
        "app_info", "pricing", "users", "app_events", "analytics", "subscriptions",
        "sandbox", "beta_app", "pre_release", "beta_license", "screenshots",
        "custom_pages", "ppo", "promoted", "metrics", "review_attachments"
    ]

    private let dependencies: WorkerDependencies
    /// Set of enabled worker names. nil = all workers enabled.
    private let enabledWorkers: Set<String>?
    /// Blocks App Store Connect mutation tools before they reach worker handlers.
    private let readOnlyMode: Bool
    private var appsWorker: AppsWorker
    private var accessibilityWorker: AccessibilityWorker
    private var webhooksWorker: WebhooksWorker
    private var xcodeCloudWorker: XcodeCloudWorker
    private var buildsWorker: BuildsWorker
    private var buildProcessingWorker: BuildProcessingWorker
    private var buildBetaDetailsWorker: BuildBetaDetailsWorker
    private var appLifecycleWorker: AppLifecycleWorker
    private var reviewsWorker: ReviewsWorker
    private var betaGroupsWorker: BetaGroupsWorker
    private var betaFeedbackWorker: BetaFeedbackWorker
    private var inAppPurchasesWorker: InAppPurchasesWorker
    private var provisioningWorker: ProvisioningWorker
    private var betaTestersWorker: BetaTestersWorker
    private var appInfoWorker: AppInfoWorker
    private var pricingWorker: PricingWorker
    private var usersWorker: UsersWorker
    private var appEventsWorker: AppEventsWorker
    private var analyticsWorker: AnalyticsWorker
    private var subscriptionsWorker: SubscriptionsWorker
    private var sandboxTestersWorker: SandboxTestersWorker
    private var betaAppWorker: BetaAppWorker
    private var preReleaseVersionsWorker: PreReleaseVersionsWorker
    private var betaLicenseAgreementsWorker: BetaLicenseAgreementsWorker
    private var screenshotsWorker: ScreenshotsWorker
    private var customProductPagesWorker: CustomProductPagesWorker
    private var productPageOptimizationWorker: ProductPageOptimizationWorker
    private var promotedPurchasesWorker: PromotedPurchasesWorker
    private let uploadService: UploadService
    private var metricsWorker: MetricsWorker
    private var reviewAttachmentsWorker: ReviewAttachmentsWorker

    /// Direct initialization with dependencies for tests and custom embedding.
    /// - Parameters:
    ///   - dependencies: Shared worker dependencies.
    ///   - enabledWorkers: Set of worker names to enable, nil = all workers.
    ///   - readOnlyMode: Whether mutation tools should be blocked before handler execution.
    public init(dependencies: WorkerDependencies, enabledWorkers: Set<String>? = nil, readOnlyMode: Bool = false) async {
        self.dependencies = dependencies
        self.enabledWorkers = enabledWorkers
        self.readOnlyMode = readOnlyMode
        self.uploadService = UploadService()

        self.appsWorker = await AppsWorker(client: dependencies.httpClient)
        self.accessibilityWorker = await AccessibilityWorker(httpClient: dependencies.httpClient)
        self.webhooksWorker = await WebhooksWorker(httpClient: dependencies.httpClient)
        self.xcodeCloudWorker = await XcodeCloudWorker(httpClient: dependencies.httpClient)
        self.buildsWorker = await BuildsWorker(httpClient: dependencies.httpClient)
        self.buildProcessingWorker = await BuildProcessingWorker(httpClient: dependencies.httpClient)
        self.buildBetaDetailsWorker = await BuildBetaDetailsWorker(httpClient: dependencies.httpClient)
        self.appLifecycleWorker = await AppLifecycleWorker(httpClient: dependencies.httpClient)
        self.reviewsWorker = await ReviewsWorker(httpClient: dependencies.httpClient)
        self.betaGroupsWorker = await BetaGroupsWorker(httpClient: dependencies.httpClient)
        self.betaFeedbackWorker = await BetaFeedbackWorker(httpClient: dependencies.httpClient)
        self.inAppPurchasesWorker = await InAppPurchasesWorker(httpClient: dependencies.httpClient, uploadService: self.uploadService)
        self.provisioningWorker = await ProvisioningWorker(httpClient: dependencies.httpClient)
        self.betaTestersWorker = await BetaTestersWorker(httpClient: dependencies.httpClient)
        self.appInfoWorker = await AppInfoWorker(httpClient: dependencies.httpClient)
        self.pricingWorker = await PricingWorker(httpClient: dependencies.httpClient)
        self.usersWorker = await UsersWorker(httpClient: dependencies.httpClient)
        self.appEventsWorker = await AppEventsWorker(httpClient: dependencies.httpClient)
        self.analyticsWorker = await AnalyticsWorker(
            httpClient: dependencies.httpClient,
            companiesManager: dependencies.companiesWorker.manager
        )
        self.subscriptionsWorker = await SubscriptionsWorker(httpClient: dependencies.httpClient, uploadService: self.uploadService)
        self.sandboxTestersWorker = await SandboxTestersWorker(httpClient: dependencies.httpClient)
        self.betaAppWorker = await BetaAppWorker(httpClient: dependencies.httpClient)
        self.preReleaseVersionsWorker = await PreReleaseVersionsWorker(httpClient: dependencies.httpClient)
        self.betaLicenseAgreementsWorker = await BetaLicenseAgreementsWorker(httpClient: dependencies.httpClient)
        self.screenshotsWorker = await ScreenshotsWorker(httpClient: dependencies.httpClient, uploadService: self.uploadService)
        self.customProductPagesWorker = await CustomProductPagesWorker(httpClient: dependencies.httpClient)
        self.productPageOptimizationWorker = await ProductPageOptimizationWorker(httpClient: dependencies.httpClient)
        self.promotedPurchasesWorker = await PromotedPurchasesWorker(httpClient: dependencies.httpClient, uploadService: self.uploadService)
        self.metricsWorker = await MetricsWorker(httpClient: dependencies.httpClient)
        self.reviewAttachmentsWorker = await ReviewAttachmentsWorker(httpClient: dependencies.httpClient, uploadService: self.uploadService)
    }

    /// Convenience factory method for production use.
    /// - Parameters:
    ///   - companiesWorker: Worker that owns company configuration and switching.
    ///   - enabledWorkers: Set of worker names to enable, nil = all workers.
    ///   - readOnlyMode: Whether mutation tools should be blocked before handler execution.
    public static func createForProduction(
        companiesWorker: CompaniesWorker,
        enabledWorkers: Set<String>? = nil,
        readOnlyMode: Bool = false
    ) async throws -> WorkerManager {
        let company = try await companiesWorker.manager.getCurrentCompany()
        let defaultURL = await companiesWorker.manager.getDefaultURL()
        
        // Create core dependencies
        let jwtService = try JWTService(company: company)
        let httpClient = await HTTPClient(
            jwtService: jwtService,
            baseURL: defaultURL
        )
        let authWorker = AuthWorker(jwtService: jwtService)
        
        // Package dependencies
        let dependencies = WorkerDependencies(
            companiesWorker: companiesWorker,
            jwtService: jwtService,
            httpClient: httpClient,
            authWorker: authWorker
        )
        
        return await WorkerManager(dependencies: dependencies, enabledWorkers: enabledWorkers, readOnlyMode: readOnlyMode)
    }

    /// Check if a worker is enabled (nonisolated since enabledWorkers is let)
    private nonisolated func isWorkerEnabled(_ name: String) -> Bool {
        guard let enabled = enabledWorkers else { return true }
        return enabled.contains(name)
    }

    private nonisolated func isWorkerDescriptorEnabled(_ descriptor: WorkerDescriptor) -> Bool {
        descriptor.enabledKeys.isEmpty || descriptor.enabledKeys.contains(where: isWorkerEnabled)
    }

    private struct WorkerDescriptor: Sendable {
        let key: String
        let enabledKeys: Set<String>
        let prefixes: [String]
        let getTools: @Sendable () async -> [Tool]
        let handle: @Sendable (CallTool.Parameters) async throws -> CallTool.Result

        func matches(_ toolName: String) -> Bool {
            prefixes.contains { toolName.hasPrefix($0) }
        }
    }

    private func workerDescriptors() -> [WorkerDescriptor] {
        [
            WorkerDescriptor(
                key: "company",
                enabledKeys: [],
                prefixes: ["company_"],
                getTools: { await self.getCompanyTools() },
                handle: { try await self.dependencies.companiesWorker.handleTool($0) }
            ),
            WorkerDescriptor(
                key: "auth",
                enabledKeys: [],
                prefixes: ["auth_"],
                getTools: { await self.getAuthTools() },
                handle: { try await self.dependencies.authWorker.handleTool($0) }
            ),
            WorkerDescriptor(key: "apps", enabledKeys: ["apps"], prefixes: ["apps_"], getTools: { await self.getAppsTools() }, handle: { try await self.appsWorker.handleTool($0) }),
            WorkerDescriptor(key: "accessibility", enabledKeys: ["accessibility"], prefixes: ["accessibility_"], getTools: { await self.getAccessibilityTools() }, handle: { try await self.accessibilityWorker.handleTool($0) }),
            WorkerDescriptor(key: "webhooks", enabledKeys: ["webhooks"], prefixes: ["webhooks_"], getTools: { await self.getWebhooksTools() }, handle: { try await self.webhooksWorker.handleTool($0) }),
            WorkerDescriptor(key: "xcode_cloud", enabledKeys: ["xcode_cloud"], prefixes: ["xcode_cloud_"], getTools: { await self.getXcodeCloudTools() }, handle: { try await self.xcodeCloudWorker.handleTool($0) }),
            WorkerDescriptor(
                key: "build_beta",
                enabledKeys: ["build_beta", "builds"],
                prefixes: [
                    "builds_get_beta_",
                    "builds_update_beta_",
                    "builds_set_beta_",
                    "builds_list_beta_",
                    "builds_send_beta_",
                    "builds_add_to_beta_",
                    "builds_add_individual_",
                    "builds_remove_individual_",
                    "builds_list_individual_"
                ],
                getTools: { await self.getBuildBetaDetailsTools() },
                handle: { try await self.buildBetaDetailsWorker.handleTool($0) }
            ),
            WorkerDescriptor(
                key: "build_processing",
                enabledKeys: ["build_processing", "builds"],
                prefixes: [
                    "builds_get_processing_",
                    "builds_update_encryption",
                    "builds_check_readiness"
                ],
                getTools: { await self.getBuildProcessingTools() },
                handle: { try await self.buildProcessingWorker.handleTool($0) }
            ),
            WorkerDescriptor(key: "builds", enabledKeys: ["builds"], prefixes: ["builds_"], getTools: { await self.getBuildsTools() }, handle: { try await self.buildsWorker.handleTool($0) }),
            WorkerDescriptor(key: "versions", enabledKeys: ["versions"], prefixes: ["app_versions_"], getTools: { await self.getAppLifecycleTools() }, handle: { try await self.appLifecycleWorker.handleTool($0) }),
            WorkerDescriptor(key: "reviews", enabledKeys: ["reviews"], prefixes: ["reviews_"], getTools: { await self.getReviewsTools() }, handle: { try await self.reviewsWorker.handleTool($0) }),
            WorkerDescriptor(key: "beta_groups", enabledKeys: ["beta_groups"], prefixes: ["beta_groups_"], getTools: { await self.getBetaGroupsTools() }, handle: { try await self.betaGroupsWorker.handleTool($0) }),
            WorkerDescriptor(key: "beta_feedback", enabledKeys: ["beta_feedback"], prefixes: ["beta_feedback_"], getTools: { await self.getBetaFeedbackTools() }, handle: { try await self.betaFeedbackWorker.handleTool($0) }),
            WorkerDescriptor(key: "iap", enabledKeys: ["iap"], prefixes: ["iap_"], getTools: { await self.getIAPTools() }, handle: { try await self.inAppPurchasesWorker.handleTool($0) }),
            WorkerDescriptor(key: "provisioning", enabledKeys: ["provisioning"], prefixes: ["provisioning_"], getTools: { await self.getProvisioningTools() }, handle: { try await self.provisioningWorker.handleTool($0) }),
            WorkerDescriptor(key: "beta_testers", enabledKeys: ["beta_testers"], prefixes: ["beta_testers_"], getTools: { await self.getBetaTestersTools() }, handle: { try await self.betaTestersWorker.handleTool($0) }),
            WorkerDescriptor(key: "app_info", enabledKeys: ["app_info"], prefixes: ["app_info_"], getTools: { await self.getAppInfoTools() }, handle: { try await self.appInfoWorker.handleTool($0) }),
            WorkerDescriptor(key: "pricing", enabledKeys: ["pricing"], prefixes: ["pricing_"], getTools: { await self.getPricingTools() }, handle: { try await self.pricingWorker.handleTool($0) }),
            WorkerDescriptor(key: "users", enabledKeys: ["users"], prefixes: ["users_"], getTools: { await self.getUsersTools() }, handle: { try await self.usersWorker.handleTool($0) }),
            WorkerDescriptor(key: "app_events", enabledKeys: ["app_events"], prefixes: ["app_events_"], getTools: { await self.getAppEventsTools() }, handle: { try await self.appEventsWorker.handleTool($0) }),
            WorkerDescriptor(key: "analytics", enabledKeys: ["analytics"], prefixes: ["analytics_"], getTools: { await self.getAnalyticsTools() }, handle: { try await self.analyticsWorker.handleTool($0) }),
            WorkerDescriptor(key: "subscriptions", enabledKeys: ["subscriptions"], prefixes: ["subscriptions_"], getTools: { await self.getSubscriptionsTools() }, handle: { try await self.subscriptionsWorker.handleTool($0) }),
            WorkerDescriptor(key: "sandbox", enabledKeys: ["sandbox"], prefixes: ["sandbox_"], getTools: { await self.getSandboxTestersTools() }, handle: { try await self.sandboxTestersWorker.handleTool($0) }),
            WorkerDescriptor(key: "beta_app", enabledKeys: ["beta_app"], prefixes: ["beta_app_"], getTools: { await self.getBetaAppTools() }, handle: { try await self.betaAppWorker.handleTool($0) }),
            WorkerDescriptor(key: "pre_release", enabledKeys: ["pre_release"], prefixes: ["pre_release_"], getTools: { await self.getPreReleaseVersionsTools() }, handle: { try await self.preReleaseVersionsWorker.handleTool($0) }),
            WorkerDescriptor(key: "beta_license", enabledKeys: ["beta_license"], prefixes: ["beta_license_"], getTools: { await self.getBetaLicenseAgreementsTools() }, handle: { try await self.betaLicenseAgreementsWorker.handleTool($0) }),
            WorkerDescriptor(key: "screenshots", enabledKeys: ["screenshots"], prefixes: ["screenshots_"], getTools: { await self.getScreenshotsTools() }, handle: { try await self.screenshotsWorker.handleTool($0) }),
            WorkerDescriptor(key: "custom_pages", enabledKeys: ["custom_pages"], prefixes: ["custom_pages_"], getTools: { await self.getCustomProductPagesTools() }, handle: { try await self.customProductPagesWorker.handleTool($0) }),
            WorkerDescriptor(key: "ppo", enabledKeys: ["ppo"], prefixes: ["ppo_"], getTools: { await self.getProductPageOptimizationTools() }, handle: { try await self.productPageOptimizationWorker.handleTool($0) }),
            WorkerDescriptor(key: "promoted", enabledKeys: ["promoted"], prefixes: ["promoted_"], getTools: { await self.getPromotedPurchasesTools() }, handle: { try await self.promotedPurchasesWorker.handleTool($0) }),
            WorkerDescriptor(key: "metrics", enabledKeys: ["metrics"], prefixes: ["metrics_"], getTools: { await self.getMetricsTools() }, handle: { try await self.metricsWorker.handleTool($0) }),
            WorkerDescriptor(key: "review_attachments", enabledKeys: ["review_attachments"], prefixes: ["review_attachments_"], getTools: { await self.getReviewAttachmentsTools() }, handle: { try await self.reviewAttachmentsWorker.handleTool($0) })
        ]
    }

    func collectWorkerToolSnapshots() async -> [ASCWorkerToolSnapshot] {
        var snapshots: [ASCWorkerToolSnapshot] = []
        for descriptor in workerDescriptors() where isWorkerDescriptorEnabled(descriptor) {
            snapshots.append(ASCWorkerToolSnapshot(
                key: descriptor.key,
                readmeName: ASCToolCatalogFactory.readmeName(for: descriptor.key),
                tools: await descriptor.getTools()
            ))
        }
        return snapshots
    }
    
    /// Register all workers in MCP server
    public func registerWorkers(in server: Server) async {
        // Register unified handler for tool listing
        await server.withMethodHandler(ListTools.self) { _ in
            var allTools: [Tool] = []
            for descriptor in await self.workerDescriptors() where self.isWorkerDescriptorEnabled(descriptor) {
                allTools += await descriptor.getTools()
            }

            return ListTools.Result(tools: allTools.map(ToolMetadataPolicy.apply))
        }

        // Handler for all tool calls
        await server.withMethodHandler(CallTool.self) { params in
            do {
                return await self.withRuntimeMetadata(try await self.routeTool(params))
            } catch {
                // Catch all errors and return them as Result
                if let ascError = error as? ASCError {
                    return await self.withRuntimeMetadata(
                        MCPResult.error(ascError.localizedDescription, details: ascError.structuredValue)
                    )
                }
                return await self.withRuntimeMetadata(MCPResult.error(error.localizedDescription))
            }
        }
    }

    func routeTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        if readOnlyMode, isBlockedByReadOnlyMode(params.name) {
            return readOnlyBlockedResult(params.name)
        }

        if params.name == "company_switch" {
            return try await switchCompanyTransactionally(params)
        }

        for descriptor in workerDescriptors() where descriptor.matches(params.name) {
            guard isWorkerDescriptorEnabled(descriptor) else {
                return disabledWorkerResult(descriptor.key)
            }
            return try await descriptor.handle(params)
        }

        return MCPResult.error("Unknown tool: \(params.name)")
    }

    private func withRuntimeMetadata(_ result: CallTool.Result) async -> CallTool.Result {
        let httpClient = await dependencies.httpClient
        guard let rateLimitInfo = await httpClient.getLastRateLimitInfo() else {
            return result
        }

        var fields = result._meta?.fields ?? [:]
        for (key, value) in rateLimitInfo.metadataFields {
            fields[key] = value
        }

        return CallTool.Result(
            content: result.content,
            structuredContent: result.structuredContent,
            isError: result.isError,
            _meta: Metadata(additionalFields: fields)
        )
    }
    
    private func switchCompanyTransactionally(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let companyValue = arguments["company"],
              let companyIdOrName = companyValue.stringValue else {
            return MCPResult.error("Required parameter 'company' (ID or name)")
        }

        do {
            let manager = dependencies.companiesWorker.manager
            let company = try await manager.resolveCompany(companyIdOrName)
            try await reinitializeWorkers(for: company)
            await manager.setCurrentCompany(company)
            return dependencies.companiesWorker.makeSwitchResult(for: company)
        } catch {
            return MCPResult.error("Error switching company: \(error.localizedDescription)")
        }
    }

    /// Reinitialize workers with the currently active company configuration.
    /// - Throws: JWT/private-key errors if dependency replacement cannot be built.
    public func reinitializeWorkers() async throws {
        let company = try await dependencies.companiesWorker.manager.getCurrentCompany()
        try await reinitializeWorkers(for: company)
    }

    /// Reinitialize workers with a prepared company configuration.
    /// - Parameter company: Company whose credentials should back all API workers.
    /// - Throws: JWT/private-key errors if dependency replacement cannot be built.
    public func reinitializeWorkers(for company: Company) async throws {
        try await dependencies.updateForCompany(company)
        self.appsWorker = await AppsWorker(client: dependencies.httpClient)
        self.accessibilityWorker = await AccessibilityWorker(httpClient: dependencies.httpClient)
        self.webhooksWorker = await WebhooksWorker(httpClient: dependencies.httpClient)
        self.xcodeCloudWorker = await XcodeCloudWorker(httpClient: dependencies.httpClient)
        self.buildsWorker = await BuildsWorker(httpClient: dependencies.httpClient)
        self.buildProcessingWorker = await BuildProcessingWorker(httpClient: dependencies.httpClient)
        self.buildBetaDetailsWorker = await BuildBetaDetailsWorker(httpClient: dependencies.httpClient)
        self.appLifecycleWorker = await AppLifecycleWorker(httpClient: dependencies.httpClient)
        self.reviewsWorker = await ReviewsWorker(httpClient: dependencies.httpClient)
        self.betaGroupsWorker = await BetaGroupsWorker(httpClient: dependencies.httpClient)
        self.betaFeedbackWorker = await BetaFeedbackWorker(httpClient: dependencies.httpClient)
        self.inAppPurchasesWorker = await InAppPurchasesWorker(httpClient: dependencies.httpClient, uploadService: self.uploadService)
        self.provisioningWorker = await ProvisioningWorker(httpClient: dependencies.httpClient)
        self.betaTestersWorker = await BetaTestersWorker(httpClient: dependencies.httpClient)
        self.appInfoWorker = await AppInfoWorker(httpClient: dependencies.httpClient)
        self.pricingWorker = await PricingWorker(httpClient: dependencies.httpClient)
        self.usersWorker = await UsersWorker(httpClient: dependencies.httpClient)
        self.appEventsWorker = await AppEventsWorker(httpClient: dependencies.httpClient)
        self.analyticsWorker = await AnalyticsWorker(
            httpClient: dependencies.httpClient,
            companiesManager: dependencies.companiesWorker.manager
        )
        self.subscriptionsWorker = await SubscriptionsWorker(httpClient: dependencies.httpClient, uploadService: self.uploadService)
        self.sandboxTestersWorker = await SandboxTestersWorker(httpClient: dependencies.httpClient)
        self.betaAppWorker = await BetaAppWorker(httpClient: dependencies.httpClient)
        self.preReleaseVersionsWorker = await PreReleaseVersionsWorker(httpClient: dependencies.httpClient)
        self.betaLicenseAgreementsWorker = await BetaLicenseAgreementsWorker(httpClient: dependencies.httpClient)
        self.screenshotsWorker = await ScreenshotsWorker(httpClient: dependencies.httpClient, uploadService: self.uploadService)
        self.customProductPagesWorker = await CustomProductPagesWorker(httpClient: dependencies.httpClient)
        self.productPageOptimizationWorker = await ProductPageOptimizationWorker(httpClient: dependencies.httpClient)
        self.promotedPurchasesWorker = await PromotedPurchasesWorker(httpClient: dependencies.httpClient, uploadService: self.uploadService)
        self.metricsWorker = await MetricsWorker(httpClient: dependencies.httpClient)
        self.reviewAttachmentsWorker = await ReviewAttachmentsWorker(httpClient: dependencies.httpClient, uploadService: self.uploadService)

        print("Workers reinitialized successfully", to: &standardError)
    }
    
    /// Returns error result for disabled worker
    private nonisolated func disabledWorkerResult(_ workerName: String) -> CallTool.Result {
        MCPResult.error("Worker '\(workerName)' is disabled. Enable it with --workers \(workerName)")
    }

    private nonisolated func isBlockedByReadOnlyMode(_ toolName: String) -> Bool {
        if toolName == "company_switch" {
            return false
        }
        return !ToolMetadataPolicy.isReadOnly(toolName)
    }

    private nonisolated func readOnlyBlockedResult(_ toolName: String) -> CallTool.Result {
        MCPResult.error(
            "Read-only mode is enabled. Tool '\(toolName)' is blocked because it can mutate App Store Connect.",
            details: .object([
                "tool": .string(toolName),
                "readOnlyMode": .bool(true),
                "reason": .string("mutation_blocked")
            ]),
            _meta: Metadata(additionalFields: [
                "asc/readOnlyMode": .bool(true),
                "asc/blockedTool": .string(toolName)
            ])
        )
    }

    // MARK: - Tool Collection Methods
    
    /// Get tools from companies worker
    private func getCompanyTools() async -> [Tool] {
        return await dependencies.companiesWorker.getTools()
    }
    
    /// Get tools from auth worker
    private func getAuthTools() async -> [Tool] {
        return await dependencies.authWorker.getTools()
    }
    
    /// Get tools from apps worker  
    private func getAppsTools() async -> [Tool] {
        return await appsWorker.getTools()
    }

    /// Get tools from accessibility declarations worker
    private func getAccessibilityTools() async -> [Tool] {
        return await accessibilityWorker.getTools()
    }

    /// Get tools from webhooks worker
    private func getWebhooksTools() async -> [Tool] {
        return await webhooksWorker.getTools()
    }

    /// Get tools from Xcode Cloud worker
    private func getXcodeCloudTools() async -> [Tool] {
        return await xcodeCloudWorker.getTools()
    }
    
    /// Get tools from builds worker
    private func getBuildsTools() async -> [Tool] {
        return await buildsWorker.getTools()
    }
    
    /// Get tools from build processing worker
    private func getBuildProcessingTools() async -> [Tool] {
        return await buildProcessingWorker.getTools()
    }
    
    /// Get tools from build beta details worker
    private func getBuildBetaDetailsTools() async -> [Tool] {
        return await buildBetaDetailsWorker.getTools()
    }
    
    /// Get tools from app lifecycle worker
    private func getAppLifecycleTools() async -> [Tool] {
        return await appLifecycleWorker.getTools()
    }
    
    /// Get tools from reviews worker
    private func getReviewsTools() async -> [Tool] {
        return await reviewsWorker.getTools()
    }

    /// Get tools from beta groups worker
    private func getBetaGroupsTools() async -> [Tool] {
        return await betaGroupsWorker.getTools()
    }

    /// Get tools from beta feedback worker
    private func getBetaFeedbackTools() async -> [Tool] {
        return await betaFeedbackWorker.getTools()
    }

    /// Get tools from in-app purchases worker
    private func getIAPTools() async -> [Tool] {
        return await inAppPurchasesWorker.getTools()
    }

    /// Get tools from provisioning worker
    private func getProvisioningTools() async -> [Tool] {
        return await provisioningWorker.getTools()
    }

    /// Get tools from beta testers worker
    private func getBetaTestersTools() async -> [Tool] {
        return await betaTestersWorker.getTools()
    }

    /// Get tools from app info worker
    private func getAppInfoTools() async -> [Tool] {
        return await appInfoWorker.getTools()
    }

    /// Get tools from pricing worker
    private func getPricingTools() async -> [Tool] {
        return await pricingWorker.getTools()
    }

    /// Get tools from users worker
    private func getUsersTools() async -> [Tool] {
        return await usersWorker.getTools()
    }

    /// Get tools from app events worker
    private func getAppEventsTools() async -> [Tool] {
        return await appEventsWorker.getTools()
    }

    /// Get tools from analytics worker
    private func getAnalyticsTools() async -> [Tool] {
        return await analyticsWorker.getTools()
    }

    private func getSubscriptionsTools() async -> [Tool] {
        return await subscriptionsWorker.getTools()
    }

    private func getSandboxTestersTools() async -> [Tool] {
        return await sandboxTestersWorker.getTools()
    }

    private func getBetaAppTools() async -> [Tool] {
        return await betaAppWorker.getTools()
    }

    private func getPreReleaseVersionsTools() async -> [Tool] {
        return await preReleaseVersionsWorker.getTools()
    }

    private func getBetaLicenseAgreementsTools() async -> [Tool] {
        return await betaLicenseAgreementsWorker.getTools()
    }

    private func getScreenshotsTools() async -> [Tool] {
        return await screenshotsWorker.getTools()
    }

    private func getCustomProductPagesTools() async -> [Tool] {
        return await customProductPagesWorker.getTools()
    }

    private func getProductPageOptimizationTools() async -> [Tool] {
        return await productPageOptimizationWorker.getTools()
    }

    private func getPromotedPurchasesTools() async -> [Tool] {
        return await promotedPurchasesWorker.getTools()
    }

    private func getMetricsTools() async -> [Tool] {
        return await metricsWorker.getTools()
    }

    private func getReviewAttachmentsTools() async -> [Tool] {
        return await reviewAttachmentsWorker.getTools()
    }
}
