import Foundation

enum ASCToolKind: String, Codable, Sendable {
    case direct
    case compound
    case local
    case alias
}

enum ASCMappingStatus: String, Codable, Sendable {
    case full
    case partial
    case deprecated
    case unresolved
}

enum ASCOperationRole: String, Codable, Sendable {
    case primary
    case supporting
    case conditional
}

enum ASCFieldSourceKind: String, Codable, Sendable {
    case parameter
    case requestBody
    case local
    case fixed
    case derived
}

enum ASCResponseMode: String, Codable, Sendable {
    case direct
    case projection
    case aggregate
    case local
    case opaque
}

enum ASCOperationDisposition: String, Codable, Sendable {
    case deferred
    case outOfScope
    case unsupported
}

enum ASCToolEffect: String, Codable, Sendable {
    case read
    case write
    case destructive
    case local
}

enum ASCImplementationState: String, Codable, Sendable {
    case asBuilt
    case target
    case broken
}

enum ASCOptionalParameterDisposition: String, Codable, Sendable {
    case internalControl
    case intentionallyOmitted
}

enum ASCOptionalParameterFamily: String, Codable, Sendable {
    case sparseFields
}

indirect enum ASCJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case integer(Int64)
    case number(Double)
    case boolean(Bool)
    case object([String: ASCJSONValue])
    case array([ASCJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([ASCJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: ASCJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value in operation manifest."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var canonicalDescription: String {
        switch self {
        case .string(let value):
            return value
        case .integer(let value):
            return String(value)
        case .number(let value):
            return String(value)
        case .boolean(let value):
            return String(value)
        case .object(let value):
            return "{" + value.keys.sorted().map {
                "\($0):\(value[$0]?.canonicalDescription ?? "null")"
            }.joined(separator: ",") + "}"
        case .array(let value):
            return "[" + value.map(\.canonicalDescription).joined(separator: ",") + "]"
        case .null:
            return "null"
        }
    }

    var canonicalIdentity: String {
        switch self {
        case .string(let value):
            return "string:\(value)"
        case .integer(let value):
            return "integer:\(value)"
        case .number(let value):
            return "number:\(value)"
        case .boolean(let value):
            return "boolean:\(value)"
        case .object(let value):
            return "object:{" + value.keys.sorted().map {
                "\($0):\(value[$0]?.canonicalIdentity ?? "null")"
            }.joined(separator: ",") + "}"
        case .array(let value):
            return "array:[" + value.map(\.canonicalIdentity).joined(separator: ",") + "]"
        case .null:
            return "null"
        }
    }

    func matches(openAPIType type: String) -> Bool {
        switch (self, type) {
        case (.string, "string"),
             (.integer, "integer"),
             (.integer, "number"),
             (.number, "number"),
             (.boolean, "boolean"),
             (.object, "object"),
             (.array, "array"),
             (.null, "null"):
            return true
        default:
            return false
        }
    }
}

struct ASCSpecPin: Codable, Sendable, Equatable {
    let version: String
    let sha256: String
    let pathCount: Int
    let operationCount: Int
}

struct ASCOperationScopeRule: Codable, Sendable, Equatable {
    let pathPrefix: String
    let disposition: ASCOperationDisposition
    let reason: String
    let owner: String
    let reviewAtSpec: String
}

struct ASCOperationWaiver: Codable, Sendable, Equatable {
    let id: String
    let operationID: String?
    let method: String?
    let path: String?
    let disposition: ASCOperationDisposition
    let reason: String
    let owner: String
    let reviewAtSpec: String

    enum CodingKeys: String, CodingKey {
        case id
        case operationID = "operationId"
        case method
        case path
        case disposition
        case reason
        case owner
        case reviewAtSpec
    }
}

struct ASCOptionalParameterFamilyRule: Codable, Sendable, Equatable {
    let family: ASCOptionalParameterFamily
    let disposition: ASCOptionalParameterDisposition
    let reason: String
    let owner: String
    let reviewAtSpec: String
}

struct ASCOperationManifestIndex: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let specPin: ASCSpecPin
    let optionalInputCoveragePin: ASCOptionalInputCoverage?
    let optionalParameterFamilyRules: [ASCOptionalParameterFamilyRule]?
    let scopeRules: [ASCOperationScopeRule]
    let waivers: [ASCOperationWaiver]

    init(
        schemaVersion: Int,
        specPin: ASCSpecPin,
        optionalInputCoveragePin: ASCOptionalInputCoverage? = nil,
        optionalParameterFamilyRules: [ASCOptionalParameterFamilyRule]? = nil,
        scopeRules: [ASCOperationScopeRule],
        waivers: [ASCOperationWaiver]
    ) {
        self.schemaVersion = schemaVersion
        self.specPin = specPin
        self.optionalInputCoveragePin = optionalInputCoveragePin
        self.optionalParameterFamilyRules = optionalParameterFamilyRules
        self.scopeRules = scopeRules
        self.waivers = waivers
    }
}

struct ASCOptionalParameterClassification: Codable, Sendable, Equatable {
    let location: String
    let appleName: String
    let disposition: ASCOptionalParameterDisposition
    let reason: String
    let reviewAtSpec: String
}

struct ASCOperationUse: Codable, Sendable, Equatable {
    let invocationID: String?
    let operationID: String
    let method: String
    let path: String
    let role: ASCOperationRole
    let condition: String?
    let inputs: [ASCOperationInputBinding]?
    let optionalParameterClassifications: [ASCOptionalParameterClassification]?

    init(
        invocationID: String?,
        operationID: String,
        method: String,
        path: String,
        role: ASCOperationRole,
        condition: String?,
        inputs: [ASCOperationInputBinding]?,
        optionalParameterClassifications: [ASCOptionalParameterClassification]? = nil
    ) {
        self.invocationID = invocationID
        self.operationID = operationID
        self.method = method
        self.path = path
        self.role = role
        self.condition = condition
        self.inputs = inputs
        self.optionalParameterClassifications = optionalParameterClassifications
    }

    enum CodingKeys: String, CodingKey {
        case invocationID = "invocationId"
        case operationID = "operationId"
        case method
        case path
        case role
        case condition
        case inputs
        case optionalParameterClassifications
    }
}

struct ASCOperationInputBinding: Codable, Sendable, Equatable {
    let sourceKind: ASCFieldSourceKind
    let location: String?
    let appleName: String?
    let jsonPointer: String?
    let fixedValue: ASCJSONValue?
    let derivedFrom: [String]?
    let localRole: String?

    init(
        sourceKind: ASCFieldSourceKind,
        location: String?,
        appleName: String?,
        jsonPointer: String?,
        fixedValue: ASCJSONValue?,
        derivedFrom: [String]?,
        localRole: String?
    ) {
        self.sourceKind = sourceKind
        self.location = location
        self.appleName = appleName
        self.jsonPointer = jsonPointer
        self.fixedValue = fixedValue
        self.derivedFrom = derivedFrom
        self.localRole = localRole
    }

    enum CodingKeys: String, CodingKey {
        case sourceKind
        case location
        case appleName
        case jsonPointer
        case fixedValue
        case derivedFrom
        case localRole
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceKind = try container.decode(ASCFieldSourceKind.self, forKey: .sourceKind)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        appleName = try container.decodeIfPresent(String.self, forKey: .appleName)
        jsonPointer = try container.decodeIfPresent(String.self, forKey: .jsonPointer)
        fixedValue = try container.decodeManifestJSONValue(forKey: .fixedValue)
        derivedFrom = try container.decodeIfPresent([String].self, forKey: .derivedFrom)
        localRole = try container.decodeIfPresent(String.self, forKey: .localRole)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceKind, forKey: .sourceKind)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(appleName, forKey: .appleName)
        try container.encodeIfPresent(jsonPointer, forKey: .jsonPointer)
        try container.encodeManifestJSONValue(fixedValue, forKey: .fixedValue)
        try container.encodeIfPresent(derivedFrom, forKey: .derivedFrom)
        try container.encodeIfPresent(localRole, forKey: .localRole)
    }
}

