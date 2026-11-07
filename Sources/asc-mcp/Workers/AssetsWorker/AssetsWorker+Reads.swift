import Foundation
import MCP

extension AssetsWorker {
    func readTool(_ name: String, _ arguments: [String: Value]) async throws -> CallTool.Result {
        if name == "assets_get_reference_data" {
            if arguments["reference_id"] != nil {
                guard arguments.count == 1 else { throw AssetLibraryError("Reference ID cannot be combined with collection filters") }
                return MCPResult.jsonObject(["success": true, "reference_data": try await resource("appAssetLibraryRefData", identifier("reference_id", arguments)).projection()])
            }
            let query = try filterQuery(arguments, mapping: ["features": "features", "placement_types": "placementTypes", "placement_groups": "placementProfileGroups", "spec_ids": "specs"])
            let response = try await httpClient.get("/v1/appAssetLibraryRefData", parameters: query, as: AssetLibraryCollection.self)
            guard response.data.allSatisfy({ $0.type == "appAssetLibraryRefData" }), response.next == nil else { throw AssetLibraryError("Invalid reference-data response") }
            return MCPResult.jsonObject(["success": true, "reference_data": response.data.map { $0.projection() }])
        }
        let appID = try identifier("app_id", arguments)
        if name == "assets_get_library" {
            return MCPResult.jsonObject(["success": true, "app_id": appID, "library": try await library(appID: appID).projection()])
        }
        if name == "assets_get_image" || name == "assets_get_video" {
            let kind: AssetLibraryKind = name == "assets_get_image" ? .image : .video
            let asset = try await ownedAsset(appID: appID, kind: kind, id: identifier("asset_id", arguments))
            return MCPResult.jsonObject(["success": true, "app_id": appID, "asset": asset.projection()])
        }
        if name == "assets_get_placement" {
            let placement = try await ownedPlacement(appID: appID, id: identifier("placement_id", arguments), requireEditable: false)
            return MCPResult.jsonObject(["success": true, "app_id": appID, "placement": placement.projection()])
        }
        var path: String
        var query: [String: String]
        let type: String
        if name == "assets_list_images" || name == "assets_list_videos" {
            let kind: AssetLibraryKind = name == "assets_list_images" ? .image : .video
            let library = try await library(appID: appID)
            path = "/v1/appAssetLibraries/\(try ASCPathSegment.encode(library.id))/\(try ASCPathSegment.encode(kind.collection))"
            query = try filterQuery(arguments, mapping: ["categories": "category", "states": "state", "reference_names": "referenceName", "spec_ids": "specId", "asset_ids": "id"])
            type = kind.resourceType
        } else {
            let assetSelector = arguments["asset_id"] != nil || arguments["asset_kind"] != nil
            let targetSelector = arguments["target_id"] != nil || arguments["target_type"] != nil
            guard assetSelector != targetSelector else { throw AssetLibraryError("Provide exactly one asset selector or one localization selector") }
            if assetSelector {
                guard let kind = AssetLibraryKind(rawValue: try required("asset_kind", arguments)) else { throw AssetLibraryError("Invalid asset_kind") }
                let id = try identifier("asset_id", arguments)
                _ = try await ownedAsset(appID: appID, kind: kind, id: id)
                path = "/v1/\(try ASCPathSegment.encode(kind.resourceType))/\(try ASCPathSegment.encode(id))/placements"
            } else {
                let (target, id) = try targetArguments(arguments)
                _ = try await targetScope(appID: appID, target: target, id: id, requireEditable: false)
                if target.isToOnePlacementEndpoint {
                    guard arguments["next_url"] == nil else {
                        throw AssetLibraryError("next_url is not supported for to-one placement targets")
                    }
                    if let input = arguments["limit"] {
                        guard let value = input.intValue, (1...200).contains(value) else {
                            throw AssetLibraryError("limit must be an integer between 1 and 200")
                        }
                    }
                    let allowedTypes = arguments["placement_types"] != nil ? Set(try stringList("placement_types", arguments)) : nil
                    let allowedGroups = arguments["placement_groups"] != nil ? Set(try stringList("placement_groups", arguments)) : nil
                    let placements = try await targetPlacements(target: target, id: id).filter { placement in
                        let matchesType = allowedTypes.map {
                            guard let type = placement.attributes?["placementType"]?.stringValue else { return false }
                            return $0.contains(type)
                        } ?? true
                        let matchesGroup = allowedGroups.map {
                            guard let group = placement.attributes?["placementGroup"]?.stringValue else { return false }
                            return $0.contains(group)
                        } ?? true
                        return matchesType && matchesGroup
                    }
                    return MCPResult.jsonObject([
                        "success": true,
                        "app_id": appID,
                        "resources": placements.map { $0.projection() },
                        "count": placements.count
                    ])
                }
                path = try target.placementsPath(id: id)
            }
            type = "appAssetLibraryPlacements"
            query = try filterQuery(arguments, mapping: ["placement_types": "placementType", "placement_groups": "placementGroup"])
            query["include"] = Self.placementIncludes
            query["sort"] = "placementGroupPosition"
        }
        let limit: Int
        if let input = arguments["limit"] {
            guard let value = input.intValue, (1...200).contains(value) else { throw AssetLibraryError("limit must be an integer between 1 and 200") }
            limit = value
        } else { limit = 50 }
        query["limit"] = String(limit)
        let page: AssetLibraryCollection
        if arguments["next_url"] != nil {
            page = try await httpClient.getPage(required("next_url", arguments), scope: PaginationScope.strict(path: path, query: query), as: AssetLibraryCollection.self)
        } else { page = try await httpClient.get(path, parameters: query, as: AssetLibraryCollection.self) }
        guard page.data.allSatisfy({ $0.type == type }), Set(page.data.map(\.id)).count == page.data.count else { throw AssetLibraryError("Invalid resource collection") }
        if let next = page.next { _ = try httpClient.validatedScopedLink(next, scope: PaginationScope.strict(path: path, query: query)) }
        var result: [String: Any] = ["success": true, "app_id": appID, "resources": page.data.map { $0.projection() }, "count": page.data.count]
        if let next = page.next { result["next_url"] = next }
        if let meta = page.meta { result["meta"] = meta.asAny }
        return MCPResult.jsonObject(result)
    }

