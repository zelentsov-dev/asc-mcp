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
}
