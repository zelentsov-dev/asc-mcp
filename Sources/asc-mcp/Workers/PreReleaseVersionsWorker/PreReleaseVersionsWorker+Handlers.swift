import Foundation
import MCP

// MARK: - Tool Handlers
extension PreReleaseVersionsWorker {

    /// Lists pre-release versions with optional filtering
    /// - Returns: JSON array of pre-release versions with version and platform attributes
    func listPreReleaseVersions(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments

        do {
            let response: ASCPreReleaseVersionsResponse
            var queryParams: [String: String] = [:]

            if let appId = arguments?["app_id"]?.stringValue {
                queryParams["filter[app]"] = appId
            }
            if let platform = arguments?["platform"]?.stringValue {
                queryParams["filter[platform]"] = platform
            }
            if let version = arguments?["version"]?.stringValue {
                queryParams["filter[version]"] = version
            }
            if let sort = arguments?["sort"]?.stringValue {
                queryParams["sort"] = sort
            }
            if let limit = arguments?["limit"]?.intValue {
                queryParams["limit"] = String(min(max(limit, 1), 200))
            } else {
                queryParams["limit"] = "25"
            }

            if let nextUrl = try paginationURL(from: arguments?["next_url"]) {
                var requiredParameters = queryParams
                requiredParameters.removeValue(forKey: "limit")
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(
                        path: "/v1/preReleaseVersions",
                        requiredParameters: requiredParameters
                    ),
                    as: ASCPreReleaseVersionsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v1/preReleaseVersions",
                    parameters: queryParams,
                    as: ASCPreReleaseVersionsResponse.self
                )
            }

            let versions = response.data.map { formatPreReleaseVersion($0) }

            var result: [String: Any] = [
                "success": true,
                "pre_release_versions": versions,
                "count": versions.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list pre-release versions: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets a single pre-release version by ID
    /// - Returns: JSON with pre-release version details
    func getPreReleaseVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let preReleaseVersionId = arguments["pre_release_version_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'pre_release_version_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCPreReleaseVersionResponse = try await httpClient.get(
                "/v1/preReleaseVersions/\(try ASCPathSegment.encode(preReleaseVersionId))",
                parameters: [:],
                as: ASCPreReleaseVersionResponse.self
            )

            let version = formatPreReleaseVersion(response.data)

            let result = [
                "success": true,
                "pre_release_version": version
            ] as [String: Any]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get pre-release version: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists builds for a specific pre-release version
    /// - Returns: JSON array of builds associated with the pre-release version
    func listPreReleaseVersionBuilds(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let preReleaseVersionId = arguments["pre_release_version_id"]?.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'pre_release_version_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCBuildsResponse

            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(path: "/v1/preReleaseVersions/\(try ASCPathSegment.encode(preReleaseVersionId))/builds"),
                    as: ASCBuildsResponse.self
                )
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/preReleaseVersions/\(try ASCPathSegment.encode(preReleaseVersionId))/builds",
                    parameters: queryParams,
                    as: ASCBuildsResponse.self
                )
            }

            let builds = response.data.map { formatBuild($0) }

            var result: [String: Any] = [
                "success": true,
                "builds": builds,
                "count": builds.count
            ]
            if let next = response.links?.next {
                result["next_url"] = next
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list builds for pre-release version: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    private func formatPreReleaseVersion(_ version: ASCPreReleaseVersionResource) -> [String: Any] {
        return [
            "id": version.id,
            "type": version.type,
            "version": (version.attributes?.version).jsonSafe,
            "platform": (version.attributes?.platform).jsonSafe
        ]
    }

    private func formatBuild(_ build: ASCBuild) -> [String: Any] {
        return [
            "id": build.id,
            "type": build.type,
            "version": build.attributes.version.jsonSafe,
            "uploadedDate": build.attributes.uploadedDate.jsonSafe,
            "processingState": build.attributes.processingState.jsonSafe,
            "buildNumber": build.attributes.version.jsonSafe
        ]
    }
}