    func referenceData(refresh: Bool = false) async throws -> AssetLibraryResource {
        if !refresh, let cached = await referenceCache.get() { return cached }
        let response = try await httpClient.get("/v1/appAssetLibraryRefData", as: AssetLibraryCollection.self)
        guard response.data.count == 1, let resource = response.data.first, resource.type == "appAssetLibraryRefData", response.next == nil else {
            throw AssetLibraryError("Apple did not return a complete reference catalog")
        }
        for key in ["features", "placementProfileGroups", "imageSpecs", "videoSpecs", "placementTypes", "displayClasses"] {
            guard resource.attributes?[key]?.arrayValue != nil else { throw AssetLibraryError("Reference catalog is missing \(key)") }
        }
        await referenceCache.set(resource)
        return resource
    }

    func targetArguments(_ arguments: [String: Value]) throws -> (AssetLibraryTarget, String) {
        guard let target = AssetLibraryTarget(rawValue: try required("target_type", arguments)) else { throw AssetLibraryError("Unsupported target_type") }
        return (target, try identifier("target_id", arguments))
    }

    func targetScope(appID: String, target: AssetLibraryTarget, id: String, requireEditable: Bool) async throws -> [String: String] {
        let parentRelation: String
        switch target {
        case .appStoreVersionLocalization: parentRelation = "appStoreVersion"
        case .appCustomProductPageLocalization: parentRelation = "appCustomProductPageVersion"
        case .appStoreVersionExperimentTreatmentLocalization: parentRelation = "appStoreVersionExperimentTreatment"
        case .appEventLocalization: parentRelation = "appEvent"
        case .retentionMessageVersion: parentRelation = "retentionMessage"
        }
        let localization = try await resource(target.resourceType, id, include: parentRelation)
        guard let parentID = localization.related(parentRelation),
              parentID.type == parentRelation + "s",
              (try? AssetLibraryJSON.identifier(parentID.id, field: parentRelation)) == parentID.id else {
            throw AssetLibraryError("Localization has no verifiable parent")
        }
        var checked = [localization]
        let owner: AssetLibraryResourceID?
        let state: String?
        switch target {
        case .appStoreVersionLocalization:
            let parent = try await resource(parentID.type, parentID.id, include: "app")
            checked.append(parent)
            owner = parent.related("app")
            state = parent.attributes?["appVersionState"]?.stringValue ?? parent.attributes?["appStoreState"]?.stringValue
        case .appCustomProductPageLocalization:
            let version = try await resource(parentID.type, parentID.id, include: "appCustomProductPage")
            guard let pageID = version.related("appCustomProductPage"), pageID.type == "appCustomProductPages" else { throw AssetLibraryError("CPP version has no verifiable page") }
            let page = try await resource(pageID.type, pageID.id, include: "app")
            checked += [version, page]
            owner = page.related("app")
            state = version.state
        case .appStoreVersionExperimentTreatmentLocalization:
            let treatment = try await resource(parentID.type, parentID.id, include: "appStoreVersionExperimentV2")
            guard let experimentID = treatment.related("appStoreVersionExperimentV2"), experimentID.type == "appStoreVersionExperiments" else { throw AssetLibraryError("Treatment has no verifiable v2 experiment") }
            let experiment = try await resource(experimentID.type, experimentID.id, include: "app", version: "v2")
            checked += [treatment, experiment]
            owner = experiment.related("app")
            state = experiment.state
        case .appEventLocalization:
            let event = try await resource(parentID.type, parentID.id)
            let members = try await all("/v1/apps/\(try ASCPathSegment.encode(appID))/appEvents", query: ["filter[id]": event.id], type: "appEvents")
            guard members.count == 1, members.first?.id == event.id else { throw AssetLibraryError("Event does not belong to this app") }
            checked.append(event)
            owner = AssetLibraryResourceID(type: "apps", id: appID)
            state = event.attributes?["eventState"]?.stringValue
        case .retentionMessageVersion:
            let members = try await all("/v1/apps/\(try ASCPathSegment.encode(appID))/retentionMessages", type: "retentionMessages")
            let matches = members.filter { $0.id == parentID.id }
            guard matches.count == 1, let message = matches.first else {
                throw AssetLibraryError("Retention message does not belong to this app")
            }
            checked.append(message)
            owner = AssetLibraryResourceID(type: "apps", id: appID)
            state = localization.state
        }
        guard owner == AssetLibraryResourceID(type: "apps", id: appID) else { throw AssetLibraryError("Localization belongs to another application") }
        if requireEditable {
            let allowed: Set<String> = target == .appEventLocalization
                ? ["DRAFT", "READY_FOR_REVIEW", "REJECTED"]
                : ["PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"]
            guard let state, allowed.contains(state) else { throw AssetLibraryError("Parent is not in a supported editable draft state") }
        }
        var result = try Dictionary(uniqueKeysWithValues: checked.map { ($0.type + ":" + $0.id, try $0.fingerprint()) })
        if target != .retentionMessageVersion {
            var platforms = Set(checked.compactMap { $0.attributes?["platform"]?.stringValue })
            if platforms.isEmpty {
                let versions = try await all("/v1/apps/\(try ASCPathSegment.encode(appID))/appStoreVersions", type: "appStoreVersions")
                platforms = Set(versions.compactMap { $0.attributes?["platform"]?.stringValue })
            }
            result["target_platforms"] = platforms.sorted().joined(separator: ",")
        }
        return result
    }

