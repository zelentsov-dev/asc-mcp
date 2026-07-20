import Foundation

enum ASCOperationManifestJSONValidator {
    private static let indexKeys: Set<String> = [
        "schemaVersion", "specPin", "optionalParameterFamilyRules", "scopeRules", "waivers"
    ]
    private static let specPinKeys: Set<String> = [
        "version", "sha256", "pathCount", "operationCount"
    ]
    private static let scopeRuleKeys: Set<String> = [
        "pathPrefix", "disposition", "reason", "owner", "reviewAtSpec"
    ]
    private static let waiverKeys: Set<String> = [
        "id", "operationId", "method", "path", "disposition", "reason", "owner",
        "reviewAtSpec"
    ]
    private static let optionalParameterFamilyRuleKeys: Set<String> = [
        "family", "disposition", "reason", "owner", "reviewAtSpec"
    ]
    private static let workerKeys: Set<String> = [
        "workerKey", "tools", "implementationAliases"
    ]
    private static let toolKeys: Set<String> = [
        "tool", "kind", "status", "effect", "implementationState", "replacementTool",
        "operations", "fields", "response", "note"
    ]
    private static let operationKeys: Set<String> = [
        "invocationId", "operationId", "method", "path", "role", "condition", "inputs",
        "optionalParameterClassifications"
    ]
    private static let operationInputKeys: Set<String> = [
        "sourceKind", "location", "appleName", "jsonPointer", "fixedValue", "derivedFrom",
        "localRole"
    ]
    private static let optionalParameterClassificationKeys: Set<String> = [
        "location", "appleName", "disposition", "reason", "reviewAtSpec"
    ]
    private static let toolFieldKeys: Set<String> = [
        "toolField", "sourceKind", "operationId", "invocationId", "location", "appleName",
        "jsonPointer", "localRole", "fixedValue", "derivedFrom", "omissionReason"
    ]
    private static let responseKeys: Set<String> = [
        "mode", "sources", "fields", "waiverId"
    ]
    private static let responseSourceKeys: Set<String> = [
        "operationId", "invocationIds", "statusCode", "mediaType"
    ]
    private static let responseFieldKeys: Set<String> = [
        "outputField", "operationId", "invocationIds", "jsonPointer", "localRole"
    ]
    private static let aliasKeys: Set<String> = [
        "publicTool", "internalTool", "replacementTool"
    ]

    static func validateIndex(_ data: Data, source: String) throws {
        let value = try JSONSerialization.jsonObject(with: data)
        guard let object = value as? [String: Any] else {
            return
        }

        try validateKeys(of: object, allowed: indexKeys, source: source, path: "$")
        try validateObject(
            object["specPin"],
            allowed: specPinKeys,
            source: source,
            path: "$.specPin"
        )
        try validateArray(
            object["optionalParameterFamilyRules"],
            allowed: optionalParameterFamilyRuleKeys,
            source: source,
            path: "$.optionalParameterFamilyRules"
        )
        try validateArray(
            object["scopeRules"],
            allowed: scopeRuleKeys,
            source: source,
            path: "$.scopeRules"
        )
        try validateArray(
            object["waivers"],
            allowed: waiverKeys,
            source: source,
            path: "$.waivers"
        )
    }

    static func validateWorker(_ data: Data, source: String) throws {
        let value = try JSONSerialization.jsonObject(with: data)
        guard let object = value as? [String: Any] else {
            return
        }

        try validateKeys(of: object, allowed: workerKeys, source: source, path: "$")
        if let tools = object["tools"] as? [Any] {
            for (toolIndex, value) in tools.enumerated() {
                guard let tool = value as? [String: Any] else {
                    continue
                }
                let toolPath = "$.tools[\(toolIndex)]"
                try validateKeys(of: tool, allowed: toolKeys, source: source, path: toolPath)
                try validateOperations(
                    tool["operations"],
                    source: source,
                    path: "\(toolPath).operations"
                )
                try validateArray(
                    tool["fields"],
                    allowed: toolFieldKeys,
                    source: source,
                    path: "\(toolPath).fields"
                )
                try validateResponse(
                    tool["response"],
                    source: source,
                    path: "\(toolPath).response"
                )
            }
        }
        try validateArray(
            object["implementationAliases"],
            allowed: aliasKeys,
            source: source,
            path: "$.implementationAliases"
        )
    }

    private static func validateOperations(
        _ value: Any?,
        source: String,
        path: String
    ) throws {
        guard let operations = value as? [Any] else {
            return
        }
        for (operationIndex, value) in operations.enumerated() {
            guard let operation = value as? [String: Any] else {
                continue
            }
            let operationPath = "\(path)[\(operationIndex)]"
            try validateKeys(
                of: operation,
                allowed: operationKeys,
                source: source,
                path: operationPath
            )
            try validateArray(
                operation["inputs"],
                allowed: operationInputKeys,
                source: source,
                path: "\(operationPath).inputs"
            )
            try validateArray(
                operation["optionalParameterClassifications"],
                allowed: optionalParameterClassificationKeys,
                source: source,
                path: "\(operationPath).optionalParameterClassifications"
            )
        }
    }

    private static func validateResponse(
        _ value: Any?,
        source: String,
        path: String
    ) throws {
        guard let response = value as? [String: Any] else {
            return
        }
        try validateKeys(of: response, allowed: responseKeys, source: source, path: path)
        try validateArray(
            response["sources"],
            allowed: responseSourceKeys,
            source: source,
            path: "\(path).sources"
        )
        try validateArray(
            response["fields"],
            allowed: responseFieldKeys,
            source: source,
            path: "\(path).fields"
        )
    }

    private static func validateObject(
        _ value: Any?,
        allowed: Set<String>,
        source: String,
        path: String
    ) throws {
        guard let object = value as? [String: Any] else {
            return
        }
        try validateKeys(of: object, allowed: allowed, source: source, path: path)
    }

    private static func validateArray(
        _ value: Any?,
        allowed: Set<String>,
        source: String,
        path: String
    ) throws {
        guard let values = value as? [Any] else {
            return
        }
        for (index, value) in values.enumerated() {
            guard let object = value as? [String: Any] else {
                continue
            }
            try validateKeys(
                of: object,
                allowed: allowed,
                source: source,
                path: "\(path)[\(index)]"
            )
        }
    }

    private static func validateKeys(
        of object: [String: Any],
        allowed: Set<String>,
        source: String,
        path: String
    ) throws {
        guard let unknownKey = object.keys.filter({ !allowed.contains($0) }).sorted().first else {
            return
        }
        throw ASCOperationManifestError.unknownKey(
            source: source,
            path: path,
            key: unknownKey
        )
    }
}