struct ASCToolFieldBinding: Codable, Sendable, Equatable {
    let toolField: String
    let sourceKind: ASCFieldSourceKind
    let operationID: String?
    let invocationID: String?
    let location: String?
    let appleName: String?
    let jsonPointer: String?
    let localRole: String?
    let fixedValue: ASCJSONValue?
    let derivedFrom: [String]?
    let omissionReason: String?

    init(
        toolField: String,
        sourceKind: ASCFieldSourceKind,
        operationID: String?,
        invocationID: String?,
        location: String?,
        appleName: String?,
        jsonPointer: String?,
        localRole: String?,
        fixedValue: ASCJSONValue?,
        derivedFrom: [String]?,
        omissionReason: String?
    ) {
        self.toolField = toolField
        self.sourceKind = sourceKind
        self.operationID = operationID
        self.invocationID = invocationID
        self.location = location
        self.appleName = appleName
        self.jsonPointer = jsonPointer
        self.localRole = localRole
        self.fixedValue = fixedValue
        self.derivedFrom = derivedFrom
        self.omissionReason = omissionReason
    }

    enum CodingKeys: String, CodingKey {
        case toolField
        case sourceKind
        case operationID = "operationId"
        case invocationID = "invocationId"
        case location
        case appleName
        case jsonPointer
        case localRole
        case fixedValue
        case derivedFrom
        case omissionReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolField = try container.decode(String.self, forKey: .toolField)
        sourceKind = try container.decode(ASCFieldSourceKind.self, forKey: .sourceKind)
        operationID = try container.decodeIfPresent(String.self, forKey: .operationID)
        invocationID = try container.decodeIfPresent(String.self, forKey: .invocationID)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        appleName = try container.decodeIfPresent(String.self, forKey: .appleName)
        jsonPointer = try container.decodeIfPresent(String.self, forKey: .jsonPointer)
        localRole = try container.decodeIfPresent(String.self, forKey: .localRole)
        fixedValue = try container.decodeManifestJSONValue(forKey: .fixedValue)
        derivedFrom = try container.decodeIfPresent([String].self, forKey: .derivedFrom)
        omissionReason = try container.decodeIfPresent(String.self, forKey: .omissionReason)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(toolField, forKey: .toolField)
        try container.encode(sourceKind, forKey: .sourceKind)
        try container.encodeIfPresent(operationID, forKey: .operationID)
        try container.encodeIfPresent(invocationID, forKey: .invocationID)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(appleName, forKey: .appleName)
        try container.encodeIfPresent(jsonPointer, forKey: .jsonPointer)
        try container.encodeIfPresent(localRole, forKey: .localRole)
        try container.encodeManifestJSONValue(fixedValue, forKey: .fixedValue)
        try container.encodeIfPresent(derivedFrom, forKey: .derivedFrom)
        try container.encodeIfPresent(omissionReason, forKey: .omissionReason)
    }
}

