import Foundation

struct ASCOpenAPIOperation: Sendable, Equatable {
    let method: String
    let path: String
    let operationID: String
    let summary: String?
    let tags: [String]
}

struct ASCOpenAPISpec: Sendable, Equatable {
    let title: String
    let version: String
    let openAPIVersion: String
    let paths: [String]
    let operations: [ASCOpenAPIOperation]

    /// Parse the Apple OpenAPI JSON document into the metadata needed by drift tooling.
    /// - Parameter data: Raw `openapi.oas.json` data.
    /// - Returns: Parsed specification summary with sorted paths and operations.
    /// - Throws: `ASCOpenAPIParseError` when the document is not a valid OpenAPI JSON object.
    static func parse(_ data: Data) throws -> ASCOpenAPISpec {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any] else {
            throw ASCOpenAPIParseError.invalidRootObject
        }

        guard let pathsObject = root["paths"] as? [String: Any] else {
            throw ASCOpenAPIParseError.missingPaths
        }

        let info = root["info"] as? [String: Any]
        let sortedPaths = pathsObject.keys.sorted()
        let operations = sortedPaths.flatMap { path -> [ASCOpenAPIOperation] in
            guard let pathItem = pathsObject[path] as? [String: Any] else {
                return []
            }
            return Self.parseOperations(path: path, pathItem: pathItem)
        }

        return ASCOpenAPISpec(
            title: info?["title"] as? String ?? "Unknown OpenAPI Spec",
            version: info?["version"] as? String ?? "unknown",
            openAPIVersion: root["openapi"] as? String ?? "unknown",
            paths: sortedPaths,
            operations: operations
        )
    }

    private static func parseOperations(path: String, pathItem: [String: Any]) -> [ASCOpenAPIOperation] {
        let methods = ["delete", "get", "patch", "post", "put"]
        return methods.compactMap { method in
            guard let operation = pathItem[method] as? [String: Any] else {
                return nil
            }
            return ASCOpenAPIOperation(
                method: method,
                path: path,
                operationID: operation["operationId"] as? String ?? "\(method.uppercased()) \(path)",
                summary: operation["summary"] as? String,
                tags: operation["tags"] as? [String] ?? []
            )
        }
    }
}

enum ASCOpenAPIParseError: Error, LocalizedError, Equatable {
    case invalidRootObject
    case missingPaths

    var errorDescription: String? {
        switch self {
        case .invalidRootObject:
            "OpenAPI document root is not a JSON object."
        case .missingPaths:
            "OpenAPI document does not contain a paths object."
        }
    }
}
