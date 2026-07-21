import Foundation
import MCP

extension MetricsWorker {
    func getAppBetaTesterUsage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        await betaTesterUsage(
            params,
            parentField: "app_id",
            endpoint: { "/v1/apps/" + $0 + "/metrics/betaTesterUsages" },
            metricName: "app_beta_tester_usage"
        )
    }

    func getGroupBetaTesterUsage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        await betaTesterUsage(
            params,
            parentField: "group_id",
            endpoint: { "/v1/betaGroups/" + $0 + "/metrics/betaTesterUsages" },
            metricName: "group_beta_tester_usage"
        )
    }

    func getGroupPublicLinkUsage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'group_id' is missing")
        }
        do {
            try validateTestFlightMetricArguments(arguments, allowed: ["group_id", "limit", "next_url"])
            let groupID = try testFlightMetricIdentifier("group_id", from: arguments)
            let path = "/v1/betaGroups/\(try ASCPathSegment.encode(groupID, field: "group_id"))/metrics/publicLinkUsages"
            let query = try testFlightMetricPagingQuery(arguments)
            let response: ASCPublicLinkUsageMetricsResponse = try await fetchTestFlightMetric(
                path: path,
                query: query,
                nextURL: arguments["next_url"],
                as: ASCPublicLinkUsageMetricsResponse.self
            )
            try validateMetricDocument(
                links: response.links,
                meta: response.meta,
                pageCount: response.data.count,
                expectedPath: path,
                context: "group public-link usage metrics"
            )
            return metricResult(
                metricName: "group_public_link_usage",
                groups: response.data.map(formatPublicLinkUsageMetricGroup),
                links: response.links,
                meta: response.meta,
                query: query,
                requestEchoes: ["group_id": groupID]
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to get TestFlight public-link usage metrics")
        }
    }

    func getTesterUsage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameters 'tester_id' and 'app_id' are missing")
        }
        do {
            try validateTestFlightMetricArguments(
                arguments,
                allowed: ["tester_id", "app_id", "period", "limit", "next_url"]
            )
            let testerID = try testFlightMetricIdentifier("tester_id", from: arguments)
            let appID = try testFlightMetricIdentifier("app_id", from: arguments)
            var query = try testFlightMetricPagingQuery(arguments)
            query["filter[apps]"] = appID
            if let period = try testFlightMetricPeriod(arguments["period"]) {
                query["period"] = period
            }
            let path = "/v1/betaTesters/\(try ASCPathSegment.encode(testerID, field: "tester_id"))/metrics/betaTesterUsages"
            let response: ASCTesterUsageMetricsResponse = try await fetchTestFlightMetric(
                path: path,
                query: query,
                nextURL: arguments["next_url"],
                as: ASCTesterUsageMetricsResponse.self
            )
            try validateMetricDocument(
                links: response.links,
                meta: response.meta,
                pageCount: response.data.count,
                expectedPath: path,
                context: "tester usage metrics"
            )
            for group in response.data {
                if let dimension = group.dimensions?.apps {
                    try validateMetricDimension(
                        dimension,
                        expectedID: appID,
                        context: "tester usage app dimension"
                    )
                }
            }
            return metricResult(
                metricName: "tester_usage",
                groups: response.data.map(formatTesterUsageMetricGroup),
                links: response.links,
                meta: response.meta,
                query: query,
                requestEchoes: ["tester_id": testerID, "app_id": appID]
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to get beta tester usage metrics")
        }
    }

    func getBuildBetaUsage(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter 'build_id' is missing")
        }
        do {
            try validateTestFlightMetricArguments(arguments, allowed: ["build_id", "limit", "next_url"])
            let buildID = try testFlightMetricIdentifier("build_id", from: arguments)
            let path = "/v1/builds/\(try ASCPathSegment.encode(buildID, field: "build_id"))/metrics/betaBuildUsages"
            let query = try testFlightMetricPagingQuery(arguments)
            let response: ASCBuildBetaUsageMetricsResponse = try await fetchTestFlightMetric(
                path: path,
                query: query,
                nextURL: arguments["next_url"],
                as: ASCBuildBetaUsageMetricsResponse.self
            )
            try validateMetricDocument(
                links: response.links,
                meta: response.meta,
                pageCount: response.data.count,
                expectedPath: path,
                context: "build beta usage metrics"
            )
            return metricResult(
                metricName: "build_beta_usage",
                groups: response.data.map(formatBuildBetaUsageMetricGroup),
                links: response.links,
                meta: response.meta,
                query: query,
                requestEchoes: ["build_id": buildID]
            )
        } catch {
            return MCPResult.error(error, prefix: "Failed to get build beta usage metrics")
        }
    }
}

