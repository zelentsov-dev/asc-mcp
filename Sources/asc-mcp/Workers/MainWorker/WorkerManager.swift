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
    
    /// Update dependencies for a new company
    public func updateForCompany() async throws {
        // Get current company from CompaniesManager
        let company = try await companiesWorker.manager.getCurrentCompany()
        let defaultURL = await companiesWorker.manager.getDefaultURL()

        print("🔄 Reinitializing workers for company: \(company.name)", to: &standardError)
        print("  Key ID: \(company.keyID)", to: &standardError)
        print("  Issuer ID: \(company.issuerID)", to: &standardError)

        self.jwtService = try JWTService(company: company)

        self.httpClient = await HTTPClient(
            jwtService: self.jwtService,
            baseURL: defaultURL
        )

        self.authWorker = AuthWorker(jwtService: self.jwtService)
        
        print("✅ Dependencies updated for company: \(company.name)", to: &standardError)
    }
}

/// Manager for all workers
public actor WorkerManager {
    private let dependencies: WorkerDependencies
    /// Set of enabled worker names. nil = all workers enabled.
    private let enabledWorkers: Set<String>?
    private var appsWorker: AppsWorker
    private var buildsWorker: BuildsWorker
    private var buildProcessingWorker: BuildProcessingWorker
    private var buildBetaDetailsWorker: BuildBetaDetailsWorker
    private var appLifecycleWorker: AppLifecycleWorker
    private var reviewsWorker: ReviewsWorker
    private var betaGroupsWorker: BetaGroupsWorker
    private var inAppPurchasesWorker: InAppPurchasesWorker
    private var provisioningWorker: ProvisioningWorker
    private var betaTestersWorker: BetaTestersWorker
    private var appInfoWorker: AppInfoWorker
    private var pricingWorker: PricingWorker
    private var usersWorker: UsersWorker
    private var appEventsWorker: AppEventsWorker
    private var analyticsWorker: AnalyticsWorker
    private var subscriptionsWorker: SubscriptionsWorker
    private var offerCodesWorker: OfferCodesWorker
    private var winBackOffersWorker: WinBackOffersWorker
    private var introductoryOffersWorker: IntroductoryOffersWorker
    private var promotionalOffersWorker: PromotionalOffersWorker
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

    /// Direct initialization with dependencies (for testing and flexibility)
    /// - Parameter enabledWorkers: Set of worker names to enable, nil = all
    public init(dependencies: WorkerDependencies, enabledWorkers: Set<String>? = nil) async {
        self.dependencies = dependencies
        self.enabledWorkers = enabledWorkers
        self.uploadService = UploadService()

        self.appsWorker = await AppsWorker(client: dependencies.httpClient)
        self.buildsWorker = await BuildsWorker(httpClient: dependencies.httpClient)
        self.buildProcessingWorker = await BuildProcessingWorker(httpClient: dependencies.httpClient)
        self.buildBetaDetailsWorker = await BuildBetaDetailsWorker(httpClient: dependencies.httpClient)
        self.appLifecycleWorker = await AppLifecycleWorker(httpClient: dependencies.httpClient)
        self.reviewsWorker = await ReviewsWorker(httpClient: dependencies.httpClient)
        self.betaGroupsWorker = await BetaGroupsWorker(httpClient: dependencies.httpClient)
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
        self.offerCodesWorker = await OfferCodesWorker(httpClient: dependencies.httpClient)
        self.winBackOffersWorker = await WinBackOffersWorker(httpClient: dependencies.httpClient)
        self.introductoryOffersWorker = await IntroductoryOffersWorker(httpClient: dependencies.httpClient)
        self.promotionalOffersWorker = await PromotionalOffersWorker(httpClient: dependencies.httpClient)
        self.sandboxTestersWorker = await SandboxTestersWorker(httpClient: dependencies.httpClient)
        self.betaAppWorker = await BetaAppWorker(httpClient: dependencies.httpClient)
        self.preReleaseVersionsWorker = await PreReleaseVersionsWorker(httpClient: dependencies.httpClient)
        self.betaLicenseAgreementsWorker = await BetaLicenseAgreementsWorker(httpClient: dependencies.httpClient)
        self.screenshotsWorker = await ScreenshotsWorker(httpClient: dependencies.httpClient)
        self.customProductPagesWorker = await CustomProductPagesWorker(httpClient: dependencies.httpClient)
        self.productPageOptimizationWorker = await ProductPageOptimizationWorker(httpClient: dependencies.httpClient)
        self.promotedPurchasesWorker = await PromotedPurchasesWorker(httpClient: dependencies.httpClient, uploadService: self.uploadService)
        self.metricsWorker = await MetricsWorker(httpClient: dependencies.httpClient)
        self.reviewAttachmentsWorker = await ReviewAttachmentsWorker(httpClient: dependencies.httpClient, uploadService: self.uploadService)
    }

    /// Convenience factory method for production use
    /// - Parameter enabledWorkers: Set of worker names to enable, nil = all
    public static func createForProduction(
        companiesWorker: CompaniesWorker,
        enabledWorkers: Set<String>? = nil
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
        
        return await WorkerManager(dependencies: dependencies, enabledWorkers: enabledWorkers)
    }

    /// Check if a worker is enabled (nonisolated since enabledWorkers is let)
    private nonisolated func isWorkerEnabled(_ name: String) -> Bool {
        guard let enabled = enabledWorkers else { return true }
        return enabled.contains(name)
    }
    
    /// Register all workers in MCP server
    public func registerWorkers(in server: Server) async {
        // Register unified handler for tool listing
        await server.withMethodHandler(ListTools.self) { _ in
            // Company and auth are always included (core functionality)
            async let companyTools = self.getCompanyTools()
            async let authTools = self.getAuthTools()

            var allTools = await companyTools + authTools

            // Conditionally include other workers based on enabledWorkers filter
            if self.isWorkerEnabled("apps") {
                allTools += await self.getAppsTools()
            }
            if self.isWorkerEnabled("builds") {
                allTools += await self.getBuildsTools()
            }
            if self.isWorkerEnabled("build_processing") || self.isWorkerEnabled("builds") {
                allTools += await self.getBuildProcessingTools()
            }
            if self.isWorkerEnabled("build_beta") || self.isWorkerEnabled("builds") {
                allTools += await self.getBuildBetaDetailsTools()
            }
            if self.isWorkerEnabled("versions") {
                allTools += await self.getAppLifecycleTools()
            }
            if self.isWorkerEnabled("reviews") {
                allTools += await self.getReviewsTools()
            }
            if self.isWorkerEnabled("beta_groups") {
                allTools += await self.getBetaGroupsTools()
            }
            if self.isWorkerEnabled("iap") {
                allTools += await self.getIAPTools()
            }
            if self.isWorkerEnabled("provisioning") {
                allTools += await self.getProvisioningTools()
            }
            if self.isWorkerEnabled("beta_testers") {
                allTools += await self.getBetaTestersTools()
            }
            if self.isWorkerEnabled("app_info") {
                allTools += await self.getAppInfoTools()
            }
            if self.isWorkerEnabled("pricing") {
                allTools += await self.getPricingTools()
            }
            if self.isWorkerEnabled("users") {
                allTools += await self.getUsersTools()
            }
            if self.isWorkerEnabled("app_events") {
                allTools += await self.getAppEventsTools()
            }
            if self.isWorkerEnabled("analytics") {
                allTools += await self.getAnalyticsTools()
            }
            if self.isWorkerEnabled("subscriptions") {
                allTools += await self.getSubscriptionsTools()
            }
            if self.isWorkerEnabled("offer_codes") {
                allTools += await self.getOfferCodesTools()
            }
            if self.isWorkerEnabled("winback") {
                allTools += await self.getWinBackOffersTools()
            }
            if self.isWorkerEnabled("intro_offers") {
                allTools += await self.getIntroductoryOffersTools()
            }
            if self.isWorkerEnabled("promo_offers") {
                allTools += await self.getPromotionalOffersTools()
            }
            if self.isWorkerEnabled("sandbox") {
                allTools += await self.getSandboxTestersTools()
            }
            if self.isWorkerEnabled("beta_app") {
                allTools += await self.getBetaAppTools()
            }
            if self.isWorkerEnabled("pre_release") {
                allTools += await self.getPreReleaseVersionsTools()
            }
            if self.isWorkerEnabled("beta_license") {
                allTools += await self.getBetaLicenseAgreementsTools()
            }
            if self.isWorkerEnabled("screenshots") {
                allTools += await self.getScreenshotsTools()
            }
            if self.isWorkerEnabled("custom_pages") {
                allTools += await self.getCustomProductPagesTools()
            }
            if self.isWorkerEnabled("ppo") {
                allTools += await self.getProductPageOptimizationTools()
            }
            if self.isWorkerEnabled("promoted") {
                allTools += await self.getPromotedPurchasesTools()
            }
            if self.isWorkerEnabled("metrics") {
                allTools += await self.getMetricsTools()
            }
            if self.isWorkerEnabled("review_attachments") {
                allTools += await self.getReviewAttachmentsTools()
            }

            return ListTools.Result(tools: allTools)
        }
        
        // Handler for all tool calls
        await server.withMethodHandler(CallTool.self) { params in
            do {
                // Special handling for company_switch
                if params.name == "company_switch" {
                    let result = try await self.dependencies.companiesWorker.handleTool(params)
                    // Reinitialize all workers with the new company
                    try await self.reinitializeWorkers()
                    return result
                }

                // Route calls to corresponding workers
                // company_ and auth_ are always enabled
                if params.name.hasPrefix("company_") {
                    return try await self.dependencies.companiesWorker.handleTool(params)
                }

                if params.name.hasPrefix("auth_") {
                    return try await self.dependencies.authWorker.handleTool(params)
                }

                if params.name.hasPrefix("apps_") {
                    guard self.isWorkerEnabled("apps") else { return self.disabledWorkerResult("apps") }
                    return try await self.appsWorker.handleTool(params)
                }

                if params.name.hasPrefix("builds_") {
                    // Determine which builds worker to use based on the specific tool
                    if params.name.hasPrefix("builds_get_beta_") ||
                       params.name.hasPrefix("builds_update_beta_") ||
                       params.name.hasPrefix("builds_set_beta_") ||
                       params.name.hasPrefix("builds_list_beta_") ||
                       params.name.hasPrefix("builds_send_beta_") ||
                       params.name.hasPrefix("builds_add_to_beta_") ||
                       params.name.hasPrefix("builds_add_individual_") ||
                       params.name.hasPrefix("builds_remove_individual_") ||
                       params.name.hasPrefix("builds_list_individual_") {
                        guard self.isWorkerEnabled("build_beta") || self.isWorkerEnabled("builds") else { return self.disabledWorkerResult("build_beta") }
                        return try await self.buildBetaDetailsWorker.handleTool(params)
                    } else if params.name.hasPrefix("builds_get_processing_") ||
                              params.name == "builds_update_encryption" ||
                              params.name == "builds_check_readiness" {
                        guard self.isWorkerEnabled("build_processing") || self.isWorkerEnabled("builds") else { return self.disabledWorkerResult("build_processing") }
                        return try await self.buildProcessingWorker.handleTool(params)
                    } else {
                        guard self.isWorkerEnabled("builds") else { return self.disabledWorkerResult("builds") }
                        return try await self.buildsWorker.handleTool(params)
                    }
                }

                if params.name.hasPrefix("app_versions_") {
                    guard self.isWorkerEnabled("versions") else { return self.disabledWorkerResult("versions") }
                    return try await self.appLifecycleWorker.handleTool(params)
                }

                if params.name.hasPrefix("reviews_") {
                    guard self.isWorkerEnabled("reviews") else { return self.disabledWorkerResult("reviews") }
                    return try await self.reviewsWorker.handleTool(params)
                }

                if params.name.hasPrefix("beta_groups_") {
                    guard self.isWorkerEnabled("beta_groups") else { return self.disabledWorkerResult("beta_groups") }
                    return try await self.betaGroupsWorker.handleTool(params)
                }

                if params.name.hasPrefix("iap_") {
                    guard self.isWorkerEnabled("iap") else { return self.disabledWorkerResult("iap") }
                    return try await self.inAppPurchasesWorker.handleTool(params)
                }

                if params.name.hasPrefix("provisioning_") {
                    guard self.isWorkerEnabled("provisioning") else { return self.disabledWorkerResult("provisioning") }
                    return try await self.provisioningWorker.handleTool(params)
                }

                if params.name.hasPrefix("beta_testers_") {
                    guard self.isWorkerEnabled("beta_testers") else { return self.disabledWorkerResult("beta_testers") }
                    return try await self.betaTestersWorker.handleTool(params)
                }

                if params.name.hasPrefix("app_info_") {
                    guard self.isWorkerEnabled("app_info") else { return self.disabledWorkerResult("app_info") }
                    return try await self.appInfoWorker.handleTool(params)
                }

                if params.name.hasPrefix("pricing_") {
                    guard self.isWorkerEnabled("pricing") else { return self.disabledWorkerResult("pricing") }
                    return try await self.pricingWorker.handleTool(params)
                }

                if params.name.hasPrefix("users_") {
                    guard self.isWorkerEnabled("users") else { return self.disabledWorkerResult("users") }
                    return try await self.usersWorker.handleTool(params)
                }

                if params.name.hasPrefix("app_events_") {
                    guard self.isWorkerEnabled("app_events") else { return self.disabledWorkerResult("app_events") }
                    return try await self.appEventsWorker.handleTool(params)
                }

                if params.name.hasPrefix("analytics_") {
                    guard self.isWorkerEnabled("analytics") else { return self.disabledWorkerResult("analytics") }
                    return try await self.analyticsWorker.handleTool(params)
                }

                if params.name.hasPrefix("subscriptions_") {
                    guard self.isWorkerEnabled("subscriptions") else { return self.disabledWorkerResult("subscriptions") }
                    return try await self.subscriptionsWorker.handleTool(params)
                }

                if params.name.hasPrefix("offer_codes_") {
                    guard self.isWorkerEnabled("offer_codes") else { return self.disabledWorkerResult("offer_codes") }
                    return try await self.offerCodesWorker.handleTool(params)
                }

                if params.name.hasPrefix("winback_") {
                    guard self.isWorkerEnabled("winback") else { return self.disabledWorkerResult("winback") }
                    return try await self.winBackOffersWorker.handleTool(params)
                }

                if params.name.hasPrefix("intro_offers_") {
                    guard self.isWorkerEnabled("intro_offers") else { return self.disabledWorkerResult("intro_offers") }
                    return try await self.introductoryOffersWorker.handleTool(params)
                }

                if params.name.hasPrefix("promo_offers_") {
                    guard self.isWorkerEnabled("promo_offers") else { return self.disabledWorkerResult("promo_offers") }
                    return try await self.promotionalOffersWorker.handleTool(params)
                }

                if params.name.hasPrefix("sandbox_") {
                    guard self.isWorkerEnabled("sandbox") else { return self.disabledWorkerResult("sandbox") }
                    return try await self.sandboxTestersWorker.handleTool(params)
                }

                if params.name.hasPrefix("beta_app_") {
                    guard self.isWorkerEnabled("beta_app") else { return self.disabledWorkerResult("beta_app") }
                    return try await self.betaAppWorker.handleTool(params)
                }

                if params.name.hasPrefix("pre_release_") {
                    guard self.isWorkerEnabled("pre_release") else { return self.disabledWorkerResult("pre_release") }
                    return try await self.preReleaseVersionsWorker.handleTool(params)
                }

                if params.name.hasPrefix("beta_license_") {
                    guard self.isWorkerEnabled("beta_license") else { return self.disabledWorkerResult("beta_license") }
                    return try await self.betaLicenseAgreementsWorker.handleTool(params)
                }

                if params.name.hasPrefix("screenshots_") {
                    guard self.isWorkerEnabled("screenshots") else { return self.disabledWorkerResult("screenshots") }
                    return try await self.screenshotsWorker.handleTool(params)
                }

                if params.name.hasPrefix("custom_pages_") {
                    guard self.isWorkerEnabled("custom_pages") else { return self.disabledWorkerResult("custom_pages") }
                    return try await self.customProductPagesWorker.handleTool(params)
                }

                if params.name.hasPrefix("ppo_") {
                    guard self.isWorkerEnabled("ppo") else { return self.disabledWorkerResult("ppo") }
                    return try await self.productPageOptimizationWorker.handleTool(params)
                }

                if params.name.hasPrefix("promoted_") {
                    guard self.isWorkerEnabled("promoted") else { return self.disabledWorkerResult("promoted") }
                    return try await self.promotedPurchasesWorker.handleTool(params)
                }

                if params.name.hasPrefix("metrics_") {
                    guard self.isWorkerEnabled("metrics") else { return self.disabledWorkerResult("metrics") }
                    return try await self.metricsWorker.handleTool(params)
                }

                if params.name.hasPrefix("review_attachments_") {
                    guard self.isWorkerEnabled("review_attachments") else { return self.disabledWorkerResult("review_attachments") }
                    return try await self.reviewAttachmentsWorker.handleTool(params)
                }

                return CallTool.Result(
                    content: [.text("Error: Unknown tool: \(params.name)")],
                    isError: true
                )
            } catch {
                // Catch all errors and return them as Result
                return CallTool.Result(
                    content: [.text("Error: \(error.localizedDescription)")],
                    isError: true
                )
            }
        }
    }
    
    /// Reinitialize workers with current company configuration
    public func reinitializeWorkers() async throws {
        try await dependencies.updateForCompany()
        self.appsWorker = await AppsWorker(client: dependencies.httpClient)
        self.buildsWorker = await BuildsWorker(httpClient: dependencies.httpClient)
        self.buildProcessingWorker = await BuildProcessingWorker(httpClient: dependencies.httpClient)
        self.buildBetaDetailsWorker = await BuildBetaDetailsWorker(httpClient: dependencies.httpClient)
        self.appLifecycleWorker = await AppLifecycleWorker(httpClient: dependencies.httpClient)
        self.reviewsWorker = await ReviewsWorker(httpClient: dependencies.httpClient)
        self.betaGroupsWorker = await BetaGroupsWorker(httpClient: dependencies.httpClient)
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
        self.offerCodesWorker = await OfferCodesWorker(httpClient: dependencies.httpClient)
        self.winBackOffersWorker = await WinBackOffersWorker(httpClient: dependencies.httpClient)
        self.introductoryOffersWorker = await IntroductoryOffersWorker(httpClient: dependencies.httpClient)
        self.promotionalOffersWorker = await PromotionalOffersWorker(httpClient: dependencies.httpClient)
        self.sandboxTestersWorker = await SandboxTestersWorker(httpClient: dependencies.httpClient)
        self.betaAppWorker = await BetaAppWorker(httpClient: dependencies.httpClient)
        self.preReleaseVersionsWorker = await PreReleaseVersionsWorker(httpClient: dependencies.httpClient)
        self.betaLicenseAgreementsWorker = await BetaLicenseAgreementsWorker(httpClient: dependencies.httpClient)
        self.screenshotsWorker = await ScreenshotsWorker(httpClient: dependencies.httpClient)
        self.customProductPagesWorker = await CustomProductPagesWorker(httpClient: dependencies.httpClient)
        self.productPageOptimizationWorker = await ProductPageOptimizationWorker(httpClient: dependencies.httpClient)
        self.promotedPurchasesWorker = await PromotedPurchasesWorker(httpClient: dependencies.httpClient, uploadService: self.uploadService)
        self.metricsWorker = await MetricsWorker(httpClient: dependencies.httpClient)
        self.reviewAttachmentsWorker = await ReviewAttachmentsWorker(httpClient: dependencies.httpClient, uploadService: self.uploadService)

        print("✅ Workers reinitialized successfully", to: &standardError)
    }
    
    /// Returns error result for disabled worker
    private nonisolated func disabledWorkerResult(_ workerName: String) -> CallTool.Result {
        CallTool.Result(
            content: [.text("Error: Worker '\(workerName)' is disabled. Enable it with --workers \(workerName)")],
            isError: true
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

    private func getOfferCodesTools() async -> [Tool] {
        return await offerCodesWorker.getTools()
    }

    private func getWinBackOffersTools() async -> [Tool] {
        return await winBackOffersWorker.getTools()
    }

    private func getIntroductoryOffersTools() async -> [Tool] {
        return await introductoryOffersWorker.getTools()
    }

    private func getPromotionalOffersTools() async -> [Tool] {
        return await promotionalOffersWorker.getTools()
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

