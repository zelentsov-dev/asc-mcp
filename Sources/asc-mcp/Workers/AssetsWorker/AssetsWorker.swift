import Foundation
import MCP

actor AssetReferenceCache {
    private var entry: (Date, AssetLibraryResource)?
    func get() -> AssetLibraryResource? {
        guard let entry, Date().timeIntervalSince(entry.0) < 300 else { return nil }
        return entry.1
    }
    func set(_ resource: AssetLibraryResource) { entry = (Date(), resource) }
}

/// Provides app-scoped asset reads and preview-bound mutations.
public final class AssetsWorker: Sendable {
    let httpClient: HTTPClient
    let uploadService: UploadService
    let companiesManager: CompaniesManager
    let store: AssetOperationStore
    let sessionID = UUID()
    let referenceCache = AssetReferenceCache()
    let validateUploadDestinations: @Sendable ([ASCUploadOperation]) async throws -> [String: [String]]

    /// Creates an account-scoped worker with bounded API and upload responses.
    /// - Returns: A worker sharing the supplied account services and a private operation journal.
    /// - Throws: Does not throw; configuration and resource checks occur when a tool runs.
    public convenience init(httpClient: HTTPClient, companiesManager: CompaniesManager, uploadService: UploadService) {
        self.init(httpClient: httpClient, companiesManager: companiesManager, uploadService: uploadService, store: AssetOperationStore())
    }

    init(httpClient: HTTPClient, companiesManager: CompaniesManager, uploadService: UploadService, store: AssetOperationStore,
         validateUploadDestinations: @escaping @Sendable ([ASCUploadOperation]) async throws -> [String: [String]] = AssetUploadDestinationPolicy.resolvedDestinations) {
        self.httpClient = httpClient.withResponseLimit(32 * 1_024 * 1_024)
        self.companiesManager = companiesManager
        self.uploadService = uploadService.withResponseLimit(maxBytes: 64 * 1_024)
        self.store = store
        self.validateUploadDestinations = validateUploadDestinations
    }

    /// Returns asset discovery, preparation, execution, and reconciliation tools.
    /// - Returns: Eleven tools with explicit side-effect annotations.
    /// - Throws: Does not throw.
    public func getTools() async -> [Tool] { toolDefinitions() }