private extension MetricsWorker {
    func betaTesterUsage(
        _ params: CallTool.Parameters,
        parentField: String,
        endpoint: (String) -> String,
        metricName: String
    ) async -> CallTool.Result {
        guard let arguments = params.arguments else {
            return MCPResult.error("Required parameter '\(parentField)' is missing")
        }
        do {
            try validateTestFlightMetricArguments(
                arguments,
                allowed: [parentField, "period", "group_by", "beta_tester_id", "limit", "next_url"]
            )
            let parentID = try testFlightMetricIdentifier(parentField, from: arguments)
            let encodedID = try ASCPathSegment.encode(parentID, field: parentField)
            var query = try testFlightMetricPagingQuery(arguments)
            if let period = try testFlightMetricPeriod(arguments["period"]) {
                query["period"] = period
            }
            if let grouping = try testFlightMetricGrouping(arguments["group_by"]) {
                query["groupBy"] = grouping
            }
            let testerID = try testFlightMetricOptionalIdentifier(
                arguments["beta_tester_id"],
                field: "beta_tester_id"
            )
            if let testerID {
                query["filter[betaTesters]"] = testerID
            }
            let path = endpoint(encodedID)
            let response: ASCBetaTesterUsageMetricsResponse = try await fetchTestFlightMetric(
                path: path,
                query: query,
                nextURL: arguments["next_url"],
                as: ASCBetaTesterUsageMetricsResponse.self
            )
            try validateMetricDocument(
                links: response.links,
                meta: response.meta,
                pageCount: response.data.count,
                expectedPath: path,
                context: "\(metricName) metrics"
            )
            for group in response.data {
                if let dimension = group.dimensions?.betaTesters {
                    try validateMetricDimension(
                        dimension,
                        expectedID: testerID,
                        context: "\(metricName) beta tester dimension"
                    )
                }
            }
            var includedIDs = Set<String>()
            for tester in response.included ?? [] {
                try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                    type: tester.type.rawValue,
                    id: tester.id,
                    expectedType: "betaTesters",
                    context: "\(metricName) included beta tester"
                )
                guard includedIDs.insert(tester.id).inserted else {
                    throw TestFlightMetricArgumentError("Apple returned a duplicate included beta tester identity")
                }
            }
            var result = metricResultDictionary(
                metricName: metricName,
                groups: response.data.map(formatBetaTesterUsageMetricGroup),
                links: response.links,
                meta: response.meta,
                query: query,
                requestEchoes: [parentField: parentID]
            )
            if let included = response.included {
                result["includedBetaTesters"] = included.map(formatMetricBetaTester)
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to get TestFlight beta tester usage metrics")
        }
    }

    func fetchTestFlightMetric<Response: Decodable & Sendable>(
        path: String,
        query: [String: String],
        nextURL: Value?,
        as type: Response.Type
    ) async throws -> Response {
        let data: Data
        if let nextURL = try paginationURL(from: nextURL) {
            data = try await httpClient.getPage(
                nextURL,
                scope: PaginationScope.strict(path: path, query: query)
            )
        } else {
            data = try await httpClient.get(path, parameters: query)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ASCError.parsing("Failed to decode \(type): \(error.localizedDescription)")
        }
    }

