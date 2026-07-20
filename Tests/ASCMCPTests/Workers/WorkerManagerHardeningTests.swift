import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("WorkerManager Hardening Tests")
struct WorkerManagerHardeningTests {
    @Test("company_switch failure keeps previous company and dependencies")
    func companySwitchFailureKeepsPreviousCompanyAndDependencies() async throws {
        let goodCompany = TestFactory.makeCompany(id: "good", name: "Good Company")
        let badCompany = Company(
            id: "bad",
            name: "Bad Company",
            keyID: "BAD_KEY_ID",
            issuerID: "BAD_ISSUER_ID",
            privateKeyContent: "not a valid private key"
        )
        let manager = try await TestFactory.makeProductionWorkerManager(
            companies: [goodCompany, badCompany]
        )

        let switchResult = try await manager.routeTool(CallTool.Parameters(
            name: "company_switch",
            arguments: ["company": .string("bad")]
        ))

        #expect(switchResult.isError == true)

        let currentResult = try await manager.routeTool(CallTool.Parameters(
            name: "company_current",
            arguments: nil
        ))
        let current = try object(currentResult.structuredContent)
        let currentCompany = try object(current["currentCompany"])
        #expect(currentCompany["id"] == .string("good"))
        #expect(currentCompany["name"] == .string("Good Company"))

        let authResult = try await manager.routeTool(CallTool.Parameters(
            name: "auth_generate_token",
            arguments: nil
        ))
        #expect(authResult.isError != true)
    }

    @Test("company switches wait for active calls and exclude queued calls")
    func companySwitchesAreExclusiveAndWriterPreferred() async throws {
        let first = TestFactory.makeCompany(
            id: "first",
            name: "First Company",
            keyID: "FIRST_KEY",
            issuerID: "FIRST_ISSUER"
        )
        let second = TestFactory.makeCompany(
            id: "second",
            name: "Second Company",
            keyID: "SECOND_KEY",
            issuerID: "SECOND_ISSUER"
        )
        let third = TestFactory.makeCompany(
            id: "third",
            name: "Third Company",
            keyID: "THIRD_KEY",
            issuerID: "THIRD_ISSUER"
        )
        let transport = BlockingHTTPTransport()
        let context = try await makeManager(
            companies: [first, second, third],
            transport: transport
        )

        let inFlightCall = Task {
            try await context.manager.routeTool(CallTool.Parameters(
                name: "apps_list",
                arguments: nil
            ))
        }
        await transport.waitForRequestCount(1)
        await context.manager.waitForOperationState(activeReaders: 1)

        let firstSwitch = Task {
            try await context.manager.routeTool(CallTool.Parameters(
                name: "company_switch",
                arguments: ["company": .string("second")]
            ))
        }
        await context.manager.waitForOperationState(activeReaders: 1, waitingWriters: 1)

        let secondSwitch = Task {
            try await context.manager.routeTool(CallTool.Parameters(
                name: "company_switch",
                arguments: ["company": .string("third")]
            ))
        }
        await context.manager.waitForOperationState(activeReaders: 1, waitingWriters: 2)

        let queuedCurrentCall = Task {
            try await context.manager.routeTool(CallTool.Parameters(
                name: "company_current",
                arguments: nil
            ))
        }
        await context.manager.waitForOperationState(
            activeReaders: 1,
            waitingReaders: 1,
            waitingWriters: 2
        )

        let currentBeforeRelease = try await context.companiesManager.getCurrentCompany()
        let requestCountBeforeRelease = await transport.recordedRequestCount()
        #expect(currentBeforeRelease == first)
        #expect(requestCountBeforeRelease == 1)

        await transport.releaseAll()

        let inFlightResult = try await inFlightCall.value
        let firstSwitchResult = try await firstSwitch.value
        let secondSwitchResult = try await secondSwitch.value
        #expect(inFlightResult.isError != true)
        #expect(firstSwitchResult.isError != true)
        #expect(secondSwitchResult.isError != true)

        let queuedCurrentResult = try await queuedCurrentCall.value
        let queuedCurrent = try object(queuedCurrentResult.structuredContent)
        let queuedCompany = try object(queuedCurrent["currentCompany"])
        #expect(queuedCompany["id"] == .string("third"))

        let thirdJWTService = try JWTService(company: third)
        let thirdJWT = try await thirdJWTService.getToken()
        let validationResult = try await context.manager.routeTool(CallTool.Parameters(
            name: "auth_validate_token",
            arguments: ["token": .string(thirdJWT)]
        ))
        let validation = try object(validationResult.structuredContent)
        #expect(validation["isValid"] == .bool(true))
    }

