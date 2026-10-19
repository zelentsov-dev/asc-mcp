import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Legacy public schema compatibility")
struct LegacyPublicSchemaCompatibilityTests {
    @Test("Every 4.1.6 tool accepts its old schema without new requirements")
    func legacySchemas() async throws {
        let baseline = try JSONDecoder().decode([Tool].self, from: loadFixture("public-schemas-4.1.6"))
        let current = Dictionary(uniqueKeysWithValues: try await TestFactory.collectAllWorkerTools().map { ($0.name, $0) })
        #expect(baseline.count == 502)
        for previous in baseline {
            let tool = try #require(current[previous.name])
            compare(previous.inputSchema, tool.inputSchema, path: previous.name)
            #expect(previous.outputSchema == tool.outputSchema, "Output schema changed for \(previous.name)")
        }
    }

    private func compare(_ before: Value, _ after: Value, path: String) {
        guard let old = before.objectValue, let new = after.objectValue else {
            #expect(before == after, "Schema changed at \(path)")
            return
        }
        if let type = old["type"] {
            let oldTypes = type.arrayValue ?? [type]
            let newTypes = new["type"]?.arrayValue ?? new["type"].map { [$0] } ?? []
            #expect(oldTypes.allSatisfy { newTypes.contains($0) }, "Accepted types narrowed at \(path)")
        }
        let oldRequired = Set((old["required"]?.arrayValue ?? []).compactMap(\.stringValue))
        let newRequired = Set((new["required"]?.arrayValue ?? []).compactMap(\.stringValue))
        #expect(newRequired.isSubset(of: oldRequired), "New required arguments at \(path)")
        for (key, value) in old["properties"]?.objectValue ?? [:] {
            guard let current = new["properties"]?.objectValue?[key] else {
                Issue.record("Removed parameter \(path).\(key)")
                continue
            }
            compare(value, current, path: path + "." + key)
        }
        if let values = old["enum"]?.arrayValue, let current = new["enum"]?.arrayValue {
            #expect(values.allSatisfy { current.contains($0) }, "Enum values removed at \(path)")
        }
        if let items = old["items"] {
            if let current = new["items"] { compare(items, current, path: path + "[]") }
        }
        for key in ["minimum", "minLength", "minItems"] {
            if let limit = number(new[key]) {
                #expect(number(old[key]).map { limit <= $0 } == true, "Lower bound tightened at \(path).\(key)")
            }
        }
        for key in ["maximum", "maxLength", "maxItems"] {
            if let limit = number(new[key]) {
                #expect(number(old[key]).map { limit >= $0 } == true, "Upper bound tightened at \(path).\(key)")
            }
        }
        for key in ["oneOf", "anyOf", "allOf", "pattern", "additionalProperties"] {
            #expect(old[key] == new[key], "Constraint changed at \(path).\(key)")
        }
    }

    private func number(_ value: Value?) -> Double? {
        switch value {
        case .int(let value): Double(value)
        case .double(let value): value
        default: nil
        }
    }
}
