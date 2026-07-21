import Foundation
import MCP

extension AppsWorker {
    /// Lists App Store search keyword identifiers available to an app.
    /// - Returns: A paginated projection containing canonical search keyword IDs and continuation metadata.
    /// - Throws: Returns an MCP error result when arguments, pagination scope, or Apple's response are invalid.
    public func listSearchKeywords(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]

        do {
            let allowed = Set(["app_id", "platforms", "locales", "limit", "next_url"])
            let unknown = Set(arguments.keys).subtracting(allowed)
            guard unknown.isEmpty else {
                throw AppSearchKeywordArgumentError("Unknown parameter(s): \(unknown.sorted().joined(separator: ", "))")
            }

            guard let appID = arguments["app_id"]?.stringValue else {
                throw AppSearchKeywordArgumentError("Required parameter 'app_id' is missing")
            }
            let encodedAppID = try ASCPathSegment.encode(appID, field: "app_id")
            guard encodedAppID == appID else {
                throw AppSearchKeywordArgumentError("app_id must be a canonical App Store Connect resource ID")
            }

            let limit: Int
            if let value = arguments["limit"] {
                guard let requestedLimit = value.intValue, (1...200).contains(requestedLimit) else {
                    throw AppSearchKeywordArgumentError("limit must be an integer from 1 through 200")
                }
                limit = requestedLimit
            } else {
                limit = 200
            }

            let path = "/v1/apps/\(try ASCPathSegment.encode(appID, field: "app_id"))/searchKeywords"
            var query = ["limit": String(limit)]
            if let platforms = try appSearchKeywordList(arguments["platforms"], field: "platforms") {
                query["filter[platform]"] = platforms.joined(separator: ",")
            }
            if let locales = try appSearchKeywordList(arguments["locales"], field: "locales") {
                query["filter[locale]"] = locales.joined(separator: ",")
            }

            let response: ASCAppKeywordsResponse
            if let nextURL = try appSearchKeywordPaginationURL(arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope.strict(path: path, query: query),
                    as: ASCAppKeywordsResponse.self
                )
            } else {
                response = try await httpClient.get(
                    path,
                    parameters: query,
                    as: ASCAppKeywordsResponse.self
                )
            }

            try validateAppSearchKeywordResponse(
                response,
                expectedPath: path,
                expectedQuery: query,
                requestedLimit: limit
            )

            var result: [String: Any] = [
                "success": true,
                "app_id": appID,
                "search_keywords": response.data.map { ["id": $0.id, "type": $0.type] },
                "count": response.data.count,
                "limit": limit,
                "links": [
                    "self": response.links.`self`,
                    "first": response.links.first.jsonSafe,
                    "next": response.links.next.jsonSafe
                ]
            ]
            if let platforms = try appSearchKeywordList(arguments["platforms"], field: "platforms") {
                result["platforms"] = platforms
            }
            if let locales = try appSearchKeywordList(arguments["locales"], field: "locales") {
                result["locales"] = locales
            }
            if let paging = response.meta?.paging {
                var projectedPaging: [String: Any] = [:]
                if let total = paging.total { projectedPaging["total"] = total }
                if let pageLimit = paging.limit { projectedPaging["limit"] = pageLimit }
                if let nextCursor = paging.nextCursor { projectedPaging["next_cursor"] = nextCursor }
                if !projectedPaging.isEmpty { result["paging"] = projectedPaging }
            }
            if let nextURL = response.links.next {
                result["next_url"] = nextURL
            }
            return MCPResult.jsonObject(result)
        } catch {
            return MCPResult.error(error, prefix: "Failed to list app search keywords")
        }
    }
}

private extension AppsWorker {
    func appSearchKeywordPaginationURL(_ value: Value?) throws -> String? {
        guard let nextURL = try paginationURL(from: value) else { return nil }
        guard !nextURL.unicodeScalars.contains(where: {
            CharacterSet.whitespacesAndNewlines.contains($0) ||
            CharacterSet.controlCharacters.contains($0)
        }) else {
            throw AppSearchKeywordArgumentError("next_url must not contain whitespace or control characters")
        }
        return nextURL
    }

    func appSearchKeywordList(_ value: Value?, field: String) throws -> [String]? {
        guard let value else { return nil }
        guard let items = value.arrayValue, !items.isEmpty else {
            throw AppSearchKeywordArgumentError("\(field) must be a non-empty array of unique strings")
        }
        var seen: Set<String> = []
        let strings = try items.map { item in
            guard let string = item.stringValue,
                  !string.isEmpty,
                  string == string.trimmingCharacters(in: .whitespacesAndNewlines),
                  !string.contains(","),
                  !string.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  seen.insert(string).inserted else {
                throw AppSearchKeywordArgumentError("\(field) must contain only unique non-empty strings without commas")
            }
            return string
        }
        return strings
    }

    func validateAppSearchKeywordResponse(
        _ response: ASCAppKeywordsResponse,
        expectedPath: String,
        expectedQuery: [String: String],
        requestedLimit: Int
    ) throws {
        try validateAppSearchKeywordLink(response.links.`self`, expectedPath: expectedPath)
        guard response.data.count <= requestedLimit else {
            throw AppSearchKeywordArgumentError("Apple returned more app search keywords than the requested limit")
        }
        var seen: Set<String> = []
        for keyword in response.data {
            try ASCNonIdempotentWriteRecovery.validateResourceIdentity(
                type: keyword.type,
                id: keyword.id,
                expectedType: "appKeywords",
                context: "app search keyword response"
            )
            guard seen.insert(keyword.id).inserted else {
                throw AppSearchKeywordArgumentError("Apple returned a duplicate app search keyword ID")
            }
        }
        let nextRequest = try response.links.next.map { next in
            try httpClient.validatedScopedLink(
                next,
                scope: PaginationScope.strict(path: expectedPath, query: expectedQuery)
            )
        }
        if let meta = response.meta {
            guard let paging = meta.paging,
                  let pageLimit = paging.limit,
                  pageLimit > 0,
                  pageLimit <= requestedLimit,
                  pageLimit >= response.data.count else {
                throw AppSearchKeywordArgumentError("Apple returned invalid app search keyword paging metadata")
            }
            if let total = paging.total, total < response.data.count {
                throw AppSearchKeywordArgumentError("Apple returned app search keyword total below the page count")
            }
            if let cursor = paging.nextCursor {
                guard !cursor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      nextRequest?.parameters["cursor"] == cursor else {
                    throw AppSearchKeywordArgumentError("Apple returned inconsistent app search keyword cursor metadata")
                }
            }
        }
    }

    func validateAppSearchKeywordLink(_ value: String, expectedPath: String) throws {
        do {
            _ = try httpClient.validatedScopedLink(
                value,
                scope: PaginationScope(path: expectedPath)
            )
        } catch {
            throw AppSearchKeywordArgumentError("Apple returned an invalid app search keyword links.self")
        }
    }
}

private struct AppSearchKeywordArgumentError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
