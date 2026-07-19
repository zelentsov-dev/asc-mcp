import CryptoKit
import Foundation

struct ASCOpenAPIReferencePointer: Sendable, Equatable {
    let pointer: String
    let reference: String
}

struct ASCOpenAPIValueConstraint: Sendable, Equatable {
    let types: [String]
    let enumValues: [String]
}

struct ASCOpenAPISchemaSummary: Sendable, Equatable {
    let reference: String?
    let references: [String]
    let referencePointers: [ASCOpenAPIReferencePointer]
    let requiredReferencePointers: [ASCOpenAPIReferencePointer]
    let type: String?
    let format: String?
    let nullable: Bool
    let enumValues: [String]
    let itemType: String?
    let itemEnumValues: [String]
    let minimum: Double?
    let maximum: Double?
    let minLength: Int?
    let maxLength: Int?
    let minItems: Int?
    let maxItems: Int?
    let pattern: String?
    let requiredProperties: [String]
    let requiredPropertyPointers: [String]
    let propertyNames: [String]
    let propertyPointers: [String]
    let valueConstraints: [String: ASCOpenAPIValueConstraint]
    let fingerprint: String
}

struct ASCOpenAPIParameter: Sendable, Equatable {
    enum Location: String, Sendable, Equatable {
        case path
        case query
        case header
        case cookie
        case unknown
    }

    let name: String
    let location: Location
    let description: String?
    let required: Bool
    let deprecated: Bool
    let style: String?
    let explode: Bool?
    let schema: ASCOpenAPISchemaSummary
}

struct ASCOpenAPIMediaType: Sendable, Equatable {
    let contentType: String
    let schema: ASCOpenAPISchemaSummary
}

struct ASCOpenAPIRequestBody: Sendable, Equatable {
    let required: Bool
    let description: String?
    let content: [ASCOpenAPIMediaType]
}

struct ASCOpenAPIResponse: Sendable, Equatable {
    let statusCode: String
    let description: String?
    let content: [ASCOpenAPIMediaType]

    var isSuccess: Bool {
        guard let code = Int(statusCode) else {
            return false
        }
        return (200..<300).contains(code)
    }
}

struct ASCOpenAPIOperation: Sendable, Equatable {
    let method: String
    let path: String
    let operationID: String
    let summary: String?
    let tags: [String]
    let deprecated: Bool
    let parameters: [ASCOpenAPIParameter]
    let requestBody: ASCOpenAPIRequestBody?
    let responses: [ASCOpenAPIResponse]
}

