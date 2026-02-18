import Foundation
import MCP

// MARK: - Tool Handlers
extension AppsWorker {
    
    /// Lists all apps from App Store Connect with optional filtering
    /// - Returns: JSON array of apps with their IDs, names, bundle IDs, and metadata
    /// - Throws: CallTool.Result with error if API call fails
    public func listApps(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        do {
            let response: ASCAppsResponse

            // Check for pagination next_url
            if let nextUrl = params.arguments?["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCAppsResponse.self)
            } else {
                // Extract parameters
                var queryParams: [String: String] = [:]

                if let arguments = params.arguments {
                    if let limitValue = arguments["limit"],
                       let limit = limitValue.intValue {
                        queryParams["limit"] = String(limit)
                    }
                    if let sortValue = arguments["sort"],
                       let sort = sortValue.stringValue {
                        queryParams["sort"] = sort
                    }
                    if let bundleIdValue = arguments["bundle_id"],
                       let bundleId = bundleIdValue.stringValue {
                        queryParams["filter[bundleId]"] = bundleId
                    }
                    if let nameValue = arguments["name"],
                       let name = nameValue.stringValue {
                        queryParams["filter[name]"] = name
                    }
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
                        "availableInNewTerritories": app.attributes?.availableInNewTerritories.jsonSafe,
                        "contentRightsDeclaration": app.attributes?.contentRightsDeclaration.jsonSafe,
                        "isOrEverWasMadeForKids": app.attributes?.isOrEverWasMadeForKids.jsonSafe
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list apps: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'app_id' is missing")],
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
            let response: ASCAppResponse = try await httpClient.get("/v1/apps/\(appId)", parameters: queryParams, as: ASCAppResponse.self)
            let app = response.data
            
            // Format detailed response
            var relationships: [String: Any] = [:]
            
            // Safely process relationships
            if let appRelationships = app.relationships {
                if let appInfos = appRelationships.appInfos {
                    relationships["appInfos"] = formatRelationship(appInfos)
                }
                if let appStoreVersions = appRelationships.appStoreVersions {
                    relationships["appStoreVersions"] = formatRelationship(appStoreVersions)
                }
                if let availableTerritories = appRelationships.availableTerritories {
                    relationships["availableTerritories"] = formatRelationship(availableTerritories)
                }
                if let betaLicenseAgreement = appRelationships.betaLicenseAgreement {
                    relationships["betaLicenseAgreement"] = formatRelationship(betaLicenseAgreement)
                }
                if let builds = appRelationships.builds {
                    relationships["builds"] = formatRelationship(builds)
                }
                if let preReleaseVersions = appRelationships.preReleaseVersions {
                    relationships["preReleaseVersions"] = formatRelationship(preReleaseVersions)
                }
            }
            
            let result: [String: Any] = [
                "success": true,
                "app": [
                    "id": app.id,
                    "type": app.type,
                    "name": app.displayName,
                    "bundleId": app.bundleIdentifier,
                    "sku": app.appSKU,
                    "primaryLocale": app.locale,
                    "attributes": [
                        "availableInNewTerritories": app.attributes?.availableInNewTerritories.jsonSafe,
                        "contentRightsDeclaration": app.attributes?.contentRightsDeclaration.jsonSafe,
                        "isOrEverWasMadeForKids": app.attributes?.isOrEverWasMadeForKids.jsonSafe,
                        "subscriptionStatusUrl": app.attributes?.subscriptionStatusUrl.jsonSafe,
                        "subscriptionStatusUrlVersion": app.attributes?.subscriptionStatusUrlVersion.jsonSafe,
                        "subscriptionStatusUrlForSandbox": app.attributes?.subscriptionStatusUrlForSandbox.jsonSafe,
                        "subscriptionStatusUrlVersionForSandbox": app.attributes?.subscriptionStatusUrlVersionForSandbox.jsonSafe
                    ],
                    "relationships": relationships
                ]
            ]
            
            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
            
        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get app details: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'query' is missing")],
                isError: true
            )
        }
        
        do {
            // Search by name and Bundle ID
            let nameResults: ASCAppsResponse = try await httpClient.get("/v1/apps", 
                parameters: ["filter[name]": query], as: ASCAppsResponse.self)
            
            let bundleIdResults: ASCAppsResponse = try await httpClient.get("/v1/apps", 
                parameters: ["filter[bundleId]": query], as: ASCAppsResponse.self)
            
            // Merge results and remove duplicates
            let allApps = Array(Set(nameResults.data + bundleIdResults.data))
            
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
                "searchedIn": ["name", "bundleId"]
            ]
            
            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
            
        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to search apps: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAppStoreVersionsResponse

            // Check for pagination next_url
            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCAppStoreVersionsResponse.self)
            } else {
                response = try await httpClient.get(
                    "/v1/apps/\(appId)/appStoreVersions",
                    parameters: [
                        "limit": "200",
                        "fields[appStoreVersions]": "versionString,appStoreState,createdDate"
                    ],
                    as: ASCAppStoreVersionsResponse.self
                )
            }

