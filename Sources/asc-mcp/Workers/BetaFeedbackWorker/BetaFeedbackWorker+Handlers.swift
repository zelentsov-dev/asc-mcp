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
            let includePII = try booleanArgument(arguments["include_pii"], name: "include_pii", defaultValue: false)
            let response: ASCBetaFeedbackCrashSubmissionsResponse
            let query = try buildListQuery(arguments)
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope.strict(
                        path: "/v1/apps/\(try ASCPathSegment.encode(appID))/betaFeedbackCrashSubmissions",
                        query: query
                    ),
                    as: ASCBetaFeedbackCrashSubmissionsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v1/apps/\(try ASCPathSegment.encode(appID))/betaFeedbackCrashSubmissions",
                    parameters: query,
                    as: ASCBetaFeedbackCrashSubmissionsResponse.self
                )
            }

            var result: [String: Any] = [
                "success": true,
                "crashes": response.data.map { formatCrash($0, includePII: includePII) },
                "count": response.data.count
            ]
            appendIncluded(response.included, includePII: includePII, to: &result)
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
            let includePII = try booleanArgument(arguments["include_pii"], name: "include_pii", defaultValue: true)
            let response = try await httpClient.get(
                "/v1/betaFeedbackCrashSubmissions/\(try ASCPathSegment.encode(submissionID))",
                parameters: try relatedQuery(arguments),
                as: ASCBetaFeedbackCrashSubmissionResponse.self
            )
            var result: [String: Any] = [
                "success": true,
                "crash": formatCrash(response.data, includePII: includePII)
            ]
            appendIncluded(response.included, includePII: includePII, to: &result)
            return MCPResult.jsonObject(result)
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
            endpoint: "/v1/betaFeedbackCrashSubmissions/\(try ASCPathSegment.encode(submissionID))/crashLog",
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
            endpoint: "/v1/betaCrashLogs/\(try ASCPathSegment.encode(crashLogID))",
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
            _ = try await httpClient.delete("/v1/betaFeedbackCrashSubmissions/\(try ASCPathSegment.encode(submissionID))")
            return MCPResult.jsonObject([
                "success": true,
                "message": "Beta feedback crash submission '\(submissionID)' deleted"
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to delete beta feedback crash submission")
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
            let includePII = try booleanArgument(arguments["include_pii"], name: "include_pii", defaultValue: false)
            let response: ASCBetaFeedbackScreenshotSubmissionsResponse
            let query = try buildListQuery(arguments)
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope.strict(
                        path: "/v1/apps/\(try ASCPathSegment.encode(appID))/betaFeedbackScreenshotSubmissions",
                        query: query
                    ),
                    as: ASCBetaFeedbackScreenshotSubmissionsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    "/v1/apps/\(try ASCPathSegment.encode(appID))/betaFeedbackScreenshotSubmissions",
                    parameters: query,
                    as: ASCBetaFeedbackScreenshotSubmissionsResponse.self
                )
            }

            var result: [String: Any] = [
                "success": true,
                "screenshots": response.data.map { formatScreenshot($0, includePII: includePII) },
                "count": response.data.count
            ]
            appendIncluded(response.included, includePII: includePII, to: &result)
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
            let includePII = try booleanArgument(arguments["include_pii"], name: "include_pii", defaultValue: true)
            let response = try await httpClient.get(
                "/v1/betaFeedbackScreenshotSubmissions/\(try ASCPathSegment.encode(submissionID))",
                parameters: try relatedQuery(arguments),
                as: ASCBetaFeedbackScreenshotSubmissionResponse.self
            )
            var result: [String: Any] = [
                "success": true,
                "screenshot": formatScreenshot(response.data, includePII: includePII)
            ]
            appendIncluded(response.included, includePII: includePII, to: &result)
            return MCPResult.jsonObject(result)
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
            _ = try await httpClient.delete("/v1/betaFeedbackScreenshotSubmissions/\(try ASCPathSegment.encode(submissionID))")
            return MCPResult.jsonObject([
                "success": true,
                "message": "Beta feedback screenshot submission '\(submissionID)' deleted"
            ])
        } catch {
            return MCPResult.error(error, prefix: "Failed to delete beta feedback screenshot submission")
        }
    }

    private func fetchCrashLog(endpoint: String, arguments: [String: Value]) async throws -> CallTool.Result {
        do {
            let maxChars = try integerArgument(
                arguments["max_log_chars"],
                name: "max_log_chars",
                defaultValue: 100_000,
                range: 1...500_000
            )
            let response = try await httpClient.get(endpoint, as: ASCBetaCrashLogResponse.self)
            let rawText = response.data.attributes?.logText ?? ""
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

    private func buildListQuery(_ arguments: [String: Value]) throws -> [String: String] {
        let limit = try integerArgument(arguments["limit"], name: "limit", defaultValue: 25, range: 1...200)
        var query: [String: String] = [
            "limit": String(limit),
            "sort": try commaSeparated(
                arguments["sort"],
                name: "sort",
                allowedValues: Set(["createdDate", "-createdDate"])
            ) ?? "-createdDate"
        ]

        try setQuery("filter[build]", from: "build_id", arguments: arguments, into: &query)
        try setQuery("filter[build.preReleaseVersion]", from: "pre_release_version_id", arguments: arguments, into: &query)
        try setQuery("filter[tester]", from: "tester_id", arguments: arguments, into: &query)
        try setQuery("filter[deviceModel]", from: "device_model", arguments: arguments, into: &query)
        try setQuery("filter[osVersion]", from: "os_version", arguments: arguments, into: &query)
        try setQuery(
            "filter[appPlatform]",
            from: "app_platform",
            arguments: arguments,
            allowedValues: Set(BetaFeedbackPlatformValues.all),
            into: &query
        )
        try setQuery(
            "filter[devicePlatform]",
            from: "device_platform",
            arguments: arguments,
            allowedValues: Set(BetaFeedbackPlatformValues.all),
            into: &query
        )

        if let include = try includeValue(arguments) {
            query["include"] = include
        }

        return query
    }

    private func relatedQuery(_ arguments: [String: Value]) throws -> [String: String] {
        guard let include = try includeValue(arguments) else {
            return [:]
        }
        return ["include": include]
    }

    private func setQuery(
        _ apiName: String,
        from argumentName: String,
        arguments: [String: Value],
        allowedValues: Set<String>? = nil,
        into query: inout [String: String]
    ) throws {
        if let value = try commaSeparated(arguments[argumentName], name: argumentName, allowedValues: allowedValues) {
            query[apiName] = value
        }
    }

    private func includeValue(_ arguments: [String: Value]) throws -> String? {
        if let include = try commaSeparated(
            arguments["include"],
            name: "include",
            allowedValues: Set(BetaFeedbackIncludeValues.all)
        ) {
            return include
        }
        return try booleanArgument(arguments["include_related"], name: "include_related", defaultValue: false)
            ? BetaFeedbackIncludeValues.all.joined(separator: ",")
            : nil
    }

    private func commaSeparated(
        _ value: Value?,
        name: String,
        allowedValues: Set<String>? = nil
    ) throws -> String? {
        guard let value else {
            return nil
        }

        let values: [String]
        if let string = value.stringValue {
            values = string.split(separator: ",", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if let array = value.arrayValue {
            let strings = array.compactMap(\.stringValue)
            guard strings.count == array.count else {
                throw BetaFeedbackInputError("'\(name)' must be a string or an array of strings")
            }
            values = strings.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        } else {
            throw BetaFeedbackInputError("'\(name)' must be a string or an array of strings")
        }

        guard !values.isEmpty, values.allSatisfy({ !$0.isEmpty }) else {
            throw BetaFeedbackInputError("'\(name)' must contain at least one non-empty value")
        }
        guard Set(values).count == values.count else {
            throw BetaFeedbackInputError("'\(name)' must not contain duplicate values")
        }
        if let allowedValues {
            let unsupported = values.filter { !allowedValues.contains($0) }
            guard unsupported.isEmpty else {
                throw BetaFeedbackInputError("Unsupported value(s) for '\(name)': \(unsupported.joined(separator: ", "))")
            }
        }

        return values.joined(separator: ",")
    }

    private func booleanArgument(_ value: Value?, name: String, defaultValue: Bool) throws -> Bool {
        guard let value else {
            return defaultValue
        }
        guard let boolean = value.boolValue else {
            throw BetaFeedbackInputError("'\(name)' must be a boolean")
        }
        return boolean
    }

    private func integerArgument(
        _ value: Value?,
        name: String,
        defaultValue: Int,
        range: ClosedRange<Int>
    ) throws -> Int {
        guard let value else {
            return defaultValue
        }
        guard let integer = value.intValue else {
            throw BetaFeedbackInputError("'\(name)' must be an integer")
        }
        guard range.contains(integer) else {
            throw BetaFeedbackInputError("'\(name)' must be between \(range.lowerBound) and \(range.upperBound)")
        }
        return integer
    }

    private func appendPaging(_ links: ASCPagedDocumentLinks?, _ meta: ASCPagingInformation?, to result: inout [String: Any]) {
        if let next = links?.next {
            result["next_url"] = next
        }
        if let total = meta?.paging?.total {
            result["total"] = total
        }
    }

    private func appendIncluded(
        _ included: [ASCBetaFeedbackIncludedResource]?,
        includePII: Bool,
        to result: inout [String: Any]
    ) {
        guard let included else {
            return
        }
        result["included"] = included.map { formatIncluded($0, includePII: includePII).asAny }
    }

    private func formatIncluded(_ resource: ASCBetaFeedbackIncludedResource, includePII: Bool) -> JSONValue {
        guard !includePII,
              case .betaTester(let value) = resource,
              case .object(var object) = value,
              case .object(var attributes)? = object["attributes"] else {
            return resource.value
        }

        attributes["firstName"] = nil
        attributes["lastName"] = nil
        attributes["email"] = nil
        object["attributes"] = .object(attributes)
        return .object(object)
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

private struct BetaFeedbackInputError: LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
