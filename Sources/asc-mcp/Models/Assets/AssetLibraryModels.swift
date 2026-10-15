import Foundation
import CryptoKit
import MCP

struct AssetLibraryError: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct AssetLibraryResource: Codable, Sendable {
    let type: String
    let id: String
    var attributes: [String: JSONValue]?
    var relationships: [String: JSONValue]?
    var links: JSONValue?

    var state: String? { attributes?["state"]?.stringValue }
    var posterFrameState: String? {
        attributes?["previewFrameImage"]?.objectValue?["state"]?.objectValue?["state"]?.stringValue
    }

    func related(_ name: String) -> AssetLibraryResourceID? {
        guard let data = relationships?[name]?.objectValue?["data"]?.objectValue,
              let type = data["type"]?.stringValue, let id = data["id"]?.stringValue else { return nil }
        return AssetLibraryResourceID(type: type, id: id)
    }

    func projection() -> [String: Any] {
        var attributes = attributes ?? [:]
        attributes["uploadOperations"] = nil
        var result: [String: Any] = ["type": type, "id": id, "attributes": attributes.mapValues(\.asAny)]
        if let relationships { result["relationships"] = relationships.mapValues(\.asAny) }
        return result
    }

    func fingerprint() throws -> String {
        var resource = self
        resource.links = nil
        resource.attributes?["uploadOperations"] = nil
        resource.attributes?["imageAsset"] = nil
        resource.attributes?["videoAsset"] = nil
        resource.attributes?["previewFrameImage"] = nil
        resource.relationships = relationships?.mapValues { value in
            guard var object = value.objectValue else { return value }
            object["links"] = nil
            object["meta"] = nil
            return .object(object)
        }
        return try AssetLibraryJSON.fingerprint(resource)
    }
}

struct AssetLibraryResourceID: Codable, Sendable, Equatable {
    let type: String
    let id: String
    var relationship: JSONValue { .object(["data": .object(["type": .string(type), "id": .string(id)])]) }
}

struct AssetLibraryDocument: Codable, Sendable {
    let data: AssetLibraryResource
}

struct AssetLibraryCollection: Codable, Sendable {
    let data: [AssetLibraryResource]
    let links: [String: JSONValue]?
    let meta: JSONValue?
    var next: String? { links?["next"]?.stringValue }
}

enum AssetLibraryKind: String, Codable, Sendable {
    case image, video
    var resourceType: String { self == .image ? "appAssetLibraryImages" : "appAssetLibraryVideos" }
    var collection: String { self == .image ? "images" : "videos" }
    var specs: String { self == .image ? "imageSpecs" : "videoSpecs" }
}

enum AssetLibraryTarget: String, Codable, Sendable, CaseIterable {
    case appStoreVersionLocalization
    case appCustomProductPageLocalization
    case appStoreVersionExperimentTreatmentLocalization
    case appEventLocalization

    var resourceType: String { rawValue + "s" }
    var feature: String {
        switch self {
        case .appStoreVersionLocalization: "APP_STORE_VERSIONS"
        case .appCustomProductPageLocalization: "CUSTOM_PRODUCT_PAGES"
        case .appStoreVersionExperimentTreatmentLocalization: "PRODUCT_PAGE_OPTIMIZATIONS"
        case .appEventLocalization: "IN_APP_EVENTS"
        }
    }
}

enum AssetLibraryAction: String, Codable, Sendable, CaseIterable {
    case uploadImage = "upload_image"
    case uploadVideo = "upload_video"
    case updateReferenceName = "update_reference_name"
    case updateVideoPoster = "update_video_poster"
    case createPlacement = "create_placement"
    case replacePlacement = "replace_placement"
    case deletePlacement = "delete_placement"
    case reorderPlacements = "reorder_placements"
    case archiveAsset = "archive_asset"
    case unarchiveAsset = "unarchive_asset"
    case deleteAsset = "delete_asset"
    case addReviewItem = "add_review_item"

    var isUpload: Bool { self == .uploadImage || self == .uploadVideo }
}

struct AssetPreviousPlacement: Codable, Sendable {
    let assetKind: AssetLibraryKind
    let assetID: String
    let target: AssetLibraryTarget
    let targetID: String
    let placementType: String
    let placementGroup: String
    var orderedPlacementIDs: [String]
}

struct AssetLibraryChange: Codable, Sendable {
    let action: AssetLibraryAction
    let appID: String
    var kind: AssetLibraryKind?
    var assetID: String?
    var category: String?
    var referenceName: String?
    var previewFrameTimeCode: String?
    var target: AssetLibraryTarget?
    var targetID: String?
    var placementType: String?
    var placementGroup: String?
    var placementID: String?
    var orderedPlacementIDs: [String]?
    var submissionID: String?
    var expectedSpecIDs: [String]?
    var fileSHA256: String?
    var fileName: String?
    var fileSize: Int?
    var resumeOperationID: String?
    var previousPlacement: AssetPreviousPlacement?
    var baseline: [String: String] = [:]
    var warnings: [String] = []
}

struct AssetLibraryOperation: Codable, Sendable {
    let id: String
    let account: String
    let createdAt: Date
    var updatedAt: Date
    var status: String
    var change: AssetLibraryChange
    var resourceIDs: [String: String] = [:]
    var completedSteps: [String] = []
    var pendingStep: String?
    var message: String?

    var unresolved: Bool { ["running", "outcome_unknown", "processing_pending", "requires_reconciliation"].contains(status) }
}

enum AssetLibraryJSON {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func fingerprint<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try encode(value)).map { String(format: "%02x", $0) }.joined()
    }

    static func body(type: String, id: String? = nil, attributes: [String: JSONValue] = [:], relationships: [String: JSONValue] = [:]) throws -> Data {
        var data: [String: JSONValue] = ["type": .string(type)]
        if let id { data["id"] = .string(id) }
        if !attributes.isEmpty { data["attributes"] = .object(attributes) }
        if !relationships.isEmpty { data["relationships"] = .object(relationships) }
        return try encode(JSONValue.object(["data": .object(data)]))
    }

    static func value<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: encode(value))
    }

    static func identifier(_ value: String, field: String) throws -> String {
        guard !value.isEmpty, value.count <= 256, try ASCPathSegment.encode(value, field: field) == value else {
            throw AssetLibraryError("'\(field)' must be a canonical resource identifier")
        }
        return value
    }
}
