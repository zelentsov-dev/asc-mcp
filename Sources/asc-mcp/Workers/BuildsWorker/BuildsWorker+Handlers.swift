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
                content: [.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBuildsResponse

            // Check for pagination next_url
            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCBuildsResponse.self)
            } else {
                var queryParams: [String: String] = [
                    "filter[app]": appId,
                    "include": "app,buildBetaDetail,preReleaseVersion"
                ]

                if let versionValue = arguments["version"],
                   let version = versionValue.stringValue {
                    queryParams["filter[version]"] = version
                }
                if let stateValue = arguments["processing_state"],
                   let state = stateValue.stringValue {
                    queryParams["filter[processingState]"] = state
                }
                if let expiredValue = arguments["expired"],
                   let expired = expiredValue.boolValue {
                    queryParams["filter[expired]"] = expired ? "true" : "false"
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list builds: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'build_id' is missing")],
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
            
            let queryParams: [String: String] = [
                "include": includes.joined(separator: ",")
            ]
            
            let response: ASCBuildResponse = try await httpClient.get(
                "/v1/builds/\(buildId)",
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
            
            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
            
        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get build: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameters 'app_id' and 'build_number' are missing")],
                isError: true
            )
        }
        
        do {
            let queryParams: [String: String] = [
                "filter[app]": appId,
                "filter[version]": buildNumber,
                "include": "app,buildBetaDetail,preReleaseVersion",
                "limit": "1"
            ]
            
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
                return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
            }
            
            let build = formatBuild(response.data[0])
            
            let result = [
                "success": true,
                "build": build
            ] as [String: Any]
            
            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
            
        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to find build: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            // Direct endpoint: returns single build attached to the version
            let queryParams: [String: String] = [
                "fields[builds]": "version,uploadedDate,processingState,expired,minOsVersion"
            ]

            let data = try await httpClient.get(
                "/v1/appStoreVersions/\(versionId)/build",
                parameters: queryParams
            )

            // Parse as single build response (not array)
            let buildResponse = try JSONDecoder().decode(ASCBuildResponse.self, from: data)
            let build = formatBuild(buildResponse.data)

            let result = [
                "success": true,
                "build": build
            ] as [String: Any]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get build for version: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
}