    /// Routes an asset tool after rejecting unknown input fields.
    /// - Returns: A sanitized structured result or an actionable error.
    /// - Throws: `MCPError.methodNotFound` for an unknown tool name.
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let tool = toolDefinitions().first(where: { $0.name == params.name }) else { throw MCPError.methodNotFound(params.name) }
        do {
            let arguments = params.arguments ?? [:]
            let allowed = Set(tool.inputSchema.objectValue?["properties"]?.objectValue?.keys.map { $0 } ?? [])
            guard Set(arguments.keys).isSubset(of: allowed) else { throw AssetLibraryError("Unsupported input parameter") }
            switch params.name {
            case "assets_prepare_change": return try await prepareChange(arguments)
            case "assets_apply_change": return try await applyChange(previewID: required("preview_id", arguments))
            case "assets_get_operation": return try await getOperation(arguments)
            default: return try await readTool(params.name, arguments)
            }
        } catch { return MCPResult.error(error, prefix: "Asset Library") }
    }

    func accountScope() async throws -> String {
        let company = try await companiesManager.getCurrentCompany()
        return try AssetLibraryJSON.fingerprint([company.id, company.keyID, company.issuerID])
    }

    func required(_ name: String, _ arguments: [String: Value]) throws -> String {
        guard let value = arguments[name]?.stringValue, !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines), value.count <= 1_024 else {
            throw AssetLibraryError("'\(name)' must be a nonempty string without surrounding whitespace")
        }
        return value
    }

    func identifier(_ name: String, _ arguments: [String: Value]) throws -> String {
        try AssetLibraryJSON.identifier(required(name, arguments), field: name)
    }

    func resource(_ type: String, _ id: String, include: String? = nil, version: String = "v1") async throws -> AssetLibraryResource {
        let path = "/\(version)/\(type)/\(try AssetLibraryJSON.identifier(id, field: "resource_id"))"
        let document = try await httpClient.get(path, parameters: include.map { ["include": $0] } ?? [:], as: AssetLibraryDocument.self)
        guard document.data.type == type, document.data.id == id else { throw AssetLibraryError("Apple returned a resource outside the requested scope") }
        return document.data
    }

    func library(appID: String) async throws -> AssetLibraryResource {
        let document = try await httpClient.get("/v1/apps/\(try ASCPathSegment.encode(try AssetLibraryJSON.identifier(appID, field: "app_id")))/assetLibrary", as: AssetLibraryDocument.self)
        guard document.data.type == "appAssetLibraries" else { throw AssetLibraryError("Apple returned an invalid asset library") }
        return try await resource("appAssetLibraries", document.data.id)
    }

    func all(_ path: String, query: [String: String] = [:], type: String) async throws -> [AssetLibraryResource] {
        var query = query
        query["limit"] = "200"
        var page = try await httpClient.get(path, parameters: query, as: AssetLibraryCollection.self)
        var result: [AssetLibraryResource] = []
        var inventoryBytes = 0
        var ids: Set<String> = []
        var links: Set<String> = []
        let declaredTotal = AssetMediaInspector.number(page.meta?.objectValue?["paging"]?.objectValue?["total"])
        for _ in 0..<100 {
            for item in page.data {
                guard item.type == type, ids.insert(item.id).inserted else { throw AssetLibraryError("Collection contains a duplicate or unexpected resource") }
                _ = try AssetLibraryJSON.identifier(item.id, field: "response_id")
                let itemBytes = try AssetLibraryJSON.encode(item).count
                guard itemBytes <= 32 * 1_024 * 1_024 - inventoryBytes else {
                    throw AssetLibraryError("Collection exceeds the safe inventory byte limit")
                }
                inventoryBytes += itemBytes
                result.append(item)
            }
            guard result.count <= 20_000 else { throw AssetLibraryError("Collection exceeds the safe inventory limit") }
            guard let next = page.next else {
                if let declaredTotal, declaredTotal != Double(result.count) { throw AssetLibraryError("Collection ended before its declared total; refusing incomplete inventory") }
                return result
            }
            guard !page.data.isEmpty, links.insert(next).inserted else { throw AssetLibraryError("Invalid or repeating pagination link") }
            page = try await httpClient.getPage(next, scope: PaginationScope.strict(path: path, query: query), as: AssetLibraryCollection.self)
        }
        throw AssetLibraryError("Collection pagination exceeded its safe bound")
    }

    func ownedAsset(appID: String, kind: AssetLibraryKind, id: String) async throws -> AssetLibraryResource {
        let library = try await library(appID: appID)
        let members = try await all("/v1/appAssetLibraries/\(try ASCPathSegment.encode(library.id))/\(try ASCPathSegment.encode(kind.collection))", query: ["filter[id]": try AssetLibraryJSON.identifier(id, field: "asset_id")], type: kind.resourceType)
        guard members.count == 1, members[0].id == id else { throw AssetLibraryError("Asset does not belong to this application's library") }
        return try await resource(kind.resourceType, id)
    }

    func placements(kind: AssetLibraryKind, id: String) async throws -> [AssetLibraryResource] {
        try await all("/v1/\(try ASCPathSegment.encode(kind.resourceType))/\(try ASCPathSegment.encode(try AssetLibraryJSON.identifier(id, field: "asset_id")))/placements", query: ["include": Self.placementIncludes], type: "appAssetLibraryPlacements")
    }

    static let placementIncludes = "image,video,appEventLocalization,appStoreVersionLocalization,appCustomProductPageLocalization,appStoreVersionExperimentTreatmentLocalization"
}