struct ASCResponseSource: Codable, Sendable, Equatable {
    let operationID: String
    let invocationIDs: [String]?
    let statusCode: String
    let mediaType: String?

    enum CodingKeys: String, CodingKey {
        case operationID = "operationId"
        case invocationIDs = "invocationIds"
        case statusCode
        case mediaType
    }
}

struct ASCResponseFieldBinding: Codable, Sendable, Equatable {
    let outputField: String
    let operationID: String?
    let invocationIDs: [String]?
    let jsonPointer: String?
    let localRole: String?

    enum CodingKeys: String, CodingKey {
        case outputField
        case operationID = "operationId"
        case invocationIDs = "invocationIds"
        case jsonPointer
        case localRole
    }
}

struct ASCResponseMapping: Codable, Sendable, Equatable {
    let mode: ASCResponseMode
    let sources: [ASCResponseSource]
    let fields: [ASCResponseFieldBinding]
    let waiverID: String?

    enum CodingKeys: String, CodingKey {
        case mode
        case sources
        case fields
        case waiverID = "waiverId"
    }
}

struct ASCImplementationAlias: Codable, Sendable, Equatable {
    let publicTool: String
    let internalTool: String
    let replacementTool: String?
}

struct ASCToolOperationMapping: Codable, Sendable, Equatable {
    let tool: String
    let kind: ASCToolKind
    let status: ASCMappingStatus
    let effect: ASCToolEffect
    let implementationState: ASCImplementationState
    let replacementTool: String?
    let operations: [ASCOperationUse]
    let fields: [ASCToolFieldBinding]
    let response: ASCResponseMapping
    let note: String?
}

struct ASCWorkerToolManifest: Codable, Sendable, Equatable {
    let workerKey: String
    let tools: [ASCToolOperationMapping]
    let implementationAliases: [ASCImplementationAlias]
}

struct ASCOperationManifestBundle: Sendable, Equatable {
    let index: ASCOperationManifestIndex
    let workers: [ASCWorkerToolManifest]

    var tools: [ASCToolOperationMapping] {
        workers.flatMap(\.tools).sorted { $0.tool < $1.tool }
    }

    func mapping(for toolName: String) -> ASCToolOperationMapping? {
        tools.first { $0.tool == toolName }
    }