    @Test("ordinary calls retain parallel execution")
    func ordinaryCallsRetainParallelExecution() async throws {
        let company = TestFactory.makeCompany()
        let transport = BlockingHTTPTransport()
        let context = try await makeManager(companies: [company], transport: transport)

        let firstCall = Task {
            try await context.manager.routeTool(CallTool.Parameters(
                name: "apps_list",
                arguments: nil
            ))
        }
        let secondCall = Task {
            try await context.manager.routeTool(CallTool.Parameters(
                name: "apps_list",
                arguments: nil
            ))
        }

        await context.manager.waitForOperationState(activeReaders: 2)
        await transport.waitForRequestCount(2)
        let requestCount = await transport.recordedRequestCount()
        #expect(requestCount == 2)

        await transport.releaseAll()
        let firstResult = try await firstCall.value
        let secondResult = try await secondCall.value
        #expect(firstResult.isError != true)
        #expect(secondResult.isError != true)
    }

    @Test("FIFO gate serves an earlier reader before a later switch")
    func fifoGateServesReaderBeforeLaterSwitch() async throws {
        let first = TestFactory.makeCompany(id: "first", name: "First Company")
        let second = TestFactory.makeCompany(id: "second", name: "Second Company")
        let third = TestFactory.makeCompany(id: "third", name: "Third Company")
        let transport = BlockingHTTPTransport()
        let context = try await makeManager(
            companies: [first, second, third],
            transport: transport
        )

        let inFlightCall = Task {
            try await context.manager.routeTool(CallTool.Parameters(
                name: "apps_list",
                arguments: nil
            ))
        }
        await transport.waitForRequestCount(1)

        let firstSwitch = Task {
            try await context.manager.routeTool(CallTool.Parameters(
                name: "company_switch",
                arguments: ["company": .string("second")]
            ))
        }
        await context.manager.waitForOperationState(activeReaders: 1, waitingWriters: 1)

        let queuedReader = Task {
            try await context.manager.routeTool(CallTool.Parameters(
                name: "company_current",
                arguments: nil
            ))
        }
        await context.manager.waitForOperationState(
            activeReaders: 1,
            waitingReaders: 1,
            waitingWriters: 1
        )

        let laterSwitch = Task {
            try await context.manager.routeTool(CallTool.Parameters(
                name: "company_switch",
                arguments: ["company": .string("third")]
            ))
        }
        await context.manager.waitForOperationState(
            activeReaders: 1,
            waitingReaders: 1,
            waitingWriters: 2
        )

        await transport.releaseAll()
        let inFlightResult = try await inFlightCall.value
        let firstSwitchResult = try await firstSwitch.value
        let readerResult = try await queuedReader.value
        let laterSwitchResult = try await laterSwitch.value
        #expect(inFlightResult.isError != true)
        #expect(firstSwitchResult.isError != true)
        #expect(laterSwitchResult.isError != true)

        let readerPayload = try object(readerResult.structuredContent)
        let readerCompany = try object(readerPayload["currentCompany"])
        #expect(readerCompany["id"] == .string("second"))

        let finalCompany = try await context.companiesManager.getCurrentCompany()
        #expect(finalCompany == third)
    }