struct ASCOpenAPISpec: Sendable, Equatable {
    let title: String
    let version: String
    let openAPIVersion: String
    let sha256: String
    let paths: [String]
    let operations: [ASCOpenAPIOperation]
    let schemas: [String: ASCOpenAPISchemaSummary]

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
        let components = root["components"] as? [String: Any]
        let rawSchemas = components?["schemas"] as? [String: Any] ?? [:]
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
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            paths: sortedPaths,
            operations: operations,
            schemas: rawSchemas.mapValues { schemaSummary($0) }
        )
    }

    func operation(id: String) -> ASCOpenAPIOperation? {
        operations.first { $0.operationID == id }
    }

    func operation(method: String, path: String) -> ASCOpenAPIOperation? {
        operations.first { $0.method == method.lowercased() && $0.path == path }
    }

    private static func parseOperations(path: String, pathItem: [String: Any]) -> [ASCOpenAPIOperation] {
        let methods = ["delete", "get", "head", "options", "patch", "post", "put", "trace"]
        let pathParameters = parseParameters(pathItem["parameters"])

        return methods.compactMap { method in
            guard let operation = pathItem[method] as? [String: Any] else {
                return nil
            }

            let operationParameters = parseParameters(operation["parameters"])
            let parameters = mergeParameters(path: pathParameters, operation: operationParameters)

            return ASCOpenAPIOperation(
                method: method,
                path: path,
                operationID: operation["operationId"] as? String ?? "\(method.uppercased()) \(path)",
                summary: operation["summary"] as? String,
                tags: operation["tags"] as? [String] ?? [],
                deprecated: operation["deprecated"] as? Bool ?? false,
                parameters: parameters,
                requestBody: parseRequestBody(operation["requestBody"]),
                responses: parseResponses(operation["responses"])
            )
        }
    }

    private static func parseParameters(_ value: Any?) -> [ASCOpenAPIParameter] {
        guard let rawParameters = value as? [[String: Any]] else {
            return []
        }

        return rawParameters.compactMap { raw in
            guard let name = raw["name"] as? String else {
                return nil
            }
            let rawLocation = raw["in"] as? String ?? "unknown"
            let location = ASCOpenAPIParameter.Location(rawValue: rawLocation) ?? .unknown
            return ASCOpenAPIParameter(
                name: name,
                location: location,
                description: raw["description"] as? String,
                required: raw["required"] as? Bool ?? false,
                deprecated: raw["deprecated"] as? Bool ?? false,
                style: raw["style"] as? String,
                explode: raw["explode"] as? Bool,
                schema: schemaSummary(raw["schema"])
            )
        }
        .sorted { lhs, rhs in
            if lhs.location == rhs.location {
                return lhs.name < rhs.name
            }
            return lhs.location.rawValue < rhs.location.rawValue
        }
    }

    private static func mergeParameters(
        path: [ASCOpenAPIParameter],
        operation: [ASCOpenAPIParameter]
    ) -> [ASCOpenAPIParameter] {
        var merged: [String: ASCOpenAPIParameter] = [:]
        for parameter in path + operation {
            merged["\(parameter.location.rawValue):\(parameter.name)"] = parameter
        }
        return merged.values.sorted { lhs, rhs in
            if lhs.location == rhs.location {
                return lhs.name < rhs.name
            }
            return lhs.location.rawValue < rhs.location.rawValue
        }
    }

    private static func parseRequestBody(_ value: Any?) -> ASCOpenAPIRequestBody? {
        guard let raw = value as? [String: Any] else {
            return nil
        }
        return ASCOpenAPIRequestBody(
            required: raw["required"] as? Bool ?? false,
            description: raw["description"] as? String,
            content: parseMediaTypes(raw["content"])
        )
    }

    private static func parseResponses(_ value: Any?) -> [ASCOpenAPIResponse] {
        guard let rawResponses = value as? [String: Any] else {
            return []
        }
        return rawResponses.compactMap { statusCode, rawValue in
            guard let raw = rawValue as? [String: Any] else {
                return nil
            }
            return ASCOpenAPIResponse(
                statusCode: statusCode,
                description: raw["description"] as? String,
                content: parseMediaTypes(raw["content"])
            )
        }
        .sorted { $0.statusCode < $1.statusCode }
    }

    private static func parseMediaTypes(_ value: Any?) -> [ASCOpenAPIMediaType] {
        guard let rawContent = value as? [String: Any] else {
            return []
        }
        return rawContent.compactMap { contentType, rawValue in
            guard let raw = rawValue as? [String: Any] else {
                return nil
            }
            return ASCOpenAPIMediaType(
                contentType: contentType,
                schema: schemaSummary(raw["schema"])
            )
        }
        .sorted { $0.contentType < $1.contentType }
    }

    private static func schemaSummary(_ value: Any?) -> ASCOpenAPISchemaSummary {
        let raw = value as? [String: Any] ?? [:]
        let items = raw["items"] as? [String: Any]
        let properties = raw["properties"] as? [String: Any]
        return ASCOpenAPISchemaSummary(
            reference: raw["$ref"] as? String,
            references: collectReferences(from: raw),
            referencePointers: collectReferencePointers(from: raw),
            requiredReferencePointers: collectRequiredReferencePointers(from: raw),
            type: raw["type"] as? String,
            format: raw["format"] as? String,
            nullable: raw["nullable"] as? Bool ?? false,
            enumValues: scalarStrings(raw["enum"]),
            itemType: items?["type"] as? String,
            itemEnumValues: scalarStrings(items?["enum"]),
            minimum: number(raw["minimum"]),
            maximum: number(raw["maximum"]),
            minLength: integer(raw["minLength"]),
            maxLength: integer(raw["maxLength"]),
            minItems: integer(raw["minItems"]),
            maxItems: integer(raw["maxItems"]),
            pattern: raw["pattern"] as? String,
            requiredProperties: (raw["required"] as? [String] ?? []).sorted(),
            requiredPropertyPointers: collectRequiredPropertyPointers(from: raw),
            propertyNames: (properties?.keys.sorted() ?? []),
            propertyPointers: collectPropertyPointers(from: raw),
            valueConstraints: collectValueConstraints(from: raw),
            fingerprint: fingerprint(raw)
        )
    }

    private static func collectValueConstraints(
        from schema: [String: Any]
    ) -> [String: ASCOpenAPIValueConstraint] {
        var types: [String: Set<String>] = [:]
        var enumValues: [String: Set<String>] = [:]

        func escape(_ component: String) -> String {
            component.replacingOccurrences(of: "~", with: "~0")
                .replacingOccurrences(of: "/", with: "~1")
        }

        func visit(_ node: [String: Any], prefix: String) {
            if let type = node["type"] as? String {
                types[prefix, default: []].insert(type)
            }
            if node["nullable"] as? Bool == true {
                types[prefix, default: []].insert("null")
            }
            let values = scalarStrings(node["enum"])
            if !values.isEmpty {
                enumValues[prefix, default: []].formUnion(values)
                if node["nullable"] as? Bool == true {
                    enumValues[prefix, default: []].insert("null")
                }
            }
            if let properties = node["properties"] as? [String: Any] {
                for name in properties.keys.sorted() {
                    guard let child = properties[name] as? [String: Any] else {
                        continue
                    }
                    visit(child, prefix: "\(prefix)/\(escape(name))")
                }
            }
            if let items = node["items"] as? [String: Any] {
                visit(items, prefix: "\(prefix)/*")
            }
            for compositionKey in ["allOf", "oneOf", "anyOf"] {
                if let variants = node[compositionKey] as? [[String: Any]] {
                    for variant in variants {
                        visit(variant, prefix: prefix)
                    }
                }
            }
        }

        visit(schema, prefix: "")
        return Set(types.keys).union(enumValues.keys).reduce(into: [:]) { result, pointer in
            result[pointer] = ASCOpenAPIValueConstraint(
                types: (types[pointer] ?? []).sorted(),
                enumValues: (enumValues[pointer] ?? []).sorted()
            )
        }
    }

    private static func collectPropertyPointers(from schema: [String: Any]) -> [String] {
        var pointers: Set<String> = []

        func escape(_ component: String) -> String {
            component.replacingOccurrences(of: "~", with: "~0")
                .replacingOccurrences(of: "/", with: "~1")
        }

        func visit(_ node: [String: Any], prefix: String) {
            if let properties = node["properties"] as? [String: Any] {
                for name in properties.keys.sorted() {
                    let pointer = "\(prefix)/\(escape(name))"
                    pointers.insert(pointer)
                    if let child = properties[name] as? [String: Any] {
                        visit(child, prefix: pointer)
                    }
                }
            }
            if let items = node["items"] as? [String: Any] {
                let pointer = "\(prefix)/*"
                pointers.insert(pointer)
                visit(items, prefix: pointer)
            }
            for compositionKey in ["allOf", "oneOf", "anyOf"] {
                if let variants = node[compositionKey] as? [[String: Any]] {
                    for variant in variants {
                        visit(variant, prefix: prefix)
                    }
                }
            }
        }

        visit(schema, prefix: "")
        return pointers.sorted()
    }

    private static func collectRequiredPropertyPointers(from schema: [String: Any]) -> [String] {
        var pointers: Set<String> = []

        func escape(_ component: String) -> String {
            component.replacingOccurrences(of: "~", with: "~0")
                .replacingOccurrences(of: "/", with: "~1")
        }

        func visit(_ node: [String: Any], prefix: String) {
            let requiredNames = (node["required"] as? [String] ?? []).sorted()
            if let properties = node["properties"] as? [String: Any] {
                for name in requiredNames {
                    pointers.insert("\(prefix)/\(escape(name))")
                    guard let child = properties[name] as? [String: Any] else {
                        continue
                    }
                    visit(child, prefix: "\(prefix)/\(escape(name))")
                }
            }
            if let items = node["items"] as? [String: Any] {
                visit(items, prefix: "\(prefix)/*")
            }
            if let variants = node["allOf"] as? [[String: Any]] {
                for variant in variants {
                    visit(variant, prefix: prefix)
                }
            }
        }

        visit(schema, prefix: "")
        return pointers.sorted()
    }

    private static func collectRequiredReferencePointers(
        from schema: [String: Any]
    ) -> [ASCOpenAPIReferencePointer] {
        var references: [ASCOpenAPIReferencePointer] = []

        func escape(_ component: String) -> String {
            component.replacingOccurrences(of: "~", with: "~0")
                .replacingOccurrences(of: "/", with: "~1")
        }

        func visit(_ node: [String: Any], prefix: String) {
            if let reference = node["$ref"] as? String {
                references.append(ASCOpenAPIReferencePointer(pointer: prefix, reference: reference))
            }
            let requiredNames = (node["required"] as? [String] ?? []).sorted()
            if let properties = node["properties"] as? [String: Any] {
                for name in requiredNames {
                    guard let child = properties[name] as? [String: Any] else {
                        continue
                    }
                    visit(child, prefix: "\(prefix)/\(escape(name))")
                }
            }
            if let items = node["items"] as? [String: Any] {
                visit(items, prefix: "\(prefix)/*")
            }
            if let variants = node["allOf"] as? [[String: Any]] {
                for variant in variants {
                    visit(variant, prefix: prefix)
                }
            }
        }

        visit(schema, prefix: "")
        return references.sorted { lhs, rhs in
            if lhs.pointer == rhs.pointer {
                return lhs.reference < rhs.reference
            }
            return lhs.pointer < rhs.pointer
        }
    }

    private static func collectReferences(from value: Any) -> [String] {
        var references: Set<String> = []

        func visit(_ node: Any) {
            if let object = node as? [String: Any] {
                if let reference = object["$ref"] as? String {
                    references.insert(reference)
                }
                for child in object.values {
                    visit(child)
                }
            } else if let array = node as? [Any] {
                for child in array {
                    visit(child)
                }
            }
        }

        visit(value)
        return references.sorted()
    }

    private static func collectReferencePointers(from schema: [String: Any]) -> [ASCOpenAPIReferencePointer] {
        var references: [ASCOpenAPIReferencePointer] = []

        func escape(_ component: String) -> String {
            component.replacingOccurrences(of: "~", with: "~0")
                .replacingOccurrences(of: "/", with: "~1")
        }

        func visit(_ node: [String: Any], prefix: String) {
            if let reference = node["$ref"] as? String {
                references.append(ASCOpenAPIReferencePointer(pointer: prefix, reference: reference))
            }
            if let properties = node["properties"] as? [String: Any] {
                for name in properties.keys.sorted() {
                    guard let child = properties[name] as? [String: Any] else {
                        continue
                    }
                    visit(child, prefix: "\(prefix)/\(escape(name))")
                }
            }
            if let items = node["items"] as? [String: Any] {
                visit(items, prefix: "\(prefix)/*")
            }
            for compositionKey in ["allOf", "oneOf", "anyOf"] {
                if let variants = node[compositionKey] as? [[String: Any]] {
                    for variant in variants {
                        visit(variant, prefix: prefix)
                    }
                }
            }
        }

        visit(schema, prefix: "")
        return references.sorted { lhs, rhs in
            if lhs.pointer == rhs.pointer {
                return lhs.reference < rhs.reference
            }
            return lhs.pointer < rhs.pointer
        }
    }

    private static func scalarStrings(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else {
            return []
        }
        return values.compactMap { value in
            if let string = value as? String {
                return string
            }
            if let boolean = value as? Bool {
                return boolean ? "true" : "false"
            }
            if let number = value as? NSNumber {
                return number.stringValue
            }
            return nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func fingerprint(_ object: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return ""
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