    func metricResult(
        metricName: String,
        groups: [[String: Any]],
        links: ASCPagedDocumentLinks,
        meta: ASCPagingInformation?,
        query: [String: String],
        requestEchoes: [String: String]
    ) -> CallTool.Result {
        MCPResult.jsonObject(metricResultDictionary(
            metricName: metricName,
            groups: groups,
            links: links,
            meta: meta,
            query: query,
            requestEchoes: requestEchoes
        ))
    }

    func metricResultDictionary(
        metricName: String,
        groups: [[String: Any]],
        links: ASCPagedDocumentLinks,
        meta: ASCPagingInformation?,
        query: [String: String],
        requestEchoes: [String: String]
    ) -> [String: Any] {
        var result: [String: Any] = [
            "success": true,
            "metric": metricName,
            "groups": groups,
            "count": groups.count,
            "limit": Int(query["limit"] ?? "") ?? 25
        ]
        for (key, value) in requestEchoes {
            result[key] = value
        }
        if let period = query["period"] {
            result["period"] = period
        }
        if let groupBy = query["groupBy"] {
            result["group_by"] = groupBy.split(separator: ",").map(String.init)
        }
        if let testerID = query["filter[betaTesters]"] {
            result["beta_tester_id"] = testerID
        }
        if let next = links.next {
            result["next_url"] = next
        }
        if let total = meta?.paging?.total {
            result["total"] = total
        }
        return result
    }

    func testFlightMetricPagingQuery(_ arguments: [String: Value]) throws -> [String: String] {
        let limit: Int
        if let value = arguments["limit"] {
            guard let parsed = value.intValue, (1...200).contains(parsed) else {
                throw TestFlightMetricArgumentError("limit must be an integer between 1 and 200")
            }
            limit = parsed
        } else {
            limit = 25
        }
        return ["limit": String(limit)]
    }

    func validateTestFlightMetricArguments(_ arguments: [String: Value], allowed: Set<String>) throws {
        let unsupported = Set(arguments.keys).subtracting(allowed).sorted()
        guard unsupported.isEmpty else {
            throw TestFlightMetricArgumentError("Unsupported parameter(s): \(unsupported.joined(separator: ", "))")
        }
    }

    func testFlightMetricPeriod(_ value: Value?) throws -> String? {
        guard let value else { return nil }
        guard let period = value.stringValue,
              ["P7D", "P30D", "P90D", "P365D"].contains(period) else {
            throw TestFlightMetricArgumentError("period must be one of P7D, P30D, P90D, or P365D")
        }
        return period
    }

    func testFlightMetricGrouping(_ value: Value?) throws -> String? {
        guard let value else { return nil }
        let values: [String]
        if let scalar = value.stringValue {
            values = [scalar]
        } else if let array = value.arrayValue {
            guard array.count == 1, let only = array.first?.stringValue else {
                throw TestFlightMetricArgumentError("group_by must contain exactly one string")
            }
            values = [only]
        } else {
            throw TestFlightMetricArgumentError("group_by must be a string or one-item string array")
        }
        guard values == ["betaTesters"] else {
            throw TestFlightMetricArgumentError("group_by only supports betaTesters")
        }
        return values.joined(separator: ",")
    }

    func testFlightMetricIdentifier(_ name: String, from arguments: [String: Value]) throws -> String {
        guard let value = arguments[name] else {
            throw TestFlightMetricArgumentError("\(name) is required")
        }
        guard let identifier = try testFlightMetricOptionalIdentifier(value, field: name) else {
            throw TestFlightMetricArgumentError("\(name) is required")
        }
        return identifier
    }

    func testFlightMetricOptionalIdentifier(_ value: Value?, field: String) throws -> String? {
        guard let value else { return nil }
        guard let identifier = value.stringValue else {
            throw TestFlightMetricArgumentError("\(field) must be a string")
        }
        let encoded = try ASCPathSegment.encode(identifier, field: field)
        guard encoded == identifier else {
            throw TestFlightMetricArgumentError("\(field) must be a canonical App Store Connect resource ID")
        }
        return identifier
    }

