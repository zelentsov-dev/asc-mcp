import Testing
import Foundation
@testable import asc_mcp

@Suite("CompanyError Tests")
struct CompanyErrorTests {
    @Test func companyNotFound() {
        let error = CompanyError.companyNotFound("Acme")
        #expect(error.errorDescription?.contains("Acme") == true)
        #expect(error.errorDescription?.contains("not found") == true)
    }

    @Test func companyNotFoundExactFormat() {
        let error = CompanyError.companyNotFound("TestCorp")
        #expect(error.errorDescription == "Company not found: TestCorp")
    }

    @Test func noCompanySelected() {
        let error = CompanyError.noCompanySelected
        #expect(error.errorDescription?.contains("No company selected") == true)
    }

    @Test func configFileNotFound() {
        let error = CompanyError.configFileNotFound
        #expect(error.errorDescription?.contains("Configuration not found") == true)
    }

    @Test func errorConformsToLocalizedError() {
        let error: any LocalizedError = CompanyError.noCompanySelected
        #expect(error.errorDescription != nil)
    }

    @Test func errorIsSendable() {
        let error: any Sendable = CompanyError.configFileNotFound
        _ = error // Compiles means Sendable conformance works
    }
}
