import Foundation
import MCP

// MARK: - Tool Handlers
extension AppsWorker {
    private struct AppSearchCollection: Sendable {
        let apps: [ASCApp]
        let pagesFetched: Int
    }

    private func fetchAllSearchApps(query: String, filter: String) async throws -> AppSearchCollection {
        let path = "/v1/apps"
        let parameters = [
            filter: query,
            "fields[apps]": "name,bundleId,sku,primaryLocale",
            "limit": "200",
            "sort": "name,bundleId,sku"
        ]
        let scope = PaginationScope(
            path: path,
            requiredParameters: parameters,
            allowedParameters: Set(parameters.keys).union(Set(["cursor"]))
        )
        var response: ASCAppsResponse? = try await httpClient.get(
            path,
            parameters: parameters,
            as: ASCAppsResponse.self
        )
        var apps: [ASCApp] = []
        var pagesFetched = 0
        var seenNextURLs: Set<String> = []

        while let page = response {
            pagesFetched += 1
            apps.append(contentsOf: page.data)

            guard let next = page.links.next else {
                response = nil
                continue
            }
            guard seenNextURLs.insert(next).inserted else {
                throw ASCError.parsing("Apps search pagination returned a repeated next URL")
            }
            response = try await httpClient.getPage(next, scope: scope, as: ASCAppsResponse.self)
        }

        return AppSearchCollection(apps: apps, pagesFetched: pagesFetched)
    }

    private func orderedUniqueSearchApps(_ apps: [ASCApp]) -> [ASCApp] {
        var seenIDs: Set<String> = []
        return apps
            .filter { seenIDs.insert($0.id).inserted }
            .sorted { lhs, rhs in
                let left = [
                    lhs.attributes?.name ?? "",
                    lhs.attributes?.bundleId ?? "",
                    lhs.attributes?.sku ?? "",
                    lhs.id
                ]
                let right = [
                    rhs.attributes?.name ?? "",
                    rhs.attributes?.bundleId ?? "",
                    rhs.attributes?.sku ?? "",
                    rhs.id
                ]
                for (leftPart, rightPart) in zip(left, right) where leftPart != rightPart {
                    return leftPart < rightPart
                }
                return false
            }
    }

    private func effectiveVersionState(_ version: ASCAppStoreVersion) -> String {
        version.attributes?.appVersionState ?? version.attributes?.appStoreState ?? "UNKNOWN"
    }

    private func versionBelongsToApp(_ version: ASCAppStoreVersion, appId: String) -> Bool {
        guard let data = version.relationships?.app?.data,
              case .single(let app) = data else {
            return false
        }
        return app.type == "apps" && app.id == appId
    }

    private func localizationBelongsToVersion(_ localization: ASCAppStoreVersionLocalization, versionId: String) -> Bool {
        guard let data = localization.relationships?.appStoreVersion?.data,
              case .single(let version) = data else {
            return false
        }
        return version.type == "appStoreVersions" && version.id == versionId
    }

    private func fetchAllVersions(appId: String) async throws -> [ASCAppStoreVersion] {
        let path = "/v1/apps/\(try ASCPathSegment.encode(appId))/appStoreVersions"
        let versionFields = "platform,versionString,appVersionState,appStoreState,createdDate"
        var response: ASCAppStoreVersionsResponse? = try await httpClient.get(
            path,
            parameters: [
                "fields[appStoreVersions]": versionFields,
                "limit": "200"
            ],
            as: ASCAppStoreVersionsResponse.self
        )
        var versions: [ASCAppStoreVersion] = []
        while let page = response {
            versions.append(contentsOf: page.data)
            if let next = page.links?.next {
                response = try await httpClient.getPage(
                    next,
                    scope: PaginationScope(
                        path: path,
                        requiredParameters: [
                            "fields[appStoreVersions]": versionFields,
                            "limit": "200"
                        ]
                    ),
                    as: ASCAppStoreVersionsResponse.self
                )
            } else {
                response = nil
            }
        }
        return versions
    }

    private func nullableMetadataString(_ name: String, from arguments: [String: Value]) throws -> NullableAttributeValue? {
        guard let value = arguments[name] else {
            return nil
        }
        if value.isNull {
            return .null
        }
        guard let string = value.stringValue else {
            throw AppsMetadataArgumentError("\(name) must be a string or null")
        }
        return .string(string)
    }

