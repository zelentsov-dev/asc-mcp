import Foundation
import MCP

fileprivate struct WorkerAccountDependencies: Sendable {
    let jwtService: JWTService
    let httpClient: HTTPClient
    let authWorker: AuthWorker
}

/// Dependencies container for WorkerManager
public actor WorkerDependencies: Sendable {
    public let companiesWorker: CompaniesWorker
    private var account: WorkerAccountDependencies

    public var jwtService: JWTService { account.jwtService }
    public var httpClient: HTTPClient { account.httpClient }
    public var authWorker: AuthWorker { account.authWorker }

    public init(
        companiesWorker: CompaniesWorker,
        jwtService: JWTService,
        httpClient: HTTPClient,
        authWorker: AuthWorker
    ) {
        self.companiesWorker = companiesWorker
        self.account = WorkerAccountDependencies(
            jwtService: jwtService,
            httpClient: httpClient,
            authWorker: authWorker
        )
    }

    fileprivate func makeAccount(for company: Company) async throws -> WorkerAccountDependencies {
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

        return WorkerAccountDependencies(
            jwtService: newJWTService,
            httpClient: newHTTPClient,
            authWorker: newAuthWorker
        )
    }

    fileprivate func snapshot() -> (CompaniesWorker, WorkerAccountDependencies) {
        (companiesWorker, account)
    }

    fileprivate func install(_ account: WorkerAccountDependencies) {
        self.account = account
    }
}

