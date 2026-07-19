import Foundation
import MCP

extension BetaFeedbackWorker {
    /// Lists TestFlight beta feedback crash submissions for an app.
    /// - Parameter params: Tool parameters containing `app_id` and optional filters.
    /// - Returns: JSON object with crash submissions, count, and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listCrashes(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appID = arguments["app_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'app_id' is missing")
        }

        do {
            let response: ASCBetaFeedbackCrashSubmissionsResponse
            let query = buildListQuery(arguments)
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                var requiredParameters = query
                requiredParameters.removeValue(forKey: "limit")
                if arguments["sort"]?.stringValue == nil {
                    requiredParameters.removeValue(forKey: "sort")
                }
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope(
                        path: "/v1/apps/\(appID)/betaFeedbackCrashSubmissions",
                        requiredParameters: requiredParameters
                    ),
                    as: ASCBetaFeedbackCrashSubmissionsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v1/apps/\(appID)/betaFeedbackCrashSubmissions",
                    parameters: query,
                    as: ASCBetaFeedbackCrashSubmissionsResponse.self
                )
            }

            var result: [String: Any] = [
                "success": true,
                "crashes": response.data.map { formatCrash($0, includePII: arguments["include_pii"]?.boolValue ?? false) },
                "count": response.data.count
            ]
            appendPaging(response.links, response.meta, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list beta feedback crash submissions: \(error.localizedDescription)")
        }
    }

    /// Gets a TestFlight beta feedback crash submission.
    /// - Parameter params: Tool parameters containing `submission_id`.
    /// - Returns: JSON object with one crash submission.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getCrash(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let submissionID = arguments["submission_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'submission_id' is missing")
        }

        do {
            let response = try await httpClient.get(
                "/v1/betaFeedbackCrashSubmissions/\(submissionID)",
                parameters: relatedQuery(arguments),
                as: ASCBetaFeedbackCrashSubmissionResponse.self
            )
            return MCPResult.jsonObject([
                "success": true,
                "crash": formatCrash(response.data, includePII: arguments["include_pii"]?.boolValue ?? true)
            ])
        } catch {
            return MCPResult.error("Failed to get beta feedback crash submission: \(error.localizedDescription)")
        }
    }

    /// Reads crash log text for a TestFlight beta feedback crash submission.
    /// - Parameter params: Tool parameters containing `submission_id`.
    /// - Returns: JSON object with crash log text, truncation state, and size.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getCrashLog(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let submissionID = arguments["submission_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'submission_id' is missing")
        }

        return try await fetchCrashLog(
            endpoint: "/v1/betaFeedbackCrashSubmissions/\(submissionID)/crashLog",
            arguments: arguments
        )
    }

    /// Reads crash log text by beta crash log ID.
    /// - Parameter params: Tool parameters containing `crash_log_id`.
    /// - Returns: JSON object with crash log text, truncation state, and size.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getCrashLogByID(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let crashLogID = arguments["crash_log_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'crash_log_id' is missing")
        }

        return try await fetchCrashLog(
            endpoint: "/v1/betaCrashLogs/\(crashLogID)",
            arguments: arguments
        )
    }

    /// Deletes a TestFlight beta feedback crash submission.
    /// - Parameter params: Tool parameters containing `submission_id`.
    /// - Returns: JSON confirmation.
    /// - Throws: Networking or API errors from App Store Connect.
    func deleteCrash(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let submissionID = arguments["submission_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'submission_id' is missing")
        }

        do {
            _ = try await httpClient.delete("/v1/betaFeedbackCrashSubmissions/\(submissionID)")
            return MCPResult.jsonObject([
                "success": true,
                "message": "Beta feedback crash submission '\(submissionID)' deleted"
            ])
        } catch {
            return MCPResult.error("Failed to delete beta feedback crash submission: \(error.localizedDescription)")
        }
    }

    /// Lists TestFlight beta feedback screenshot submissions for an app.
    /// - Parameter params: Tool parameters containing `app_id` and optional filters.
    /// - Returns: JSON object with screenshot submissions, count, and pagination fields.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func listScreenshots(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appID = arguments["app_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'app_id' is missing")
        }

        do {
            let response: ASCBetaFeedbackScreenshotSubmissionsResponse
            let query = buildListQuery(arguments)
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                var requiredParameters = query
                requiredParameters.removeValue(forKey: "limit")
                if arguments["sort"]?.stringValue == nil {
                    requiredParameters.removeValue(forKey: "sort")
                }
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope(
                        path: "/v1/apps/\(appID)/betaFeedbackScreenshotSubmissions",
                        requiredParameters: requiredParameters
                    ),
                    as: ASCBetaFeedbackScreenshotSubmissionsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v1/apps/\(appID)/betaFeedbackScreenshotSubmissions",
                    parameters: query,
                    as: ASCBetaFeedbackScreenshotSubmissionsResponse.self
                )
            }

            var result: [String: Any] = [
                "success": true,
                "screenshots": response.data.map { formatScreenshot($0, includePII: arguments["include_pii"]?.boolValue ?? false) },
                "count": response.data.count
            ]
            appendPaging(response.links, response.meta, to: &result)
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error("Failed to list beta feedback screenshot submissions: \(error.localizedDescription)")
        }
    }

    /// Gets a TestFlight beta feedback screenshot submission.
    /// - Parameter params: Tool parameters containing `submission_id`.
    /// - Returns: JSON object with one screenshot submission.
    /// - Throws: Networking, decoding, or API errors from App Store Connect.
    func getScreenshot(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let submissionID = arguments["submission_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'submission_id' is missing")
        }

        do {
            let response = try await httpClient.get(
                "/v1/betaFeedbackScreenshotSubmissions/\(submissionID)",
                parameters: relatedQuery(arguments),
                as: ASCBetaFeedbackScreenshotSubmissionResponse.self
            )
            return MCPResult.jsonObject([
                "success": true,
                "screenshot": formatScreenshot(response.data, includePII: arguments["include_pii"]?.boolValue ?? true)
            ])
        } catch {
            return MCPResult.error("Failed to get beta feedback screenshot submission: \(error.localizedDescription)")
        }
    }

    /// Deletes a TestFlight beta feedback screenshot submission.
    /// - Parameter params: Tool parameters containing `submission_id`.
    /// - Returns: JSON confirmation.
    /// - Throws: Networking or API errors from App Store Connect.
    func deleteScreenshot(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let submissionID = arguments["submission_id"]?.stringValue else {
            return MCPResult.error("Required parameter 'submission_id' is missing")
        }

        do {
            _ = try await httpClient.delete("/v1/betaFeedbackScreenshotSubmissions/\(submissionID)")
            return MCPResult.jsonObject([
                "success": true,
                "message": "Beta feedback screenshot submission '\(submissionID)' deleted"
            ])
        } catch {
            return MCPResult.error("Failed to delete beta feedback screenshot submission: \(error.localizedDescription)")
        }
    }

    private func fetchCrashLog(endpoint: String, arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let response = try await httpClient.get(endpoint, as: ASCBetaCrashLogResponse.self)
            let rawText = response.data.attributes?.logText ?? ""
            let maxChars = min(max(arguments["max_log_chars"]?.intValue ?? 100_000, 1), 500_000)
            let truncatedText = String(rawText.prefix(maxChars))
            return MCPResult.jsonObject([
                "success": true,
                "crashLog": [
                    "id": response.data.id,
                    "type": response.data.type,
                    "logText": truncatedText,
                    "totalCharacters": rawText.count,
                    "returnedCharacters": truncatedText.count,
                    "truncated": rawText.count > truncatedText.count
                ]
            ])
        } catch {
            return MCPResult.error("Failed to read beta crash log: \(error.localizedDescription)")
        }
    }

    private func buildListQuery(_ arguments: [String: Value]) -> [String: String] {
        var query: [String: String] = [
            "limit": String(min(max(arguments["limit"]?.intValue ?? 25, 1), 200)),
            "sort": arguments["sort"]?.stringValue ?? "-createdDate"
        ]

        setQuery("filter[build]", from: "build_id", arguments: arguments, into: &query)
        setQuery("filter[build.preReleaseVersion]", from: "pre_release_version_id", arguments: arguments, into: &query)
        setQuery("filter[tester]", from: "tester_id", arguments: arguments, into: &query)
        setQuery("filter[deviceModel]", from: "device_model", arguments: arguments, into: &query)
        setQuery("filter[osVersion]", from: "os_version", arguments: arguments, into: &query)
        setQuery("filter[appPlatform]", from: "app_platform", arguments: arguments, into: &query)
        setQuery("filter[devicePlatform]", from: "device_platform", arguments: arguments, into: &query)

        if arguments["include_related"]?.boolValue == true {
            query["include"] = "build,tester"
        }

        return query
    }

    private func relatedQuery(_ arguments: [String: Value]) -> [String: String] {
        arguments["include_related"]?.boolValue == true ? ["include": "build,tester"] : [:]
    }

    private func setQuery(_ apiName: String, from argumentName: String, arguments: [String: Value], into query: inout [String: String]) {
        if let value = arguments[argumentName]?.stringValue {
            query[apiName] = value
        }
    }

    private func appendPaging(_ links: ASCPagedDocumentLinks?, _ meta: ASCPagingInformation?, to result: inout [String: Any]) {
        if let next = links?.next {
            result["next_url"] = next
        }
        if let total = meta?.paging?.total {
            result["total"] = total
        }
    }

    private func formatCrash(_ submission: ASCBetaFeedbackCrashSubmission, includePII: Bool) -> [String: Any] {
        var result = formatCommonFeedback(
            id: submission.id,
            type: submission.type,
            attributes: submission.attributes,
            buildID: submission.relationships?.build?.data?.id,
            testerID: submission.relationships?.tester?.data?.id,
            includePII: includePII
        )
        result["hasCrashLogRelationship"] = submission.relationships?.crashLog != nil
        return result
    }

    private func formatScreenshot(_ submission: ASCBetaFeedbackScreenshotSubmission, includePII: Bool) -> [String: Any] {
        var result = formatCommonFeedback(
            id: submission.id,
            type: submission.type,
            attributes: submission.attributes,
            buildID: submission.relationships?.build?.data?.id,
            testerID: submission.relationships?.tester?.data?.id,
            includePII: includePII
        )
        result["screenshots"] = submission.attributes?.screenshots?.map(formatScreenshotImage) ?? []
        return result
    }

    private func formatCommonFeedback(
        id: String,
        type: String,
        attributes: FeedbackAttributes?,
        buildID: String?,
        testerID: String?,
        includePII: Bool
    ) -> [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "type": type,
            "createdDate": (attributes?.createdDate).jsonSafe,
            "deviceModel": (attributes?.deviceModel).jsonSafe,
            "osVersion": (attributes?.osVersion).jsonSafe,
            "locale": (attributes?.locale).jsonSafe,
            "timeZone": (attributes?.timeZone).jsonSafe,
            "architecture": (attributes?.architecture).jsonSafe,
            "connectionType": (attributes?.connectionType).jsonSafe,
            "pairedAppleWatch": (attributes?.pairedAppleWatch).jsonSafe,
            "appUptimeInMilliseconds": (attributes?.appUptimeInMilliseconds).jsonSafe,
            "diskBytesAvailable": (attributes?.diskBytesAvailable).jsonSafe,
            "diskBytesTotal": (attributes?.diskBytesTotal).jsonSafe,
            "batteryPercentage": (attributes?.batteryPercentage).jsonSafe,
            "screenWidthInPoints": (attributes?.screenWidthInPoints).jsonSafe,
            "screenHeightInPoints": (attributes?.screenHeightInPoints).jsonSafe,
            "appPlatform": (attributes?.appPlatform).jsonSafe,
            "devicePlatform": (attributes?.devicePlatform).jsonSafe,
            "deviceFamily": (attributes?.deviceFamily).jsonSafe,
            "buildBundleId": (attributes?.buildBundleId).jsonSafe,
            "buildId": buildID.jsonSafe,
            "testerId": testerID.jsonSafe
        ]

        if includePII {
            result["email"] = (attributes?.email).jsonSafe
            result["comment"] = (attributes?.comment).jsonSafe
        }

        return result
    }

    private func formatScreenshotImage(_ image: ASCBetaFeedbackScreenshotImage) -> [String: Any] {
        [
            "url": image.url.jsonSafe,
            "width": image.width.jsonSafe,
            "height": image.height.jsonSafe,
            "expirationDate": image.expirationDate.jsonSafe
        ]
    }
}

private protocol FeedbackAttributes {
    var createdDate: String? { get }
    var comment: String? { get }
    var email: String? { get }
    var deviceModel: String? { get }
    var osVersion: String? { get }
    var locale: String? { get }
    var timeZone: String? { get }
    var architecture: String? { get }
    var connectionType: String? { get }
    var pairedAppleWatch: String? { get }
    var appUptimeInMilliseconds: Int64? { get }
    var diskBytesAvailable: Int64? { get }
    var diskBytesTotal: Int64? { get }
    var batteryPercentage: Int? { get }
    var screenWidthInPoints: Int? { get }
    var screenHeightInPoints: Int? { get }
    var appPlatform: String? { get }
    var devicePlatform: String? { get }
    var deviceFamily: String? { get }
    var buildBundleId: String? { get }
}

extension ASCBetaFeedbackCrashSubmission.Attributes: FeedbackAttributes {}
extension ASCBetaFeedbackScreenshotSubmission.Attributes: FeedbackAttributes {}