    func validateMetricDocument(
        links: ASCPagedDocumentLinks,
        meta: ASCPagingInformation?,
        pageCount: Int,
        expectedPath: String,
        context: String
    ) throws {
        try validateMetricDocumentSelf(links.`self`, expectedPath: expectedPath, context: context)
        if let next = links.next,
           next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TestFlightMetricArgumentError("Apple returned an empty continuation URL in \(context)")
        }
        guard let meta else { return }
        guard let paging = meta.paging,
              let limit = paging.limit else {
            throw TestFlightMetricArgumentError("Apple returned incomplete paging metadata in \(context)")
        }
        if limit <= 0 || limit < pageCount {
            throw TestFlightMetricArgumentError("Apple returned an invalid paging limit in \(context)")
        }
        if let total = paging.total, total < pageCount {
            throw TestFlightMetricArgumentError("Apple returned paging total below the page count in \(context)")
        }
        if let cursor = paging.nextCursor,
           cursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || links.next == nil {
            throw TestFlightMetricArgumentError("Apple returned inconsistent paging cursor state in \(context)")
        }
    }

    func validateMetricDocumentSelf(_ value: String, expectedPath: String, context: String) throws {
        guard !value.isEmpty,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let components = URLComponents(string: value),
              components.fragment == nil,
              components.user == nil,
              components.password == nil else {
            throw TestFlightMetricArgumentError("Apple returned an invalid required links.self in \(context)")
        }
        if components.scheme != nil || components.host != nil {
            guard components.scheme == "https", components.host?.isEmpty == false else {
                throw TestFlightMetricArgumentError("Apple returned a non-HTTPS required links.self in \(context)")
            }
        }
        guard components.percentEncodedPath == expectedPath else {
            throw TestFlightMetricArgumentError("Apple returned required links.self outside \(context)")
        }
        _ = try validatedASCAPIEndpoint(components.percentEncodedPath)
    }

    func validateMetricDimension(
        _ dimension: ASCTestFlightMetricDimension,
        expectedID: String?,
        context: String
    ) throws {
        if let identifier = dimension.data {
            let encoded = try ASCPathSegment.encode(identifier, field: "\(context) identifier")
            guard encoded == identifier else {
                throw TestFlightMetricArgumentError("Apple returned a non-canonical metric dimension identity")
            }
            if let expectedID, identifier != expectedID {
                throw TestFlightMetricArgumentError("Apple returned a metric dimension outside the requested filter scope")
            }
        }
        for link in [dimension.links?.groupBy, dimension.links?.related].compactMap({ $0 }) {
            guard !link.isEmpty,
                  link == link.trimmingCharacters(in: .whitespacesAndNewlines),
                  !link.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  let components = URLComponents(string: link),
                  components.user == nil,
                  components.password == nil else {
                throw TestFlightMetricArgumentError("Apple returned an invalid metric dimension link")
            }
        }
    }

    func formatBetaTesterUsageMetricGroup(_ group: ASCBetaTesterUsageMetricGroup) -> [String: Any] {
        var result: [String: Any] = [
            "data_points": group.dataPoints.map { $0.map(formatBetaTesterUsageMetricDataPoint) }.jsonSafe
        ]
        if let dimension = group.dimensions?.betaTesters {
            result["dimensions"] = ["beta_testers": formatMetricDimension(dimension)]
        }
        return result
    }

    func formatTesterUsageMetricGroup(_ group: ASCTesterUsageMetricGroup) -> [String: Any] {
        var result: [String: Any] = [
            "data_points": group.dataPoints.map { $0.map(formatBetaTesterUsageMetricDataPoint) }.jsonSafe
        ]
        if let dimension = group.dimensions?.apps {
            result["dimensions"] = ["apps": formatMetricDimension(dimension)]
        }
        return result
    }

    func formatPublicLinkUsageMetricGroup(_ group: ASCPublicLinkUsageMetricGroup) -> [String: Any] {
        ["data_points": group.dataPoints.map { $0.map(formatPublicLinkUsageMetricDataPoint) }.jsonSafe]
    }

    func formatBuildBetaUsageMetricGroup(_ group: ASCBuildBetaUsageMetricGroup) -> [String: Any] {
        ["data_points": group.dataPoints.map { $0.map(formatBuildBetaUsageMetricDataPoint) }.jsonSafe]
    }

    func formatBetaTesterUsageMetricDataPoint(_ point: ASCBetaTesterUsageMetricDataPoint) -> [String: Any] {
        [
            "start": point.start.jsonSafe,
            "end": point.end.jsonSafe,
            "values": point.values.map(formatBetaTesterUsageMetricValues).jsonSafe
        ]
    }

    func formatPublicLinkUsageMetricDataPoint(_ point: ASCPublicLinkUsageMetricDataPoint) -> [String: Any] {
        [
            "start": point.start.jsonSafe,
            "end": point.end.jsonSafe,
            "values": point.values.map(formatPublicLinkUsageMetricValues).jsonSafe
        ]
    }

    func formatBuildBetaUsageMetricDataPoint(_ point: ASCBuildBetaUsageMetricDataPoint) -> [String: Any] {
        [
            "start": point.start.jsonSafe,
            "end": point.end.jsonSafe,
            "values": point.values.map(formatBuildBetaUsageMetricValues).jsonSafe
        ]
    }

    func formatBetaTesterUsageMetricValues(_ values: ASCBetaTesterUsageMetricValues) -> [String: Any] {
        var result: [String: Any] = [:]
        if let value = values.crashCount { result["crash_count"] = value }
        if let value = values.sessionCount { result["session_count"] = value }
        if let value = values.feedbackCount { result["feedback_count"] = value }
        return result
    }

    func formatPublicLinkUsageMetricValues(_ values: ASCPublicLinkUsageMetricValues) -> [String: Any] {
        var result: [String: Any] = [:]
        if let value = values.viewCount { result["view_count"] = value }
        if let value = values.acceptedCount { result["accepted_count"] = value }
        if let value = values.didNotAcceptCount { result["did_not_accept_count"] = value }
        if let value = values.didNotMeetCriteriaCount { result["did_not_meet_criteria_count"] = value }
        if let value = values.notRelevantRatio { result["not_relevant_ratio"] = value }
        if let value = values.notClearRatio { result["not_clear_ratio"] = value }
        if let value = values.notInterestingRatio { result["not_interesting_ratio"] = value }
        return result
    }

    func formatBuildBetaUsageMetricValues(_ values: ASCBuildBetaUsageMetricValues) -> [String: Any] {
        var result: [String: Any] = [:]
        if let value = values.crashCount { result["crash_count"] = value }
        if let value = values.installCount { result["install_count"] = value }
        if let value = values.sessionCount { result["session_count"] = value }
        if let value = values.feedbackCount { result["feedback_count"] = value }
        if let value = values.inviteCount { result["invite_count"] = value }
        return result
    }

    func formatMetricDimension(_ dimension: ASCTestFlightMetricDimension) -> [String: Any] {
        [
            "id": dimension.data.jsonSafe,
            "group_by_url": (dimension.links?.groupBy).jsonSafe,
            "related_url": (dimension.links?.related).jsonSafe
        ]
    }

    func formatMetricBetaTester(_ tester: ASCTestFlightIncludedBetaTester) -> [String: Any] {
        [
            "id": tester.id,
            "type": tester.type.rawValue,
            "email": (tester.attributes?.email).jsonSafe,
            "firstName": (tester.attributes?.firstName).jsonSafe,
            "lastName": (tester.attributes?.lastName).jsonSafe,
            "inviteType": (tester.attributes?.inviteType).jsonSafe,
            "state": (tester.attributes?.state).jsonSafe,
            "appDevices": (tester.attributes?.appDevices).map {
                $0.map(formatMetricBetaTesterDevice)
            }.jsonSafe
        ]
    }

    func formatMetricBetaTesterDevice(_ device: BetaTesterAppDevice) -> [String: Any] {
        [
            "model": device.model.jsonSafe,
            "platform": (device.platform?.rawValue).jsonSafe,
            "osVersion": device.osVersion.jsonSafe,
            "appBuildVersion": device.appBuildVersion.jsonSafe
        ]
    }
}

private struct TestFlightMetricArgumentError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