            let versions = response.data.map { version in
                return [
                    "id": version.id,
                    "versionString": version.attributes?.versionString ?? "N/A",
                    "appStoreState": version.attributes?.appStoreState ?? "UNKNOWN",
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list versions: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        // Optional parameters
        let locale = arguments["locale"]?.stringValue
        let versionIdParam = arguments["version_id"]?.stringValue
        let versionStateFilter = arguments["version_state"]?.stringValue
        let includeMedia = arguments["include_media"]?.boolValue ?? false

        do {
            // Step 1: Resolve version
            let resolvedVersion: (id: String, versionString: String, state: String)

            if let versionId = versionIdParam {
                // Use provided version_id — fetch its details
                let versionResponse: ASCAppStoreVersionResponse = try await httpClient.get(
                    "/v1/appStoreVersions/\(versionId)",
                    parameters: ["fields[appStoreVersions]": "versionString,appStoreState"],
                    as: ASCAppStoreVersionResponse.self
                )
                let v = versionResponse.data
                resolvedVersion = (id: v.id, versionString: v.version, state: v.state)
            } else {
                // Auto-resolve version
                let versionsResponse: ASCAppStoreVersionsResponse = try await httpClient.get(
                    "/v1/apps/\(appId)/appStoreVersions",
                    parameters: [
                        "fields[appStoreVersions]": "versionString,appStoreState,createdDate",
                        "limit": "10"
                    ],
                    as: ASCAppStoreVersionsResponse.self
                )

                guard !versionsResponse.data.isEmpty else {
                    return CallTool.Result(
                        content: [.text(JSONFormatter.formatJSON([
                            "success": false,
                            "error": "App \(appId) has no versions"
                        ] as [String: Any]))],
                        isError: true
                    )
                }

                let versions = versionsResponse.data
                let selected: ASCAppStoreVersion

                if let stateFilter = versionStateFilter {
                    // Filter by requested state
                    guard let match = versions.first(where: { $0.attributes?.appStoreState == stateFilter }) else {
                        let available = versions.compactMap { $0.attributes?.appStoreState }.joined(separator: ", ")
                        return CallTool.Result(
                            content: [.text(JSONFormatter.formatJSON([
                                "success": false,
                                "error": "Version with state '\(stateFilter)' not found. Available: \(available)"
                            ] as [String: Any]))],
                            isError: true
                        )
                    }
                    selected = match
                } else {
                    // Priority: PREPARE_FOR_SUBMISSION > READY_FOR_SALE > first available
                    // Within each state, prefer platform: IOS > MAC_OS > TV_OS > VISION_OS
                    let platformPriority = ["IOS", "MAC_OS", "TV_OS", "WATCH_OS", "VISION_OS"]

                    func preferredByPlatform(_ candidates: [ASCAppStoreVersion]) -> ASCAppStoreVersion? {
                        for platform in platformPriority {
                            if let match = candidates.first(where: { $0.attributes?.platform == platform }) {
                                return match
                            }
                        }
                        return candidates.first
                    }

                    let editableCandidates = versions.filter { $0.attributes?.appStoreState == "PREPARE_FOR_SUBMISSION" }
                    let publishedCandidates = versions.filter { $0.attributes?.appStoreState == "READY_FOR_SALE" }

                    if let editable = preferredByPlatform(editableCandidates) {
                        selected = editable
                    } else if let published = preferredByPlatform(publishedCandidates) {
                        selected = published
                    } else {
                        selected = versions[0]
                    }
                }

                resolvedVersion = (
                    id: selected.id,
                    versionString: selected.attributes?.versionString ?? "N/A",
                    state: selected.attributes?.appStoreState ?? "UNKNOWN"
                )
            }

            // Step 2: Fetch localizations
            var localizationParams: [String: String] = [
                "fields[appStoreVersionLocalizations]": "description,locale,keywords,marketingUrl,promotionalText,supportUrl,whatsNew",
                "limit": "200"
            ]
            if let locale = locale {
                localizationParams["filter[locale]"] = locale
            }

            let localizationsResponse: ASCAppStoreVersionLocalizationsResponse = try await httpClient.get(
                "/v1/appStoreVersions/\(resolvedVersion.id)/appStoreVersionLocalizations",
                parameters: localizationParams,
                as: ASCAppStoreVersionLocalizationsResponse.self
            )

            // Check if locale filter returned empty results
            if let locale = locale, localizationsResponse.data.isEmpty {
                return CallTool.Result(
                    content: [.text(JSONFormatter.formatJSON([
                        "success": false,
                        "error": "Localization '\(locale)' not found for version \(resolvedVersion.versionString)"
                    ] as [String: Any]))],
                    isError: true
                )
            }

            let versionInfo: [String: Any] = [
                "id": resolvedVersion.id,
                "versionString": resolvedVersion.versionString,
                "appStoreState": resolvedVersion.state
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
                    let mediaResult = await fetchMedia(for: loc.id)
                    if let previews = mediaResult.previews { result["appPreviewSets"] = previews }
                    if let screenshots = mediaResult.screenshots { result["screenshotSets"] = screenshots }
                }
            } else {
                // All locales mode
                let formatted = localizationsResponse.data
                    .sorted { $0.locale < $1.locale }
                    .map { formatLocalization($0) }
                result["totalLocalizations"] = formatted.count
                result["localizations"] = formatted
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get metadata: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Fetches media (preview videos and screenshots) for a localization
    /// - Returns: Tuple with optional preview sets and screenshot sets arrays
    private func fetchMedia(for localizationId: String) async -> (previews: [[String: Any]]?, screenshots: [[String: Any]]?) {
        var previews: [[String: Any]]?
        var screenshots: [[String: Any]]?

        // Fetch preview videos
        if let previewSetsData = try? await httpClient.get(
            "/v1/appStoreVersionLocalizations/\(localizationId)/appPreviewSets",
            parameters: ["include": "appPreviews", "limit": "10"]
        ) {
            if let response = try? JSONDecoder().decode(ASCAppPreviewSetsResponse.self, from: previewSetsData),
               !response.data.isEmpty {
                var sets: [[String: Any]] = []
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
                                items.append(item)
                            }
                        }
                        if !items.isEmpty { setInfo["appPreviews"] = items }
                    }
                    sets.append(setInfo)
                }
                if !sets.isEmpty { previews = sets }
            }
        }

