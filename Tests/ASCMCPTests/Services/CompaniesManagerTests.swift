import Foundation
import Testing
@testable import asc_mcp

@Suite("CompaniesManager Tests")
struct CompaniesManagerTests {
    @Test("explicit malformed config reports invalid JSON")
    func explicitMalformedConfigReportsInvalidJSON() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-mcp-malformed-\(UUID().uuidString).json")
        try "{not json".write(to: url, atomically: true, encoding: .utf8)

        do {
            _ = try CompaniesManager(configPath: url.path)
            Issue.record("Expected invalid config error")
        } catch let error as CompanyError {
            guard case .invalidConfig(let path, _) = error else {
                Issue.record("Expected invalidConfig, got \(error)")
                return
            }
            #expect(path == url.path)
        }
    }

    @Test("explicit empty config reports empty companies")
    func explicitEmptyConfigReportsEmptyCompanies() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-mcp-empty-\(UUID().uuidString).json")
        try #"{"companies":[]}"#.write(to: url, atomically: true, encoding: .utf8)

        do {
            _ = try CompaniesManager(configPath: url.path)
            Issue.record("Expected empty companies error")
        } catch let error as CompanyError {
            guard case .emptyCompanies(let path) = error else {
                Issue.record("Expected emptyCompanies, got \(error)")
                return
            }
            #expect(path == url.path)
        }
    }

    @Test("explicit missing config reports missing path")
    func explicitMissingConfigReportsMissingPath() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("asc-mcp-missing-\(UUID().uuidString).json")
            .path

        do {
            _ = try CompaniesManager(configPath: path)
            Issue.record("Expected missing config error")
        } catch let error as CompanyError {
            guard case .configFileMissing(let missingPath) = error else {
                Issue.record("Expected configFileMissing, got \(error)")
                return
            }
            #expect(missingPath == path)
        }
    }

    @Test("company resolution rejects empty and ambiguous queries")
    func companyResolutionRejectsEmptyAndAmbiguousQueries() async throws {
        let north = TestFactory.makeCompany(id: "north", name: "Acme North")
        let south = TestFactory.makeCompany(id: "south", name: "Acme South")
        let manager = try TestFactory.makeCompaniesManager(companies: [north, south])

        do {
            _ = try await manager.resolveCompany("  \n ")
            Issue.record("Expected empty company identifier error")
        } catch let error as CompanyError {
            guard case .emptyCompanyIdentifier = error else {
                Issue.record("Expected emptyCompanyIdentifier, got \(error)")
                return
            }
        }

        do {
            _ = try await manager.resolveCompany("acme")
            Issue.record("Expected ambiguous company error")
        } catch let error as CompanyError {
            guard case .ambiguousCompany(let query, let matches) = error else {
                Issue.record("Expected ambiguousCompany, got \(error)")
                return
            }
            #expect(query == "acme")
            #expect(matches == ["Acme North", "Acme South"])
        }
    }

    @Test("company resolution prioritizes trimmed exact ID and exact name")
    func companyResolutionPrioritizesExactMatches() async throws {
        let north = TestFactory.makeCompany(id: "north", name: "Acme")
        let south = TestFactory.makeCompany(id: "south", name: "Acme South")
        let manager = try TestFactory.makeCompaniesManager(companies: [north, south])

        let byID = try await manager.resolveCompany(" NORTH ")
        let byExactName = try await manager.resolveCompany("acme")
        let byUniquePartial = try await manager.resolveCompany("me sou")

        #expect(byID == north)
        #expect(byExactName == north)
        #expect(byUniquePartial == south)
    }

    @Test("company resolution rejects duplicate exact IDs")
    func companyResolutionRejectsDuplicateExactIDs() async throws {
        let first = TestFactory.makeCompany(id: "shared", name: "First Company")
        let second = TestFactory.makeCompany(id: "shared", name: "Second Company")
        let manager = try TestFactory.makeCompaniesManager(companies: [first, second])

        do {
            _ = try await manager.resolveCompany(" SHARED ")
            Issue.record("Expected ambiguous company error")
        } catch let error as CompanyError {
            guard case .ambiguousCompany(let query, let matches) = error else {
                Issue.record("Expected ambiguousCompany, got \(error)")
                return
            }
            #expect(query == "SHARED")
            #expect(matches == ["First Company (ID: shared)", "Second Company (ID: shared)"])
        }
    }
}