    /// Load an operation manifest bundle from its root directory.
    /// - Parameter directoryURL: Directory containing `manifest.json` and a `tools` subdirectory.
    /// - Returns: Decoded manifest index and deterministically sorted worker fragments.
    /// - Throws: File-system, JSON decoding, or duplicate-entry errors.
    static func load(from directoryURL: URL) throws -> ASCOperationManifestBundle {
        let decoder = JSONDecoder()
        let indexURL = directoryURL.appendingPathComponent("manifest.json")
        let indexData = try Data(contentsOf: indexURL)
        try ASCOperationManifestJSONValidator.validateIndex(
            indexData,
            source: "manifest.json"
        )
        let index = try decoder.decode(
            ASCOperationManifestIndex.self,
            from: indexData
        )

        let toolsDirectoryURL = directoryURL.appendingPathComponent("tools", isDirectory: true)
        let fragmentURLs = try FileManager.default.contentsOfDirectory(
            at: toolsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let workers = try fragmentURLs.map { url in
            let workerData = try Data(contentsOf: url)
            try ASCOperationManifestJSONValidator.validateWorker(
                workerData,
                source: "tools/\(url.lastPathComponent)"
            )
            let worker = try decoder.decode(
                ASCWorkerToolManifest.self,
                from: workerData
            )
            let fileKey = url.deletingPathExtension().lastPathComponent
            guard fileKey == worker.workerKey else {
                throw ASCOperationManifestError.workerKeyFilenameMismatch(
                    fileKey: fileKey,
                    workerKey: worker.workerKey
                )
            }
            return worker
        }

        let duplicateWorkerKeys = duplicateValues(workers.map(\.workerKey))
        guard duplicateWorkerKeys.isEmpty else {
            throw ASCOperationManifestError.duplicateWorkerKeys(duplicateWorkerKeys)
        }

        let duplicateTools = duplicateValues(workers.flatMap(\.tools).map(\.tool))
        guard duplicateTools.isEmpty else {
            throw ASCOperationManifestError.duplicateTools(duplicateTools)
        }

        return ASCOperationManifestBundle(index: index, workers: workers)
    }

    /// Load the operation manifest bundled with the executable.
    /// - Returns: Decoded production operation manifest.
    /// - Throws: `ASCOperationManifestError.resourceMissing` when the resource bundle is incomplete.
    static func loadBundled() throws -> ASCOperationManifestBundle {
        if let overridePath = ProcessInfo.processInfo.environment["ASC_MCP_OPERATION_MANIFEST"] {
            return try load(from: URL(fileURLWithPath: overridePath, isDirectory: true))
        }

        guard let directoryURL = bundledManifestDirectory() else {
            throw ASCOperationManifestError.resourceMissing("OperationManifest")
        }
        return try load(from: directoryURL)
    }

    private static func bundledManifestDirectory() -> URL? {
        let fileManager = FileManager.default
        let loadedBundles = Bundle.allBundles + [Bundle.main]
        var roots = loadedBundles.flatMap { bundle in
            [bundle.bundleURL, bundle.resourceURL].compactMap { $0 }
        }

        var executableURLs = loadedBundles.compactMap(\.executableURL)
        for argument in CommandLine.arguments
        where argument.hasPrefix("/") && fileManager.isExecutableFile(atPath: argument) {
            executableURLs.append(URL(fileURLWithPath: argument))
        }

        let ancestrySeeds = roots + executableURLs.map { $0.deletingLastPathComponent() }
        for seed in ancestrySeeds {
            var current = seed
                .standardizedFileURL
                .resolvingSymlinksInPath()
            for _ in 0..<8 {
                roots.append(current)
                let parent = current.deletingLastPathComponent()
                if parent == current {
                    break
                }
                current = parent
            }
        }

        var seen: Set<String> = []
        for root in roots {
            let resourceBundle = root.appendingPathComponent(
                "asc-mcp_asc-mcp.bundle",
                isDirectory: true
            )
            let candidates = [
                root.appendingPathComponent("OperationManifest", isDirectory: true),
                resourceBundle.appendingPathComponent("OperationManifest", isDirectory: true),
                resourceBundle.appendingPathComponent("Contents/Resources/OperationManifest", isDirectory: true)
            ]
            for candidate in candidates {
                let path = candidate.standardizedFileURL.path
                guard seen.insert(path).inserted else {
                    continue
                }
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func duplicateValues(_ values: [String]) -> [String] {
        Dictionary(grouping: values, by: { $0 })
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
    }
}

enum ASCOperationManifestError: Error, LocalizedError, Equatable {
    case resourceMissing(String)
    case unknownKey(source: String, path: String, key: String)
    case workerKeyFilenameMismatch(fileKey: String, workerKey: String)
    case duplicateWorkerKeys([String])
    case duplicateTools([String])

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let resource):
            "Operation manifest resource is missing: \(resource)"
        case .unknownKey(let source, let path, let key):
            "Unknown operation manifest key '\(key)' at \(source):\(path)."
        case .workerKeyFilenameMismatch(let fileKey, let workerKey):
            "Worker manifest filename '\(fileKey).json' does not match workerKey '\(workerKey)'."
        case .duplicateWorkerKeys(let keys):
            "Duplicate worker manifest keys: \(keys.joined(separator: ", "))"
        case .duplicateTools(let tools):
            "Duplicate tool manifest entries: \(tools.joined(separator: ", "))"
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeManifestJSONValue(forKey key: Key) throws -> ASCJSONValue? {
        guard contains(key) else {
            return nil
        }
        if try decodeNil(forKey: key) {
            return .null
        }
        return try decode(ASCJSONValue.self, forKey: key)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeManifestJSONValue(
        _ value: ASCJSONValue?,
        forKey key: Key
    ) throws {
        guard let value else {
            return
        }
        try encode(value, forKey: key)
    }
}