        // Fetch screenshots
        if let screenshotSetsData = try? await httpClient.get(
            "/v1/appStoreVersionLocalizations/\(localizationId)/appScreenshotSets",
            parameters: ["include": "appScreenshots", "limit": "10"]
        ) {
            if let response = try? JSONDecoder().decode(ASCAppScreenshotSetsResponse.self, from: screenshotSetsData),
               !response.data.isEmpty {
                var sets: [[String: Any]] = []
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
                                if let imageAsset = s.attributes?.imageAsset,
                                   let url = imageAsset.templateUrl {
                                    item["url"] = url
                                        .replacingOccurrences(of: "{w}", with: "1290")
                                        .replacingOccurrences(of: "{h}", with: "2796")
                                        .replacingOccurrences(of: "{f}", with: "png")
                                }
                                items.append(item)
                            }
                        }
                    }
                    setData["screenshots"] = items
                    sets.append(setData)
                }
                if !sets.isEmpty { screenshots = sets }
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
              let _ = appIdValue.stringValue, // validate presence, app_id is only needed for validation
              let versionIdValue = arguments["version_id"],
              let versionId = versionIdValue.stringValue,
              let localeValue = arguments["locale"],
              let locale = localeValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameters 'app_id', 'version_id' and 'locale' are missing")],
                isError: true
            )
        }
        
        do {
            // 1. First check that version is in editable state
            let versionResponse: ASCAppStoreVersionResponse = try await httpClient.get(
                "/v1/appStoreVersions/\(versionId)",
                as: ASCAppStoreVersionResponse.self
            )
            
            let version = versionResponse.data
            guard version.attributes?.appStoreState == "PREPARE_FOR_SUBMISSION" else {
                return CallTool.Result(
                    content: [.text("Error: Version must be in PREPARE_FOR_SUBMISSION state for editing.\nCurrent state: \(version.attributes?.appStoreState ?? "Unknown")")],
                    isError: true
                )
            }
            
            // 2. Get localization ID for the specified locale
            let localizationsResponse: ASCAppStoreVersionLocalizationsResponse = try await httpClient.get(
                "/v1/appStoreVersions/\(versionId)/appStoreVersionLocalizations",
                parameters: ["filter[locale]": locale],
                as: ASCAppStoreVersionLocalizationsResponse.self
            )
            
            guard let localization = localizationsResponse.data.first else {
                return CallTool.Result(
                    content: [.text("Error: Localization '\(locale)' not found for version \(version.version)")],
                    isError: true
                )
            }
            
            // 3. Collect attributes for update (only provided fields)
            let attributes = ASCAppStoreVersionLocalizationUpdateRequest.Data.Attributes(
                description: arguments["description"]?.stringValue,
                whatsNew: arguments["whats_new"]?.stringValue,
                keywords: arguments["keywords"]?.stringValue,
                promotionalText: arguments["promotional_text"]?.stringValue,
                supportUrl: arguments["support_url"]?.stringValue,
                marketingUrl: arguments["marketing_url"]?.stringValue
            )
            
            // Check that at least one field is provided
            let hasUpdates = attributes.description != nil ||
                           attributes.whatsNew != nil ||
                           attributes.keywords != nil ||
                           attributes.promotionalText != nil ||
                           attributes.supportUrl != nil ||
                           attributes.marketingUrl != nil
            
            guard hasUpdates else {
                return CallTool.Result(
                    content: [.text("Warning: No fields specified for update")],
                    isError: true
                )
            }
            
            // 4. Send PATCH request
            let updateRequest = ASCAppStoreVersionLocalizationUpdateRequest(
                id: localization.id,
                attributes: attributes
            )
            
            let _: ASCAppStoreVersionLocalizationUpdateResponse = try await httpClient.patch(
                "/v1/appStoreVersionLocalizations/\(localization.id)",
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
            
            return CallTool.Result(content: [.text(result)])
            
        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to update metadata: \(error.localizedDescription)")],
                isError: true
            )
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
            return CallTool.Result(
                content: [.text("Error: Required parameters 'version_id' and 'locale' are missing")],
                isError: true
            )
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create localization: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'localization_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/appStoreVersionLocalizations/\(localizationId)")

            let result: [String: Any] = [
                "success": true,
                "message": "Localization '\(localizationId)' deleted"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete localization: \(error.localizedDescription)")],
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
            result["data"] = data.map { ["id": $0.id, "type": $0.type] }
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
                content: [.text("Error: Required parameters 'app_id' and 'version_id' are missing\n\nUse apps_list_versions to get version ID")],
                isError: true
            )
        }

        do {
            let localizationsResponse: ASCAppStoreVersionLocalizationsResponse

            // Check for pagination next_url
            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                localizationsResponse = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCAppStoreVersionLocalizationsResponse.self)
            } else {
                localizationsResponse = try await httpClient.get(
                    "/v1/appStoreVersions/\(versionId)/appStoreVersionLocalizations",
                    parameters: [:],
                    as: ASCAppStoreVersionLocalizationsResponse.self
                )
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            let result: [String: Any] = [
                "success": false,
                "error": error.localizedDescription
            ]
            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))], isError: true)
        }
    }
}