private actor WorkerOperationGate {
    private enum Access: Sendable, Equatable {
        case read
        case write
    }

    private struct Waiter: Sendable {
        let id: UUID
        let access: Access
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct Criteria: Sendable {
        let activeReaders: Int?
        let writerActive: Bool?
        let waitingReaders: Int?
        let waitingWriters: Int?
    }

    private struct StateWaiter: Sendable {
        let criteria: Criteria
        let continuation: CheckedContinuation<Void, Never>
    }

    private var activeReaders = 0
    private var writerActive = false
    private var waiters: [Waiter] = []
    private var stateWaiters: [StateWaiter] = []

    func beginRead() async throws {
        try await begin(.read)
    }

    func beginWrite() async throws {
        try await begin(.write)
    }

    func endRead() {
        precondition(activeReaders > 0)
        activeReaders -= 1
        drain()
    }

    func endWrite() {
        precondition(writerActive)
        writerActive = false
        drain()
    }

    func waitForState(
        activeReaders: Int? = nil,
        writerActive: Bool? = nil,
        waitingReaders: Int? = nil,
        waitingWriters: Int? = nil
    ) async {
        let criteria = Criteria(
            activeReaders: activeReaders,
            writerActive: writerActive,
            waitingReaders: waitingReaders,
            waitingWriters: waitingWriters
        )
        guard !matches(criteria) else { return }

        await withCheckedContinuation { continuation in
            stateWaiters.append(StateWaiter(criteria: criteria, continuation: continuation))
        }
    }

    private func matches(_ criteria: Criteria) -> Bool {
        if let value = criteria.activeReaders, value != activeReaders { return false }
        if let value = criteria.writerActive, value != writerActive { return false }
        if let value = criteria.waitingReaders, value != waitingCount(for: .read) { return false }
        if let value = criteria.waitingWriters, value != waitingCount(for: .write) { return false }
        return true
    }

    private func begin(_ access: Access) async throws {
        try Task.checkCancellation()
        if canStartImmediately(access) {
            grant(access)
            notifyStateWaiters()
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters.append(Waiter(id: id, access: access, continuation: continuation))
                notifyStateWaiters()
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func canStartImmediately(_ access: Access) -> Bool {
        guard !writerActive, waiters.isEmpty else { return false }
        switch access {
        case .read:
            return true
        case .write:
            return activeReaders == 0
        }
    }

    private func grant(_ access: Access) {
        switch access {
        case .read:
            precondition(!writerActive)
            activeReaders += 1
        case .write:
            precondition(!writerActive && activeReaders == 0)
            writerActive = true
        }
    }

    private func drain() {
        guard !writerActive, let first = waiters.first else {
            notifyStateWaiters()
            return
        }

        switch first.access {
        case .write:
            guard activeReaders == 0 else {
                notifyStateWaiters()
                return
            }
            let waiter = waiters.removeFirst()
            grant(.write)
            notifyStateWaiters()
            waiter.continuation.resume()
        case .read:
            var continuations: [CheckedContinuation<Void, any Error>] = []
            while waiters.first?.access == .read {
                let waiter = waiters.removeFirst()
                grant(.read)
                continuations.append(waiter.continuation)
            }
            notifyStateWaiters()
            continuations.forEach { $0.resume() }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        drain()
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func waitingCount(for access: Access) -> Int {
        waiters.lazy.filter { $0.access == access }.count
    }

    private func notifyStateWaiters() {
        var remaining: [StateWaiter] = []
        var ready: [CheckedContinuation<Void, Never>] = []
        for waiter in stateWaiters {
            if matches(waiter.criteria) {
                ready.append(waiter.continuation)
            } else {
                remaining.append(waiter)
            }
        }
        stateWaiters = remaining
        ready.forEach { $0.resume() }
    }
}

private struct WorkerGraph: Sendable {
    let appsWorker: AppsWorker
    let accessibilityWorker: AccessibilityWorker
    let webhooksWorker: WebhooksWorker
    let xcodeCloudWorker: XcodeCloudWorker
    let buildsWorker: BuildsWorker
    let buildUploadsWorker: BuildUploadsWorker
    let buildProcessingWorker: BuildProcessingWorker
    let exportComplianceWorker: ExportComplianceWorker
    let buildBetaDetailsWorker: BuildBetaDetailsWorker
    let appLifecycleWorker: AppLifecycleWorker
    let reviewsWorker: ReviewsWorker
    let betaGroupsWorker: BetaGroupsWorker
    let betaFeedbackWorker: BetaFeedbackWorker
    let inAppPurchasesWorker: InAppPurchasesWorker
    let provisioningWorker: ProvisioningWorker
    let betaTestersWorker: BetaTestersWorker
    let appInfoWorker: AppInfoWorker
    let pricingWorker: PricingWorker
    let usersWorker: UsersWorker
    let appEventsWorker: AppEventsWorker
    let analyticsWorker: AnalyticsWorker
    let subscriptionsWorker: SubscriptionsWorker
    let sandboxTestersWorker: SandboxTestersWorker
    let betaAppWorker: BetaAppWorker
    let preReleaseVersionsWorker: PreReleaseVersionsWorker
    let betaLicenseAgreementsWorker: BetaLicenseAgreementsWorker
    let screenshotsWorker: ScreenshotsWorker
    let customProductPagesWorker: CustomProductPagesWorker
    let productPageOptimizationWorker: ProductPageOptimizationWorker
    let promotedPurchasesWorker: PromotedPurchasesWorker
    let metricsWorker: MetricsWorker
    let reviewAttachmentsWorker: ReviewAttachmentsWorker
    let reviewSubmissionsWorker: ReviewSubmissionsWorker

    init(httpClient: HTTPClient, companiesManager: CompaniesManager, uploadService: UploadService) {
        self.appsWorker = AppsWorker(client: httpClient)
        self.accessibilityWorker = AccessibilityWorker(httpClient: httpClient)
        self.webhooksWorker = WebhooksWorker(httpClient: httpClient)
        self.xcodeCloudWorker = XcodeCloudWorker(httpClient: httpClient)
        self.buildsWorker = BuildsWorker(httpClient: httpClient)
        self.buildUploadsWorker = BuildUploadsWorker(httpClient: httpClient, uploadService: uploadService)
        self.buildProcessingWorker = BuildProcessingWorker(httpClient: httpClient)
        self.exportComplianceWorker = ExportComplianceWorker(httpClient: httpClient, uploadService: uploadService)
        self.buildBetaDetailsWorker = BuildBetaDetailsWorker(httpClient: httpClient)
        self.appLifecycleWorker = AppLifecycleWorker(httpClient: httpClient)
        self.reviewsWorker = ReviewsWorker(httpClient: httpClient)
        self.betaGroupsWorker = BetaGroupsWorker(httpClient: httpClient)
        self.betaFeedbackWorker = BetaFeedbackWorker(httpClient: httpClient)
        self.inAppPurchasesWorker = InAppPurchasesWorker(httpClient: httpClient, uploadService: uploadService)
        self.provisioningWorker = ProvisioningWorker(httpClient: httpClient)
        self.betaTestersWorker = BetaTestersWorker(httpClient: httpClient)
        self.appInfoWorker = AppInfoWorker(httpClient: httpClient)
        self.pricingWorker = PricingWorker(httpClient: httpClient)
        self.usersWorker = UsersWorker(httpClient: httpClient)
        self.appEventsWorker = AppEventsWorker(httpClient: httpClient)
        self.analyticsWorker = AnalyticsWorker(httpClient: httpClient, companiesManager: companiesManager)
        self.subscriptionsWorker = SubscriptionsWorker(httpClient: httpClient, uploadService: uploadService)
        self.sandboxTestersWorker = SandboxTestersWorker(httpClient: httpClient)
        self.betaAppWorker = BetaAppWorker(httpClient: httpClient)
        self.preReleaseVersionsWorker = PreReleaseVersionsWorker(httpClient: httpClient)
        self.betaLicenseAgreementsWorker = BetaLicenseAgreementsWorker(httpClient: httpClient)
        self.screenshotsWorker = ScreenshotsWorker(httpClient: httpClient, uploadService: uploadService)
        self.customProductPagesWorker = CustomProductPagesWorker(httpClient: httpClient)
        self.productPageOptimizationWorker = ProductPageOptimizationWorker(httpClient: httpClient)
        self.promotedPurchasesWorker = PromotedPurchasesWorker(httpClient: httpClient, uploadService: uploadService)
        self.metricsWorker = MetricsWorker(httpClient: httpClient)
        self.reviewAttachmentsWorker = ReviewAttachmentsWorker(httpClient: httpClient, uploadService: uploadService)
        self.reviewSubmissionsWorker = ReviewSubmissionsWorker(httpClient: httpClient)
    }
}

private struct WorkerRuntime: Sendable {
    let account: WorkerAccountDependencies
    let graph: WorkerGraph
}

/// Manager for all workers
public actor WorkerManager {
    static let validWorkerFilterKeys: Set<String> = [
        "company", "auth", "apps", "accessibility", "webhooks", "xcode_cloud",
        "builds", "build_uploads", "build_processing", "export_compliance", "build_beta", "versions", "reviews",
        "beta_groups", "beta_feedback", "beta_testers", "iap", "provisioning",
        "app_info", "pricing", "users", "app_events", "analytics", "subscriptions",
        "sandbox", "beta_app", "pre_release", "beta_license", "screenshots",
        "custom_pages", "ppo", "promoted", "metrics", "review_attachments",
        "review_submissions"
    ]

    private let dependencies: WorkerDependencies
    private let companiesWorker: CompaniesWorker
    private let operationGate = WorkerOperationGate()
    /// Set of enabled worker names. nil = all workers enabled.
    private let enabledWorkers: Set<String>?
    /// Blocks App Store Connect mutation tools before they reach worker handlers.
    private let readOnlyMode: Bool
    private var runtime: WorkerRuntime
    private let uploadService: UploadService

    /// Direct initialization with injected dependencies for internal tests.
    /// - Parameters:
    ///   - dependencies: Shared worker dependencies.
    ///   - enabledWorkers: Set of worker names to enable, nil = all workers.
    ///   - readOnlyMode: Whether mutation tools should be blocked before handler execution.
    public init(dependencies: WorkerDependencies, enabledWorkers: Set<String>? = nil, readOnlyMode: Bool = false) async {
        let (companiesWorker, account) = await dependencies.snapshot()
        let uploadService = UploadService()
        let graph = WorkerGraph(
            httpClient: account.httpClient,
            companiesManager: companiesWorker.manager,
            uploadService: uploadService
        )

        self.dependencies = dependencies
        self.companiesWorker = companiesWorker
        self.enabledWorkers = enabledWorkers
        self.readOnlyMode = readOnlyMode
        self.uploadService = uploadService
        self.runtime = WorkerRuntime(account: account, graph: graph)
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
        let companiesWorker = companiesWorker
        let authWorker = runtime.account.authWorker
        let graph = runtime.graph

        return [
            WorkerDescriptor(
                key: "company",
                enabledKeys: [],
                prefixes: ["company_"],
                getTools: { await companiesWorker.getTools() },
                handle: { try await companiesWorker.handleTool($0) }
            ),
            WorkerDescriptor(
                key: "auth",
                enabledKeys: [],
                prefixes: ["auth_"],
                getTools: { await authWorker.getTools() },
                handle: { try await authWorker.handleTool($0) }
            ),
            WorkerDescriptor(key: "apps", enabledKeys: ["apps"], prefixes: ["apps_"], getTools: { await graph.appsWorker.getTools() }, handle: { try await graph.appsWorker.handleTool($0) }),
            WorkerDescriptor(key: "accessibility", enabledKeys: ["accessibility"], prefixes: ["accessibility_"], getTools: { await graph.accessibilityWorker.getTools() }, handle: { try await graph.accessibilityWorker.handleTool($0) }),
            WorkerDescriptor(key: "webhooks", enabledKeys: ["webhooks"], prefixes: ["webhooks_"], getTools: { await graph.webhooksWorker.getTools() }, handle: { try await graph.webhooksWorker.handleTool($0) }),
            WorkerDescriptor(key: "xcode_cloud", enabledKeys: ["xcode_cloud"], prefixes: ["xcode_cloud_"], getTools: { await graph.xcodeCloudWorker.getTools() }, handle: { try await graph.xcodeCloudWorker.handleTool($0) }),
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
                getTools: { await graph.buildBetaDetailsWorker.getTools() },
                handle: { try await graph.buildBetaDetailsWorker.handleTool($0) }
            ),
            WorkerDescriptor(
                key: "build_processing",
                enabledKeys: ["build_processing", "builds"],
                prefixes: [
                    "builds_get_processing_",
                    "builds_update_encryption",
                    "builds_check_readiness"
                ],
                getTools: { await graph.buildProcessingWorker.getTools() },
                handle: { try await graph.buildProcessingWorker.handleTool($0) }
            ),
            WorkerDescriptor(
                key: "export_compliance",
                enabledKeys: ["export_compliance"],
                prefixes: ["export_compliance_"],
                getTools: { await graph.exportComplianceWorker.getTools() },
                handle: { try await graph.exportComplianceWorker.handleTool($0) }
            ),
            WorkerDescriptor(key: "build_uploads", enabledKeys: ["build_uploads"], prefixes: ["build_uploads_"], getTools: { await graph.buildUploadsWorker.getTools() }, handle: { try await graph.buildUploadsWorker.handleTool($0) }),
            WorkerDescriptor(key: "builds", enabledKeys: ["builds"], prefixes: ["builds_"], getTools: { await graph.buildsWorker.getTools() }, handle: { try await graph.buildsWorker.handleTool($0) }),
            WorkerDescriptor(key: "versions", enabledKeys: ["versions"], prefixes: ["app_versions_"], getTools: { await graph.appLifecycleWorker.getTools() }, handle: { try await graph.appLifecycleWorker.handleTool($0) }),
            WorkerDescriptor(key: "reviews", enabledKeys: ["reviews"], prefixes: ["reviews_"], getTools: { await graph.reviewsWorker.getTools() }, handle: { try await graph.reviewsWorker.handleTool($0) }),
            WorkerDescriptor(key: "beta_groups", enabledKeys: ["beta_groups"], prefixes: ["beta_groups_"], getTools: { await graph.betaGroupsWorker.getTools() }, handle: { try await graph.betaGroupsWorker.handleTool($0) }),
            WorkerDescriptor(key: "beta_feedback", enabledKeys: ["beta_feedback"], prefixes: ["beta_feedback_"], getTools: { await graph.betaFeedbackWorker.getTools() }, handle: { try await graph.betaFeedbackWorker.handleTool($0) }),
            WorkerDescriptor(key: "iap", enabledKeys: ["iap"], prefixes: ["iap_"], getTools: { await graph.inAppPurchasesWorker.getTools() }, handle: { try await graph.inAppPurchasesWorker.handleTool($0) }),
            WorkerDescriptor(key: "provisioning", enabledKeys: ["provisioning"], prefixes: ["provisioning_"], getTools: { await graph.provisioningWorker.getTools() }, handle: { try await graph.provisioningWorker.handleTool($0) }),
            WorkerDescriptor(key: "beta_testers", enabledKeys: ["beta_testers"], prefixes: ["beta_testers_"], getTools: { await graph.betaTestersWorker.getTools() }, handle: { try await graph.betaTestersWorker.handleTool($0) }),
            WorkerDescriptor(key: "app_info", enabledKeys: ["app_info"], prefixes: ["app_info_"], getTools: { await graph.appInfoWorker.getTools() }, handle: { try await graph.appInfoWorker.handleTool($0) }),
            WorkerDescriptor(key: "pricing", enabledKeys: ["pricing"], prefixes: ["pricing_"], getTools: { await graph.pricingWorker.getTools() }, handle: { try await graph.pricingWorker.handleTool($0) }),
            WorkerDescriptor(key: "users", enabledKeys: ["users"], prefixes: ["users_"], getTools: { await graph.usersWorker.getTools() }, handle: { try await graph.usersWorker.handleTool($0) }),
            WorkerDescriptor(key: "app_events", enabledKeys: ["app_events"], prefixes: ["app_events_"], getTools: { await graph.appEventsWorker.getTools() }, handle: { try await graph.appEventsWorker.handleTool($0) }),
            WorkerDescriptor(key: "analytics", enabledKeys: ["analytics"], prefixes: ["analytics_"], getTools: { await graph.analyticsWorker.getTools() }, handle: { try await graph.analyticsWorker.handleTool($0) }),
            WorkerDescriptor(key: "subscriptions", enabledKeys: ["subscriptions"], prefixes: ["subscriptions_"], getTools: { await graph.subscriptionsWorker.getTools() }, handle: { try await graph.subscriptionsWorker.handleTool($0) }),
            WorkerDescriptor(key: "sandbox", enabledKeys: ["sandbox"], prefixes: ["sandbox_"], getTools: { await graph.sandboxTestersWorker.getTools() }, handle: { try await graph.sandboxTestersWorker.handleTool($0) }),
            WorkerDescriptor(key: "beta_app", enabledKeys: ["beta_app"], prefixes: ["beta_app_"], getTools: { await graph.betaAppWorker.getTools() }, handle: { try await graph.betaAppWorker.handleTool($0) }),
            WorkerDescriptor(key: "pre_release", enabledKeys: ["pre_release"], prefixes: ["pre_release_"], getTools: { await graph.preReleaseVersionsWorker.getTools() }, handle: { try await graph.preReleaseVersionsWorker.handleTool($0) }),
            WorkerDescriptor(key: "beta_license", enabledKeys: ["beta_license"], prefixes: ["beta_license_"], getTools: { await graph.betaLicenseAgreementsWorker.getTools() }, handle: { try await graph.betaLicenseAgreementsWorker.handleTool($0) }),
            WorkerDescriptor(key: "screenshots", enabledKeys: ["screenshots"], prefixes: ["screenshots_"], getTools: { await graph.screenshotsWorker.getTools() }, handle: { try await graph.screenshotsWorker.handleTool($0) }),
            WorkerDescriptor(key: "custom_pages", enabledKeys: ["custom_pages"], prefixes: ["custom_pages_"], getTools: { await graph.customProductPagesWorker.getTools() }, handle: { try await graph.customProductPagesWorker.handleTool($0) }),
            WorkerDescriptor(key: "ppo", enabledKeys: ["ppo"], prefixes: ["ppo_"], getTools: { await graph.productPageOptimizationWorker.getTools() }, handle: { try await graph.productPageOptimizationWorker.handleTool($0) }),
            WorkerDescriptor(key: "promoted", enabledKeys: ["promoted"], prefixes: ["promoted_"], getTools: { await graph.promotedPurchasesWorker.getTools() }, handle: { try await graph.promotedPurchasesWorker.handleTool($0) }),
            WorkerDescriptor(key: "metrics", enabledKeys: ["metrics"], prefixes: ["metrics_"], getTools: { await graph.metricsWorker.getTools() }, handle: { try await graph.metricsWorker.handleTool($0) }),
            WorkerDescriptor(key: "review_attachments", enabledKeys: ["review_attachments"], prefixes: ["review_attachments_"], getTools: { await graph.reviewAttachmentsWorker.getTools() }, handle: { try await graph.reviewAttachmentsWorker.handleTool($0) }),
            WorkerDescriptor(key: "review_submissions", enabledKeys: ["review_submissions"], prefixes: ["review_submissions_"], getTools: { await graph.reviewSubmissionsWorker.getTools() }, handle: { try await graph.reviewSubmissionsWorker.handleTool($0) })
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
                return try await self.executeTool(
                    params,
                    includeRuntimeMetadata: true,
                    convertErrorsToResults: true
                )
            } catch {
                return MCPResult.error(error)
            }
        }
    }

    func routeTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        try await executeTool(
            params,
            includeRuntimeMetadata: false,
            convertErrorsToResults: false
        )
    }

    private func executeTool(
        _ params: CallTool.Parameters,
        includeRuntimeMetadata: Bool,
        convertErrorsToResults: Bool
    ) async throws -> CallTool.Result {
        let isWrite = params.name == "company_switch"
        if isWrite {
            try await operationGate.beginWrite()
        } else {
            try await operationGate.beginRead()
        }

        do {
            try Task.checkCancellation()
            let result: CallTool.Result
            do {
                result = try await routeToolWithAccess(params)
            } catch {
                guard convertErrorsToResults else { throw error }
                result = errorResult(error)
            }

            let finalResult: CallTool.Result
            if includeRuntimeMetadata {
                finalResult = await withRuntimeMetadata(result)
            } else {
                finalResult = result
            }
            let transportResult = MCPResult.normalizeForTransport(finalResult)
            if isWrite {
                await operationGate.endWrite()
            } else {
                await operationGate.endRead()
            }
            return transportResult
        } catch {
            if isWrite {
                await operationGate.endWrite()
            } else {
                await operationGate.endRead()
            }
            throw error
        }
    }

    private func routeToolWithAccess(_ params: CallTool.Parameters) async throws -> CallTool.Result {
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
        let httpClient = runtime.account.httpClient
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

    private nonisolated func errorResult(_ error: Error) -> CallTool.Result {
        MCPResult.error(error)
    }
    
    private func switchCompanyTransactionally(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let companyValue = arguments["company"],
              let companyIdOrName = companyValue.stringValue else {
            return MCPResult.error("Required parameter 'company' (ID or name)")
        }

        do {
            let manager = companiesWorker.manager
            let company = try await manager.resolveCompany(companyIdOrName)
            let candidate = try await makeRuntime(for: company)
            try Task.checkCancellation()
            await install(candidate)
            await manager.setCurrentCompany(company)
            print("Workers reinitialized successfully", to: &standardError)
            return companiesWorker.makeSwitchResult(for: company)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return MCPResult.error("Error switching company: \(error.localizedDescription)")
        }
    }

    /// Reinitialize workers with the currently active company configuration.
    /// - Throws: JWT/private-key errors if dependency replacement cannot be built.
    public func reinitializeWorkers() async throws {
        try await operationGate.beginWrite()
        do {
            try Task.checkCancellation()
            let company = try await companiesWorker.manager.getCurrentCompany()
            let candidate = try await makeRuntime(for: company)
            try Task.checkCancellation()
            await install(candidate)
            await operationGate.endWrite()
            print("Workers reinitialized successfully", to: &standardError)
        } catch {
            await operationGate.endWrite()
            throw error
        }
    }

    /// Reinitialize workers with a prepared company configuration.
    /// - Parameter company: Company whose credentials should back all API workers.
    /// - Throws: JWT/private-key errors if dependency replacement cannot be built.
    public func reinitializeWorkers(for company: Company) async throws {
        try await operationGate.beginWrite()
        do {
            try Task.checkCancellation()
            let candidate = try await makeRuntime(for: company)
            try Task.checkCancellation()
            await install(candidate)
            await companiesWorker.manager.setCurrentCompany(company)
            await operationGate.endWrite()
            print("Workers reinitialized successfully", to: &standardError)
        } catch {
            await operationGate.endWrite()
            throw error
        }
    }

    private func makeRuntime(for company: Company) async throws -> WorkerRuntime {
        let account = try await dependencies.makeAccount(for: company)
        let graph = WorkerGraph(
            httpClient: account.httpClient,
            companiesManager: companiesWorker.manager,
            uploadService: uploadService
        )
        return WorkerRuntime(account: account, graph: graph)
    }

    private func install(_ candidate: WorkerRuntime) async {
        await dependencies.install(candidate.account)
        runtime = candidate
    }

    func waitForOperationState(
        activeReaders: Int? = nil,
        writerActive: Bool? = nil,
        waitingReaders: Int? = nil,
        waitingWriters: Int? = nil
    ) async {
        await operationGate.waitForState(
            activeReaders: activeReaders,
            writerActive: writerActive,
            waitingReaders: waitingReaders,
            waitingWriters: waitingWriters
        )
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

}