    func ownedPlacement(appID: String, id: String, requireEditable: Bool) async throws -> AssetLibraryResource {
        let placement = try await resource("appAssetLibraryPlacements", id, include: Self.placementIncludes)
        let targets = AssetLibraryTarget.allCases.compactMap { target -> (AssetLibraryTarget, String)? in
            guard let parent = placement.related(target.rawValue), parent.type == target.resourceType else { return nil }
            return (target, parent.id)
        }
        guard targets.count == 1, let (target, parentID) = targets.first else { throw AssetLibraryError("Placement must have exactly one verifiable localization") }
        _ = try await targetScope(appID: appID, target: target, id: parentID, requireEditable: requireEditable)
        return placement
    }

    func targetPlacements(target: AssetLibraryTarget, id: String) async throws -> [AssetLibraryResource] {
        let path = try target.placementsPath(id: id)
        if target.isToOnePlacementEndpoint {
            let doc = try await httpClient.get(path, parameters: ["include": Self.placementIncludes], as: AssetOptionalLibraryDocument.self)
            if let selfLink = doc.links?["self"]?.stringValue {
                _ = try httpClient.validatedScopedLink(selfLink, scope: PaginationScope(path: path, allowedParameters: ["include"]))
            }
            guard let placement = doc.data else { return [] }
            guard placement.type == "appAssetLibraryPlacements",
                  (try? AssetLibraryJSON.identifier(placement.id, field: "placement_id")) == placement.id else {
                throw AssetLibraryError("Invalid appAssetLibraryPlacements resource")
            }
            let targets = AssetLibraryTarget.allCases.compactMap { candidate -> (AssetLibraryTarget, AssetLibraryResourceID)? in
                guard let related = placement.related(candidate.rawValue) else { return nil }
                return (candidate, related)
            }
            if !targets.isEmpty {
                guard targets.count == 1,
                      targets.first?.0 == target,
                      targets.first?.1 == AssetLibraryResourceID(type: target.resourceType, id: id) else {
                    throw AssetLibraryError("Placement target mismatch for \(target.rawValue)")
                }
            }
            return [placement]
        }
        return try await all(path, query: ["include": Self.placementIncludes, "sort": "placementGroupPosition"], type: "appAssetLibraryPlacements")
    }

    func filterQuery(_ arguments: [String: Value], mapping: [String: String]) throws -> [String: String] {
        var query: [String: String] = [:]
        for (argument, apple) in mapping where arguments[argument] != nil {
            query["filter[\(apple)]"] = try stringList(argument, arguments).joined(separator: ",")
        }
        return query
    }

    func stringList(_ name: String, _ arguments: [String: Value]) throws -> [String] {
        guard let values = arguments[name]?.arrayValue, (1...200).contains(values.count) else { throw AssetLibraryError("'\(name)' must contain between 1 and 200 strings") }
        let strings = try values.map { value -> String in
            guard let string = value.stringValue, !string.isEmpty, string.count <= 256,
                  !string.contains(","), string == string.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw AssetLibraryError("Invalid value in '\(name)'")
            }
            return string
        }
        guard Set(strings).count == strings.count else { throw AssetLibraryError("Duplicate values in '\(name)'") }
        return strings
    }
}