    private func validateAppStoreMetadataArguments(
        _ arguments: [String: Value],
        locale: String
    ) -> [ASCMetadataValidator.FieldError] {
        var errors = ASCMetadataValidator.validateLocale(locale)

        var textFields: [String: String] = [:]
        for key in ["description", "whats_new", "keywords", "promotional_text"] {
            if let value = arguments[key]?.stringValue {
                textFields[key] = value
            }
        }

        errors += ASCMetadataValidator.validateTextFields(
            textFields,
            limits: [
                "description": 4_000,
                "whats_new": 4_000,
                "keywords": 100,
                "promotional_text": 170
            ]
        )

        for key in ["support_url", "marketing_url"] {
            if let value = arguments[key]?.stringValue, !value.isEmpty {
                errors += ASCMetadataValidator.validateHTTPURL(value, field: key)
            }
        }

        return errors
    }

    private func updatedMetadataFieldNames(
        _ attributes: ASCAppStoreVersionLocalizationUpdateRequest.Data.Attributes
    ) -> [String] {
        var fields: [String] = []
        if attributes.description != nil { fields.append("description") }
        if attributes.whatsNew != nil { fields.append("whats_new") }
        if attributes.keywords != nil { fields.append("keywords") }
        if attributes.promotionalText != nil { fields.append("promotional_text") }
        if attributes.supportUrl != nil { fields.append("support_url") }
        if attributes.marketingUrl != nil { fields.append("marketing_url") }
        return fields
    }

    
    /// Lists all apps from App Store Connect with optional filtering
    /// - Returns: JSON array of apps with their IDs, names, bundle IDs, and metadata
    /// - Throws: CallTool.Result with error if API call fails
    public func listApps(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        let effectiveLimit = min(max(arguments["limit"]?.intValue ?? 25, 1), 200)

        do {
            let response: ASCAppsResponse

            // Check for pagination next_url
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                var requiredParameters: [String: String] = ["limit": String(effectiveLimit)]
                if let sort = arguments["sort"]?.stringValue {
                    requiredParameters["sort"] = sort
                }
                if let bundleId = arguments["bundle_id"]?.stringValue {
                    requiredParameters["filter[bundleId]"] = bundleId
                }
                if let name = arguments["name"]?.stringValue {
                    requiredParameters["filter[name]"] = name
                }
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: "/v1/apps", requiredParameters: requiredParameters),
                    as: ASCAppsResponse.self
                )
            } else {
                var queryParams: [String: String] = ["limit": String(effectiveLimit)]

                if let sort = arguments["sort"]?.stringValue {
                    queryParams["sort"] = sort
                }
                if let bundleId = arguments["bundle_id"]?.stringValue {
                    queryParams["filter[bundleId]"] = bundleId
                }
                if let name = arguments["name"]?.stringValue {
                    queryParams["filter[name]"] = name
                }

                response = try await httpClient.get("/v1/apps", parameters: queryParams, as: ASCAppsResponse.self)
            }

            // Format result
            let apps = response.data.map { app in
                [
                    "id": app.id,
                    "name": app.displayName,
                    "bundleId": app.bundleIdentifier,
                    "sku": app.appSKU,
                    "primaryLocale": app.locale,
                    "type": app.type,
                    "attributes": [
                        "availableInNewTerritories": (app.attributes?.availableInNewTerritories).jsonSafe,
                        "contentRightsDeclaration": (app.attributes?.contentRightsDeclaration).jsonSafe,
                        "isOrEverWasMadeForKids": (app.attributes?.isOrEverWasMadeForKids).jsonSafe
                    ]
                ] as [String: Any]
            }

            var result: [String: Any] = [
                "success": true,
                "apps": apps,
                "count": response.data.count,
                "totalCount": response.totalCount,
                "hasNextPage": response.hasNextPage,
                "links": [
                    "self": response.links.`self`,
                    "first": response.links.first.jsonSafe,
                    "next": response.links.next.jsonSafe
                ]
            ]

            if let nextUrl = response.links.next {
                result["next_url"] = nextUrl
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list apps: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    /// Gets detailed information about a specific app
    /// - Returns: JSON with complete app data including relationships and attributes
    /// - Throws: CallTool.Result with error if app_id missing or API call fails
    public func getAppDetails(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }
        
        do {
            // Parameters for including additional information
            var queryParams: [String: String] = [:]
            
            if let arguments = params.arguments,
               let includeValue = arguments["include"],
               let include = includeValue.stringValue {
                queryParams["include"] = include
            }
            
            // Execute request
            let response: ASCAppResponse = try await httpClient.get("/v1/apps/\(try ASCPathSegment.encode(appId))", parameters: queryParams, as: ASCAppResponse.self)
            let app = response.data
            
            // Format detailed response
            let relationships = app.relationships?.values.mapValues(formatRelationship) ?? [:]
            
            var result: [String: Any] = [
                "success": true,
                "app": [
                    "id": app.id,
                    "type": app.type,
                    "name": app.displayName,
                    "bundleId": app.bundleIdentifier,
                    "sku": app.appSKU,
                    "primaryLocale": app.locale,
                    "attributes": [
                        "availableInNewTerritories": (app.attributes?.availableInNewTerritories).jsonSafe,
                        "contentRightsDeclaration": (app.attributes?.contentRightsDeclaration).jsonSafe,
                        "isOrEverWasMadeForKids": (app.attributes?.isOrEverWasMadeForKids).jsonSafe,
                        "subscriptionStatusUrl": (app.attributes?.subscriptionStatusUrl).jsonSafe,
                        "subscriptionStatusUrlVersion": (app.attributes?.subscriptionStatusUrlVersion).jsonSafe,
                        "subscriptionStatusUrlForSandbox": (app.attributes?.subscriptionStatusUrlForSandbox).jsonSafe,
                        "subscriptionStatusUrlVersionForSandbox": (app.attributes?.subscriptionStatusUrlVersionForSandbox).jsonSafe
                    ],
                    "relationships": relationships
                ]
            ]

            if let included = response.included {
                result["included"] = included.map(\.asAny)
            }
            
            return MCPResult.jsonObject(result)
            
        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get app details: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    /// Searches for apps by name or bundle ID
    /// - Returns: JSON array of matching apps with their details
    /// - Throws: CallTool.Result with error if query parameter missing or search fails
    public func searchApps(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let queryValue = arguments["query"],
              let query = queryValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'query' is missing")],
                isError: true
            )
        }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Parameter 'query' must be a non-empty string")],
                isError: true
            )
        }
        
        do {
            let nameResults = try await fetchAllSearchApps(query: query, filter: "filter[name]")
            let bundleIdResults = try await fetchAllSearchApps(query: query, filter: "filter[bundleId]")
            let allApps = orderedUniqueSearchApps(nameResults.apps + bundleIdResults.apps)
            
            let apps = allApps.map { app in
                [
                    "id": app.id,
                    "name": app.displayName,
                    "bundleId": app.bundleIdentifier,
                    "sku": app.appSKU,
                    "primaryLocale": app.locale,
                    "type": app.type
                ] as [String: Any]
            }
            
            let result: [String: Any] = [
                "success": true,
                "query": query,
                "count": allApps.count,
                "apps": apps,
                "searchedIn": ["name", "bundleId"],
                "pagesFetched": nameResults.pagesFetched + bundleIdResults.pagesFetched
            ]
            
            return MCPResult.jsonObject(result)
            
        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to search apps: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    /// Lists all versions for an app with their IDs and states
    /// - Returns: JSON array of versions with IDs, version strings, platforms and states
    /// - Throws: CallTool.Result with error if app_id missing or API call fails
    public func listAppVersions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAppStoreVersionsResponse
            let versionFields = "platform,versionString,appVersionState,appStoreState,createdDate"

            // Check for pagination next_url
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(
                        path: "/v1/apps/\(try ASCPathSegment.encode(appId))/appStoreVersions",
                        requiredParameters: [
                            "fields[appStoreVersions]": versionFields,
                            "limit": "200"
                        ]
                    ),
                    as: ASCAppStoreVersionsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v1/apps/\(try ASCPathSegment.encode(appId))/appStoreVersions",
                    parameters: [
                        "limit": "200",
                        "fields[appStoreVersions]": versionFields
                    ],
                    as: ASCAppStoreVersionsResponse.self
                )
            }

            let versions = response.data.map { version in
                return [
                    "id": version.id,
                    "versionString": version.attributes?.versionString ?? "N/A",
                    "platform": version.attributes?.platform ?? "UNKNOWN",
                    "appVersionState": (version.attributes?.appVersionState).jsonSafe,
                    "appStoreState": (version.attributes?.appStoreState).jsonSafe,
                    "state": version.state,
                    "createdDate": version.attributes?.createdDate ?? "",
                    "type": version.type
                ] as [String: Any]
            }

            var result: [String: Any] = [
                "success": true,
                "appId": appId,
                "count": versions.count,
                "versions": versions
            ]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list versions: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    /// Gets localized metadata for a specific app version
    /// - Returns: JSON with localized metadata. Single locale or all localizations depending on params.
    ///   Optionally includes media (videos/screenshots) when include_media=true.
    /// - Throws: CallTool.Result with error if required parameters missing or API call fails
    public func getAppMetadata(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        // Optional parameters
        let locale = arguments["locale"]?.stringValue
        let versionIdParam = arguments["version_id"]?.stringValue
        let versionStateFilter = arguments["version_state"]?.stringValue
        let platformFilter = arguments["platform"]?.stringValue
        let includeMedia = arguments["include_media"]?.boolValue ?? false

        do {
            // Step 1: Resolve version
            let resolvedVersion: (id: String, versionString: String, appVersionState: String?, appStoreState: String?, platform: String?)

            if let versionId = versionIdParam {
                // Use provided version_id — fetch its details
                let versionResponse: ASCAppStoreVersionResponse = try await httpClient.get(
                    "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))",
                    parameters: ["fields[appStoreVersions]": "app,platform,versionString,appVersionState,appStoreState"],
                    as: ASCAppStoreVersionResponse.self
                )
                let v = versionResponse.data
                guard versionBelongsToApp(v, appId: appId) else {
                    return MCPResult.error("Version '\(versionId)' does not belong to app '\(appId)'")
                }
                if let platformFilter, v.attributes?.platform != platformFilter {
                    return MCPResult.error("Version '\(versionId)' is not on platform '\(platformFilter)'")
                }
                resolvedVersion = (
                    id: v.id,
                    versionString: v.version,
                    appVersionState: v.attributes?.appVersionState,
                    appStoreState: v.attributes?.appStoreState,
                    platform: v.attributes?.platform
                )
            } else {
                let versions = try await fetchAllVersions(appId: appId)

                guard !versions.isEmpty else {
                    return CallTool.Result(
                        content: [MCPContent.text(JSONFormatter.formatJSON([
                            "success": false,
                            "error": "App \(appId) has no versions"
                        ] as [String: Any]))],
                        isError: true
                    )
                }

                let platformVersions = platformFilter.map { platform in
                    versions.filter { $0.attributes?.platform == platform }
                } ?? versions

                guard !platformVersions.isEmpty else {
                    return MCPResult.error("App '\(appId)' has no versions for platform '\(platformFilter ?? "UNKNOWN")'")
                }
                let selected: ASCAppStoreVersion

                if let stateFilter = versionStateFilter {
                    guard let match = platformVersions.first(where: { effectiveVersionState($0) == stateFilter }) else {
                        let available = Set(platformVersions.map(effectiveVersionState)).sorted().joined(separator: ", ")
                        return CallTool.Result(
                            content: [MCPContent.text(JSONFormatter.formatJSON([
                                "success": false,
                                "error": "Version with state '\(stateFilter)' not found. Available: \(available)"
                            ] as [String: Any]))],
                            isError: true
                        )
                    }
                    selected = match
                } else {
                    let platformPriority = ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]

                    func preferredByPlatform(_ candidates: [ASCAppStoreVersion]) -> ASCAppStoreVersion? {
                        for platform in platformPriority {
                            if let match = candidates.first(where: { $0.attributes?.platform == platform }) {
                                return match
                            }
                        }
                        return candidates.first
                    }

                    let statePriority = [
                        "PREPARE_FOR_SUBMISSION",
                        "REJECTED",
                        "METADATA_REJECTED",
                        "READY_FOR_DISTRIBUTION",
                        "READY_FOR_SALE"
                    ]
                    selected = statePriority
                        .lazy
                        .compactMap { state in
                            preferredByPlatform(platformVersions.filter { self.effectiveVersionState($0) == state })
                        }
                        .first ?? platformVersions[0]
                }

                resolvedVersion = (
                    id: selected.id,
                    versionString: selected.attributes?.versionString ?? "N/A",
                    appVersionState: selected.attributes?.appVersionState,
                    appStoreState: selected.attributes?.appStoreState,
                    platform: selected.attributes?.platform
                )
            }

            // Step 2: Fetch localizations
            var localizationParams: [String: String] = [
                "fields[appStoreVersionLocalizations]": "description,locale,keywords,marketingUrl,promotionalText,supportUrl,whatsNew,appStoreVersion",
                "limit": "200"
            ]
            if let locale = locale {
                localizationParams["filter[locale]"] = locale
            }

            let localizationsResponse: ASCAppStoreVersionLocalizationsResponse = try await httpClient.get(
                "/v1/appStoreVersions/\(try ASCPathSegment.encode(resolvedVersion.id))/appStoreVersionLocalizations",
                parameters: localizationParams,
                as: ASCAppStoreVersionLocalizationsResponse.self
            )

            // Check if locale filter returned empty results
            if let locale = locale, localizationsResponse.data.isEmpty {
                return CallTool.Result(
                    content: [MCPContent.text(JSONFormatter.formatJSON([
                        "success": false,
                        "error": "Localization '\(locale)' not found for version \(resolvedVersion.versionString)"
                    ] as [String: Any]))],
                    isError: true
                )
            }

            guard localizationsResponse.data.allSatisfy({ localizationBelongsToVersion($0, versionId: resolvedVersion.id) }) else {
                return MCPResult.error("Apple returned a localization outside version '\(resolvedVersion.id)' context")
            }

            let versionInfo: [String: Any] = [
                "id": resolvedVersion.id,
                "versionString": resolvedVersion.versionString,
                "platform": resolvedVersion.platform.jsonSafe,
                "appVersionState": resolvedVersion.appVersionState.jsonSafe,
                "appStoreState": resolvedVersion.appStoreState.jsonSafe,
                "state": resolvedVersion.appVersionState ?? resolvedVersion.appStoreState ?? "UNKNOWN"
            ]

            // Helper to format a single localization
            func formatLocalization(_ loc: ASCAppStoreVersionLocalization) -> [String: Any] {
                var data: [String: Any] = [
                    "id": loc.id,
                    "locale": loc.locale
                ]
                if let v = loc.attributes?.description { data["description"] = v }
                if let v = loc.attributes?.whatsNew { data["whatsNew"] = v }
                if let v = loc.attributes?.keywords { data["keywords"] = v }
                if let v = loc.attributes?.promotionalText { data["promotionalText"] = v }
                if let v = loc.attributes?.supportUrl { data["supportUrl"] = v }
                if let v = loc.attributes?.marketingUrl { data["marketingUrl"] = v }
                return data
            }

            var result: [String: Any] = ["success": true, "version": versionInfo]

            if locale != nil {
                // Single locale mode
                let loc = localizationsResponse.data[0]
                result["localization"] = formatLocalization(loc)

                // Step 3: Fetch media if requested
                if includeMedia {
                    let mediaResult = try await fetchMedia(for: loc.id)
                    result["appPreviewSets"] = mediaResult.previews
                    result["screenshotSets"] = mediaResult.screenshots
                }
            } else {
                // All locales mode
                let formatted = localizationsResponse.data
                    .sorted { $0.locale < $1.locale }
                    .map { formatLocalization($0) }
                result["totalLocalizations"] = formatted.count
                result["localizations"] = formatted
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get metadata: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Fetches media (preview videos and screenshots) for a localization
    /// - Returns: Tuple with optional preview sets and screenshot sets arrays
    private func fetchMedia(for localizationId: String) async throws -> (previews: [[String: Any]], screenshots: [[String: Any]]) {
        let previewPath = "/v1/appStoreVersionLocalizations/\(try ASCPathSegment.encode(localizationId))/appPreviewSets"
        let screenshotPath = "/v1/appStoreVersionLocalizations/\(try ASCPathSegment.encode(localizationId))/appScreenshotSets"
        let previewInclude = "appPreviews"
        let screenshotInclude = "appScreenshots"
        var previews: [[String: Any]] = []
        var screenshots: [[String: Any]] = []
        var previewResponse: ASCAppPreviewSetsResponse? = try await httpClient.get(
            previewPath,
            parameters: ["include": previewInclude, "limit": "200", "limit[appPreviews]": "50"],
            as: ASCAppPreviewSetsResponse.self
        )

        while let response = previewResponse {
            for previewSet in response.data {
                    var setInfo: [String: Any] = ["id": previewSet.id]
                    if let previewType = previewSet.attributes?.previewType {
                        setInfo["previewType"] = previewType
                    }
                    if let included = response.included, !included.isEmpty {
                        var previewIds: [String] = []
                        if let data = previewSet.relationships?.appPreviews?.data {
                            switch data {
                            case .multiple(let ids): previewIds = ids.map { $0.id }
                            case .single(let id): previewIds = [id.id]
                            }
                        }
                        var items: [[String: Any]] = []
                        for pid in previewIds {
                            if let p = included.first(where: { $0.id == pid }) {
                                var item: [String: Any] = ["id": p.id]
                                if let v = p.videoUrl { item["videoUrl"] = v }
                                if let v = p.attributes?.fileName { item["fileName"] = v }
                                if let v = p.attributes?.mimeType { item["mimeType"] = v }
                                if let v = p.previewImageUrl { item["previewImageUrl"] = v }
                                if let dimensions = p.previewImageDimensions {
                                    item["width"] = dimensions.width
                                    item["height"] = dimensions.height
                                }
                                items.append(item)
                            }
                        }
                        if !items.isEmpty { setInfo["appPreviews"] = items }
                    }
                    previews.append(setInfo)
            }
            if let next = response.links?.next {
                previewResponse = try await httpClient.getPage(
                    next,
                    scope: PaginationScope(
                        path: previewPath,
                        requiredParameters: [
                            "include": previewInclude,
                            "limit": "200",
                            "limit[appPreviews]": "50"
                        ]
                    ),
                    as: ASCAppPreviewSetsResponse.self
                )
            } else {
                previewResponse = nil
            }
        }

        var screenshotResponse: ASCAppScreenshotSetsResponse? = try await httpClient.get(
            screenshotPath,
            parameters: ["include": screenshotInclude, "limit": "200", "limit[appScreenshots]": "50"],
            as: ASCAppScreenshotSetsResponse.self
        )

        while let response = screenshotResponse {
            for set in response.data {
                    var setData: [String: Any] = [
                        "id": set.id,
                        "screenshotDisplayType": set.attributes?.screenshotDisplayType ?? ""
                    ]
                    var screenshotIds: [String] = []
                    if let data = set.relationships?.appScreenshots?.data {
                        switch data {
                        case .multiple(let ids): screenshotIds = ids.map { $0.id }
                        case .single(let id): screenshotIds = [id.id]
                        }
                    }
                    var items: [[String: Any]] = []
                    if let included = response.included {
                        for sid in screenshotIds {
                            for s in included where s.id == sid {
                                var item: [String: Any] = ["id": s.id]
                                if let v = s.attributes?.fileName { item["fileName"] = v }
                                if let url = s.imageUrl { item["url"] = url }
                                if let dimensions = s.dimensions {
                                    item["width"] = dimensions.width
                                    item["height"] = dimensions.height
                                }
                                items.append(item)
                            }
                        }
                    }
                    setData["screenshots"] = items
                    screenshots.append(setData)
            }
            if let next = response.links?.next {
                screenshotResponse = try await httpClient.getPage(
                    next,
                    scope: PaginationScope(
                        path: screenshotPath,
                        requiredParameters: [
                            "include": screenshotInclude,
                            "limit": "200",
                            "limit[appScreenshots]": "50"
                        ]
                    ),
                    as: ASCAppScreenshotSetsResponse.self
                )
            } else {
                screenshotResponse = nil
            }
        }

        return (previews, screenshots)
    }
    
    /// Updates app version metadata for a specific localization
    /// - Returns: JSON with updated metadata confirmation and details
    /// - Throws: CallTool.Result with error if required parameters missing or update fails
    public func updateMetadata(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue,
              let versionIdValue = arguments["version_id"],
              let versionId = versionIdValue.stringValue,
              let localeValue = arguments["locale"],
              let locale = localeValue.stringValue else {
            return MCPResult.error("Required parameters 'app_id', 'version_id' and 'locale' are missing")
        }

        let validationErrors = validateAppStoreMetadataArguments(arguments, locale: locale)
        if !validationErrors.isEmpty {
            return ASCMetadataValidator.errorResult(validationErrors)
        }
        
        do {
            // 1. Fetch version details for result context. App Store Connect
            // enforces the exact editable-state rules on the PATCH request.
            let versionResponse: ASCAppStoreVersionResponse = try await httpClient.get(
                "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))",
                parameters: ["fields[appStoreVersions]": "app,platform,versionString,appVersionState,appStoreState"],
                as: ASCAppStoreVersionResponse.self
            )
            
            let version = versionResponse.data
            guard versionBelongsToApp(version, appId: appId) else {
                return MCPResult.error("Version '\(versionId)' does not belong to app '\(appId)'")
            }
            
            // 2. Get localization ID for the specified locale
            let localizationsResponse: ASCAppStoreVersionLocalizationsResponse = try await httpClient.get(
                "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))/appStoreVersionLocalizations",
                parameters: [
                    "filter[locale]": locale,
                    "fields[appStoreVersionLocalizations]": "locale,appStoreVersion"
                ],
                as: ASCAppStoreVersionLocalizationsResponse.self
            )
            
            guard let localization = localizationsResponse.data.first else {
                return MCPResult.error("Localization '\(locale)' not found for version \(version.version)")
            }
            guard localizationBelongsToVersion(localization, versionId: versionId) else {
                return MCPResult.error("Localization '\(localization.id)' does not belong to version '\(versionId)'")
            }
            
            // 3. Collect attributes for update (only provided fields)
            let attributes = ASCAppStoreVersionLocalizationUpdateRequest.Data.Attributes(
                description: try nullableMetadataString("description", from: arguments),
                whatsNew: try nullableMetadataString("whats_new", from: arguments),
                keywords: try nullableMetadataString("keywords", from: arguments),
                promotionalText: try nullableMetadataString("promotional_text", from: arguments),
                supportUrl: try nullableMetadataString("support_url", from: arguments),
                marketingUrl: try nullableMetadataString("marketing_url", from: arguments)
            )
            
            // Check that at least one field is provided
            let hasUpdates = attributes.description != nil ||
                           attributes.whatsNew != nil ||
                           attributes.keywords != nil ||
                           attributes.promotionalText != nil ||
                           attributes.supportUrl != nil ||
                           attributes.marketingUrl != nil
            
            guard hasUpdates else {
                return MCPResult.error("No fields specified for update")
            }
            
            // 4. Send PATCH request
            let updateRequest = ASCAppStoreVersionLocalizationUpdateRequest(
                id: localization.id,
                attributes: attributes
            )
            
            let _: ASCAppStoreVersionLocalizationUpdateResponse = try await httpClient.patch(
                "/v1/appStoreVersionLocalizations/\(try ASCPathSegment.encode(localization.id))",
                body: updateRequest,
                as: ASCAppStoreVersionLocalizationUpdateResponse.self
            )
            
            // 5. Format result
            var result = "**Metadata updated successfully**\n\n"
            result += "Version: \(version.version)\n"
            result += "Locale: \(locale)\n\n"
            result += "**Updated fields:**\n"

            if attributes.description != nil {
                result += "- Description\n"
            }
            if attributes.whatsNew != nil {
                result += "- What's New\n"
            }
            if attributes.keywords != nil {
                result += "- Keywords\n"
            }
            if attributes.promotionalText != nil {
                result += "- Promotional text\n"
            }
            if attributes.supportUrl != nil {
                result += "- Support URL\n"
            }
            if attributes.marketingUrl != nil {
                result += "- Marketing URL\n"
            }
            
            return MCPResult.json(
                .object([
                    "success": .bool(true),
                    "versionId": .string(versionId),
                    "version": .string(version.version),
                    "locale": .string(locale),
                    "localizationId": .string(localization.id),
                    "updatedFields": .array(updatedMetadataFieldNames(attributes).map(Value.string))
                ]),
                text: result
            )
            
        } catch {
            return MCPResult.error("Failed to update metadata: \(error.localizedDescription)")
        }
    }
    
    /// Creates a new localization for an app store version
    /// - Returns: JSON with created localization data
    /// - Throws: CallTool.Result with error if required parameters missing or API call fails
    public func createLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionIdValue = arguments["version_id"],
              let versionId = versionIdValue.stringValue,
              let localeValue = arguments["locale"],
              let locale = localeValue.stringValue else {
            return MCPResult.error("Required parameters 'version_id' and 'locale' are missing")
        }

        let validationErrors = validateAppStoreMetadataArguments(arguments, locale: locale)
        if !validationErrors.isEmpty {
            return ASCMetadataValidator.errorResult(validationErrors)
        }

        do {
            let attributes = CreateAppStoreVersionLocalizationRequest.Data.Attributes(
                locale: locale,
                description: arguments["description"]?.stringValue,
                whatsNew: arguments["whats_new"]?.stringValue,
                keywords: arguments["keywords"]?.stringValue,
                promotionalText: arguments["promotional_text"]?.stringValue,
                supportUrl: arguments["support_url"]?.stringValue,
                marketingUrl: arguments["marketing_url"]?.stringValue
            )

            let request = CreateAppStoreVersionLocalizationRequest(
                versionId: versionId,
                attributes: attributes
            )

            let response: ASCAppStoreVersionLocalizationResponse = try await httpClient.post(
                "/v1/appStoreVersionLocalizations",
                body: request,
                as: ASCAppStoreVersionLocalizationResponse.self
            )

            let loc = response.data
            var locData: [String: Any] = [
                "id": loc.id,
                "locale": loc.locale
            ]
            if let v = loc.attributes?.description { locData["description"] = v }
            if let v = loc.attributes?.whatsNew { locData["whatsNew"] = v }
            if let v = loc.attributes?.keywords { locData["keywords"] = v }
            if let v = loc.attributes?.promotionalText { locData["promotionalText"] = v }
            if let v = loc.attributes?.supportUrl { locData["supportUrl"] = v }
            if let v = loc.attributes?.marketingUrl { locData["marketingUrl"] = v }

            let result: [String: Any] = [
                "success": true,
                "localization": locData
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a localization from an app store version
    /// - Returns: JSON confirmation of deletion
    /// - Throws: CallTool.Result with error if localization_id missing or API call fails
    public func deleteLocalization(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let localizationIdValue = arguments["localization_id"],
              let localizationId = localizationIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appStoreVersionLocalizations/\(try ASCPathSegment.encode(localizationId))")

            let result: [String: Any] = [
                "success": true,
                "message": "Localization '\(localizationId)' deleted"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to delete localization: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Formats relationship data from API response into structured JSON
    /// - Returns: Dictionary with formatted relationship information
    /// - Throws: None - internal helper method
    private func formatRelationship(_ relationship: ASCApp.Relationship) -> [String: Any] {
        var result: [String: Any] = [:]
        
        if let links = relationship.links {
            var linksDict: [String: Any] = [:]
            if let related = links.related {
                linksDict["related"] = related
            }
            if let selfLink = links.`self` {
                linksDict["self"] = selfLink
            }
            if !linksDict.isEmpty {
                result["links"] = linksDict
            }
        }
        
        if let data = relationship.data {
            switch data {
            case .single(let value):
                result["data"] = ["id": value.id, "type": value.type]
            case .multiple(let values):
                result["data"] = values.map { ["id": $0.id, "type": $0.type] }
            case .null:
                result["data"] = NSNull()
            }
        }
        
        if let meta = relationship.meta {
            if let paging = meta.paging {
                var pagingDict: [String: Any] = [:]
                if let total = paging.total {
                    pagingDict["total"] = total
                }
                if let limit = paging.limit {
                    pagingDict["limit"] = limit
                }
                if !pagingDict.isEmpty {
                    result["meta"] = ["paging": pagingDict]
                }
            }
        }
        
        return result
    }
    
    /// Lists all available localizations for a specific app version
    /// - Returns: JSON with list of all localizations with their metadata
    /// - Throws: CallTool.Result with error if parameters are invalid or API call fails
    public func listLocalizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue,
              let versionIdValue = arguments["version_id"],
              let versionId = versionIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters 'app_id' and 'version_id' are missing\n\nUse apps_list_versions to get version ID")],
                isError: true
            )
        }

        do {
            let localizationFields = "locale,description,whatsNew,keywords,promotionalText,supportUrl,marketingUrl,appStoreVersion"
            let versionResponse: ASCAppStoreVersionResponse = try await httpClient.get(
                "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))",
                parameters: ["fields[appStoreVersions]": "app"],
                as: ASCAppStoreVersionResponse.self
            )
            guard versionBelongsToApp(versionResponse.data, appId: appId) else {
                return MCPResult.error("Version '\(versionId)' does not belong to app '\(appId)'")
            }

            let localizationsResponse: ASCAppStoreVersionLocalizationsResponse

            // Check for pagination next_url
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                localizationsResponse = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(
                        path: "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))/appStoreVersionLocalizations",
                        requiredParameters: ["fields[appStoreVersionLocalizations]": localizationFields]
                    ),
                    as: ASCAppStoreVersionLocalizationsResponse.self
                )
            } else {
                localizationsResponse = try await httpClient.get(
                    "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))/appStoreVersionLocalizations",
                    parameters: ["fields[appStoreVersionLocalizations]": localizationFields],
                    as: ASCAppStoreVersionLocalizationsResponse.self
                )
            }

            guard localizationsResponse.data.allSatisfy({ localizationBelongsToVersion($0, versionId: versionId) }) else {
                return MCPResult.error("Apple returned a localization outside version '\(versionId)' context")
            }

            // Format result
            var localizations: [[String: Any]] = []

            for localization in localizationsResponse.data {
                var localizationData: [String: Any] = [
                    "id": localization.id,
                    "locale": localization.locale
                ]

                if let description = localization.attributes?.description {
                    localizationData["hasDescription"] = !description.isEmpty
                }
                if let whatsNew = localization.attributes?.whatsNew {
                    localizationData["hasWhatsNew"] = !whatsNew.isEmpty
                }
                if let keywords = localization.attributes?.keywords {
                    localizationData["hasKeywords"] = !keywords.isEmpty
                }
                if let promotionalText = localization.attributes?.promotionalText {
                    localizationData["hasPromotionalText"] = !promotionalText.isEmpty
                }
                if let supportUrl = localization.attributes?.supportUrl {
                    localizationData["supportUrl"] = supportUrl
                }
                if let marketingUrl = localization.attributes?.marketingUrl {
                    localizationData["marketingUrl"] = marketingUrl
                }

                localizations.append(localizationData)
            }

            // Sort by locale for convenience
            localizations.sort { ($0["locale"] as? String ?? "") < ($1["locale"] as? String ?? "") }

            var result: [String: Any] = [
                "success": true,
                "appId": appId,
                "versionId": versionId,
                "totalLocalizations": localizations.count,
                "localizations": localizations
            ]

            if let nextUrl = localizationsResponse.links?.next {
                result["next_url"] = nextUrl
            }

            return MCPResult.jsonObject(result)

        } catch {
            let result: [String: Any] = [
                "success": false,
                "error": error.localizedDescription
            ]
            return MCPResult.jsonObject(result, isError: true)
        }
    }
}

private struct AppsMetadataArgumentError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
