import Foundation
import MCP

// MARK: - Tool Handlers
extension BuildsWorker {
    
    /// Lists builds for an app with various filtering options
    /// - Returns: JSON array of builds with processing states, versions, and upload dates
    /// - Throws: CallTool.Result with error if app_id missing or API call fails
    func listBuilds(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBuildsResponse
            var queryParams: [String: String] = [
                "filter[app]": appId,
                "include": "app,buildBetaDetail,preReleaseVersion,buildUpload"
            ]

            if let version = commaSeparatedStringList(arguments["version"]) {
                queryParams["filter[version]"] = version
            }
            if let state = commaSeparatedStringList(arguments["processing_state"]) {
                queryParams["filter[processingState]"] = state
            }
            if let expiredValue = arguments["expired"],
               let expired = expiredValue.boolValue {
                queryParams["filter[expired]"] = expired ? "true" : "false"
            }
            applyStringList(arguments["app_store_version_ids"], as: "filter[appStoreVersion]", to: &queryParams)
            applyStringList(arguments["beta_review_states"], as: "filter[betaAppReviewSubmission.betaReviewState]", to: &queryParams)
            applyStringList(arguments["beta_group_ids"], as: "filter[betaGroups]", to: &queryParams)
            applyStringList(arguments["build_audience_types"], as: "filter[buildAudienceType]", to: &queryParams)
            applyStringList(arguments["build_ids"], as: "filter[id]", to: &queryParams)
            applyStringList(arguments["pre_release_platforms"], as: "filter[preReleaseVersion.platform]", to: &queryParams)
            applyStringList(arguments["pre_release_versions"], as: "filter[preReleaseVersion.version]", to: &queryParams)
            applyStringList(arguments["pre_release_version_ids"], as: "filter[preReleaseVersion]", to: &queryParams)
            if let usesNonExemptEncryption = arguments["uses_non_exempt_encryption"]?.boolValue {
                queryParams["filter[usesNonExemptEncryption]"] = usesNonExemptEncryption ? "true" : "false"
            }
            if let declarationExists = arguments["uses_non_exempt_encryption_set"]?.boolValue {
                queryParams["exists[usesNonExemptEncryption]"] = declarationExists ? "true" : "false"
            }
            if let limitValue = arguments["limit"],
               let limit = limitValue.intValue {
                queryParams["limit"] = String(min(max(limit, 1), 200))
            } else {
                queryParams["limit"] = "25"
            }
            if let sortValue = arguments["sort"],
               let sort = sortValue.stringValue {
                queryParams["sort"] = sort
            } else {
                queryParams["sort"] = "-uploadedDate"
            }

            // Check for pagination next_url
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope.strict(
                        path: "/v1/builds",
                        query: queryParams
                    ),
                    as: ASCBuildsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v1/builds",
                    parameters: queryParams,
                    as: ASCBuildsResponse.self
                )
            }

            let builds = response.data.map { formatBuild($0) }

            var result = [
                "success": true,
                "builds": builds,
                "count": builds.count
            ] as [String: Any]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }
            if let total = response.meta?.paging?.total {
                result["total"] = total
            }
            if let included = response.included, !included.isEmpty {
                result["included"] = included.map { formatIncludedResource($0) }
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list builds: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    /// Gets detailed information about a specific build
    /// - Returns: JSON with complete build data including beta details and processing state
    /// - Throws: CallTool.Result with error if build_id missing or API call fails
    func getBuild(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let buildIdValue = arguments["build_id"],
              let buildId = buildIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'build_id' is missing")],
                isError: true
            )
        }
        
        do {
            let includeBetaDetail = arguments["include_beta_detail"]?.boolValue ?? true
            let includeApp = arguments["include_app"]?.boolValue ?? false
            
            var includes = [String]()
            if includeBetaDetail {
                includes.append("buildBetaDetail")
            }
            if includeApp {
                includes.append("app")
            }
            includes.append("preReleaseVersion")
            includes.append("buildBundles")
            includes.append("buildUpload")
            
            let queryParams: [String: String] = [
                "include": includes.joined(separator: ",")
            ]
            
            let response: ASCBuildResponse = try await httpClient.get(
                "/v1/builds/\(try ASCPathSegment.encode(buildId))",
                parameters: queryParams,
                as: ASCBuildResponse.self
            )
            
            let build = formatBuild(response.data)
            
            // Parse included resources
            var includedData: [String: Any] = [:]
            if let included = response.included {
                var buildBundles: [[String: Any]] = []
                
                for item in included {
                    switch item {
                    case .buildBetaDetail(_):
                        includedData["betaDetail"] = formatIncludedResource(item)
                    case .buildUpload(_):
                        includedData["buildUpload"] = formatIncludedResource(item)
                    case .app(_):
                        includedData["app"] = formatIncludedResource(item)
                    case .preReleaseVersion(_):
                        includedData["preReleaseVersion"] = formatIncludedResource(item)
                    case .buildBundle(_):
                        buildBundles.append(formatIncludedResource(item))
                    default:
                        break
                    }
                }
                
                if !buildBundles.isEmpty {
                    includedData["buildBundles"] = buildBundles
                }
            }
            
            let result = [
                "success": true,
                "build": build,
                "included": includedData
            ] as [String: Any]
            
            return MCPResult.jsonObject(result)
            
        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get build: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    /// Finds a specific build by its version number
    /// - Returns: JSON with build details if found, or error if not found
    /// - Throws: CallTool.Result with error if required parameters missing or build not found
    func findBuildByNumber(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue,
              let buildNumberValue = arguments["build_number"],
              let buildNumber = buildNumberValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters 'app_id' and 'build_number' are missing")],
                isError: true
            )
        }
        
        do {
            var queryParams: [String: String] = [
                "filter[app]": appId,
                "filter[version]": buildNumber,
                "include": "app,buildBetaDetail,preReleaseVersion,buildUpload",
                "limit": "1",
                "sort": arguments["sort"]?.stringValue ?? "-uploadedDate"
            ]
            applyStringList(arguments["pre_release_platforms"], as: "filter[preReleaseVersion.platform]", to: &queryParams)
            applyStringList(arguments["pre_release_versions"], as: "filter[preReleaseVersion.version]", to: &queryParams)
            applyStringList(arguments["pre_release_version_ids"], as: "filter[preReleaseVersion]", to: &queryParams)
            
            let response: ASCBuildsResponse = try await httpClient.get(
                "/v1/builds",
                parameters: queryParams,
                as: ASCBuildsResponse.self
            )
            
            guard !response.data.isEmpty else {
                let result = [
                    "success": false,
                    "message": "Build with number '\(buildNumber)' not found for app '\(appId)'"
                ] as [String: Any]
                return MCPResult.jsonObject(result)
            }
            
            let build = formatBuild(response.data[0])
            
            var result = [
                "success": true,
                "build": build
            ] as [String: Any]
            if let included = response.included, !included.isEmpty {
                result["included"] = included.map { formatIncludedResource($0) }
            }
            
            return MCPResult.jsonObject(result)
            
        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to find build: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
    
    /// Gets the build associated with a specific app store version
    /// - Returns: JSON with the single build linked to the version
    /// - Throws: CallTool.Result with error if version_id missing or API call fails
    func listBuildsForVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionIdValue = arguments["version_id"],
              let versionId = versionIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            // Direct endpoint: returns single build attached to the version
            let queryParams: [String: String] = [
                "fields[builds]": "version,uploadedDate,processingState,expired,minOsVersion"
            ]

            let data = try await httpClient.get(
                "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))/build",
                parameters: queryParams
            )

            // Parse as single build response (not array)
            let buildResponse = try JSONDecoder().decode(ASCBuildResponse.self, from: data)
            let build = formatBuild(buildResponse.data)

            let result = [
                "success": true,
                "build": build
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get build for version: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    private func applyStringList(_ value: Value?, as appleName: String, to query: inout [String: String]) {
        if let encoded = commaSeparatedStringList(value) {
            query[appleName] = encoded
        }
    }

    private func commaSeparatedStringList(_ value: Value?) -> String? {
        if let string = value?.stringValue, !string.isEmpty {
            return string
        }
        guard let values = value?.arrayValue,
              !values.isEmpty else {
            return nil
        }
        let strings = values.compactMap(\.stringValue).filter { !$0.isEmpty }
        guard strings.count == values.count else {
            return nil
        }
        return strings.joined(separator: ",")
    }
}
