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