    @Test("cancelled queued switch does not change account scope")
    func cancelledQueuedSwitchDoesNotChangeAccountScope() async throws {
        let first = TestFactory.makeCompany(id: "first", name: "First Company")
        let second = TestFactory.makeCompany(id: "second", name: "Second Company")
        let transport = BlockingHTTPTransport()
        let context = try await makeManager(companies: [first, second], transport: transport)

        let inFlightCall = Task {
            try await context.manager.routeTool(CallTool.Parameters(
                name: "apps_list",
                arguments: nil
            ))
        }
        await transport.waitForRequestCount(1)

        let switchCall = Task {
            try await context.manager.routeTool(CallTool.Parameters(
                name: "company_switch",
                arguments: ["company": .string("second")]
            ))
        }
        await context.manager.waitForOperationState(activeReaders: 1, waitingWriters: 1)
        switchCall.cancel()

        await context.manager.waitForOperationState(activeReaders: 1, waitingWriters: 0)

        let currentResult = try await context.manager.routeTool(CallTool.Parameters(
            name: "company_current",
            arguments: nil
        ))
        let current = try object(currentResult.structuredContent)
        let currentCompany = try object(current["currentCompany"])
        #expect(currentCompany["id"] == .string("first"))

        await transport.releaseAll()
        let inFlightResult = try await inFlightCall.value
        #expect(inFlightResult.isError != true)

        do {
            _ = try await switchCall.value
            Issue.record("Expected cancellation error")
        } catch is CancellationError {
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }
}

private struct ManagerContext: Sendable {
    let manager: WorkerManager
    let companiesManager: CompaniesManager
}

private func makeManager(
    companies: [Company],
    transport: BlockingHTTPTransport
) async throws -> ManagerContext {
    let companiesManager = try TestFactory.makeCompaniesManager(
        companies: companies,
        defaultURL: "https://api.example.test"
    )
    let initialCompany = try await companiesManager.getCurrentCompany()
    let jwtService = try JWTService(company: initialCompany)
    let httpClient = await HTTPClient(
        jwtService: jwtService,
        baseURL: "https://api.example.test",
        transport: transport,
        maxRetries: 1
    )
    let companiesWorker = CompaniesWorker(manager: companiesManager)
    let dependencies = WorkerDependencies(
        companiesWorker: companiesWorker,
        jwtService: jwtService,
        httpClient: httpClient,
        authWorker: AuthWorker(jwtService: jwtService)
    )
    let manager = await WorkerManager(dependencies: dependencies)
    return ManagerContext(manager: manager, companiesManager: companiesManager)
}

private actor BlockingHTTPTransport: HTTPTransport {
    private struct RequestWaiter: Sendable {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var requestCount = 0
    private var requestWaiters: [RequestWaiter] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        notifyRequestWaiters()
        await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.example.test/v1/apps")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        let body = #"{"data":[],"links":{"self":"https://api.example.test/v1/apps"}}"#
        return (Data(body.utf8), response)
    }

    func waitForRequestCount(_ count: Int) async {
        guard requestCount < count else { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(RequestWaiter(count: count, continuation: continuation))
        }
    }

    func recordedRequestCount() -> Int {
        requestCount
    }

    func releaseAll() {
        let continuations = releaseContinuations
        releaseContinuations.removeAll(keepingCapacity: true)
        continuations.forEach { $0.resume() }
    }

    private func notifyRequestWaiters() {
        var remaining: [RequestWaiter] = []
        var ready: [CheckedContinuation<Void, Never>] = []
        for waiter in requestWaiters {
            if requestCount >= waiter.count {
                ready.append(waiter.continuation)
            } else {
                remaining.append(waiter)
            }
        }
        requestWaiters = remaining
        ready.forEach { $0.resume() }
    }
}

private func object(_ value: Value?) throws -> [String: Value] {
    guard case .object(let object) = value else {
        Issue.record("Expected object, got \(String(describing: value))")
        throw TestFailure.expectedObject
    }
    return object
}

private enum TestFailure: Error {
    case expectedObject
}
