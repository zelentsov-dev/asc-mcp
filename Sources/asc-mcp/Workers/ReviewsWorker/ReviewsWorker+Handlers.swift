//
//  ReviewsWorker+Handlers.swift
//  asc-mcp
//
//  Implementation of customer reviews handlers
//

import Foundation
import MCP

extension ReviewsWorker {

    private struct ReviewCollectionOptions {
        let queryParameters: [String: String]
        let requiredParameters: [String: String]
    }

    private struct ReviewLookupResponse: Codable, Sendable {
        let data: CustomerReview
    }

    private struct ReviewExistenceResponse: Codable, Sendable {
        let data: Resource

        struct Resource: Codable, Sendable {
            let id: String
            let type: String
        }
    }

    private struct TerritoryAccumulator {
        var count = 0
        var ratingTotal = 0
    }

    private struct StreamedReviewStats {
        let stats: ReviewStats
        let reviewsScanned: Int
        let uniqueReviewsScanned: Int
        let duplicatesSkipped: Int
        let pagesFetched: Int
    }

    private func loadReviewStats(
        appId: String,
        territory: String?,
        hasPublishedResponse: Bool?,
        startDate: Date?,
        now: Date
    ) async throws -> StreamedReviewStats {
        let endpoint = "/v1/apps/\(try ASCPathSegment.encode(appId))/customerReviews"
        var parameters: [String: String] = [
            "limit": "200",
            "sort": "-createdDate"
        ]
        if let territory, territory != "all" {
            parameters["filter[territory]"] = territory
        }
        if let hasPublishedResponse {
            parameters["exists[publishedResponse]"] = String(hasPublishedResponse)
        }

        var seenReviewIDs: Set<String> = []
        var reviewsScanned = 0
        var uniqueReviewsScanned = 0
        var duplicatesSkipped = 0
        var pagesFetched = 0
        var seenNextURLs: Set<String> = []
        var totalCount = 0
        var totalRating = 0
        var ratingDistribution = Dictionary(uniqueKeysWithValues: (1...5).map { ($0, 0) })
        var territories: [String: TerritoryAccumulator] = [:]
        var nextURL: String?
        var requiredParameters = parameters
        requiredParameters.removeValue(forKey: "limit")
        let scope = PaginationScope(path: endpoint, requiredParameters: requiredParameters)

        while true {
            let response: Data
            if let nextURL {
                response = try await httpClient.getPage(nextURL, scope: scope)
            } else {
                response = try await httpClient.get(endpoint, parameters: parameters)
            }
            let page = try parseReviewsResponse(data: response)
            pagesFetched += 1
            reviewsScanned += page.data.count

            let oldestDate = page.data.compactMap { parseReviewDate($0.attributes.createdDate) }.min()
            for review in page.data {
                guard seenReviewIDs.insert(review.id).inserted else {
                    duplicatesSkipped += 1
                    continue
                }
                uniqueReviewsScanned += 1

                if let startDate {
                    guard let reviewDate = parseReviewDate(review.attributes.createdDate),
                          reviewDate >= startDate,
                          reviewDate <= now else {
                        continue
                    }
                }

                totalCount += 1
                totalRating += review.attributes.rating
                ratingDistribution[review.attributes.rating, default: 0] += 1
                let reviewTerritory = review.attributes.territory ?? "Unknown"
                territories[reviewTerritory, default: TerritoryAccumulator()].count += 1
                territories[reviewTerritory, default: TerritoryAccumulator()].ratingTotal += review.attributes.rating
            }

            if let startDate,
               let oldestDate,
               oldestDate < startDate {
                break
            }

            guard let next = page.links?.next else { break }
            guard seenNextURLs.insert(next).inserted else {
                throw ASCError.parsing("Customer reviews pagination returned a repeated next URL")
            }
            nextURL = next
        }

        let averageRating = totalCount > 0 ? Double(totalRating) / Double(totalCount) : 0
        var territoryStats: [TerritoryStats] = []
        territoryStats.reserveCapacity(territories.count)
        for (territory, aggregate) in territories {
            territoryStats.append(
                TerritoryStats(
                    territory: territory,
                    count: aggregate.count,
                    averageRating: Double(aggregate.ratingTotal) / Double(aggregate.count)
                )
            )
        }
        territoryStats.sort {
            $0.count == $1.count ? $0.territory < $1.territory : $0.count > $1.count
        }
        let topTerritories = Array(territoryStats.prefix(5))

        return StreamedReviewStats(
            stats: ReviewStats(
                totalCount: totalCount,
                averageRating: averageRating,
                ratingDistribution: ratingDistribution,
                periodStart: startDate.map { ISO8601DateFormatter().string(from: $0) },
                periodEnd: ISO8601DateFormatter().string(from: now),
                topTerritories: topTerritories.isEmpty ? nil : topTerritories
            ),
            reviewsScanned: reviewsScanned,
            uniqueReviewsScanned: uniqueReviewsScanned,
            duplicatesSkipped: duplicatesSkipped,
            pagesFetched: pagesFetched
        )
    }

    private func reviewCollectionOptions(arguments: [String: Value]) throws -> ReviewCollectionOptions {
        let limit: Int
        if let value = arguments["limit"] {
            guard let parsed = value.intValue, (1...200).contains(parsed) else {
                throw ASCError.parsing("limit must be an integer from 1 through 200")
            }
            limit = parsed
        } else {
            limit = 100
        }

        let sort = try reviewSort(arguments["sort"])

        let ratings = try reviewRatings(arguments: arguments)
        let territories = try reviewTerritories(arguments: arguments)
        let includeResponse = try optionalBool(arguments["include_response"], name: "include_response")
        let hasPublishedResponse = try optionalBool(
            arguments["has_published_response"],
            name: "has_published_response"
        )

        var query: [String: String] = [
            "limit": String(limit),
            "sort": sort.joined(separator: ",")
        ]
        if let ratings {
            query["filter[rating]"] = ratings.map(String.init).joined(separator: ",")
        }
        if let territories {
            query["filter[territory]"] = territories.joined(separator: ",")
        }
        if includeResponse == true {
            query["include"] = "response"
        }
        if let hasPublishedResponse {
            query["exists[publishedResponse]"] = String(hasPublishedResponse)
        }

        var required = query
        required.removeValue(forKey: "limit")
        return ReviewCollectionOptions(queryParameters: query, requiredParameters: required)
    }

    private func reviewSort(_ value: Value?) throws -> [String] {
        guard let value else {
            return ["-createdDate"]
        }

        let values: [String]
        if let scalar = value.stringValue {
            values = [scalar]
        } else if let array = value.arrayValue {
            let strings = array.compactMap(\.stringValue)
            guard strings.count == array.count else {
                throw ASCError.parsing("sort must be a string or an array containing only strings")
            }
            values = strings
        } else {
            throw ASCError.parsing("sort must be a string or an array of strings")
        }

        guard !values.isEmpty else {
            throw ASCError.parsing("sort must contain at least one value")
        }
        guard values.allSatisfy({ value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed == value
        }) else {
            throw ASCError.parsing("sort must contain only non-empty strings without surrounding whitespace")
        }
        guard Set(values).count == values.count else {
            throw ASCError.parsing("sort must not contain duplicate values")
        }
        let allowedValues = Set(Self.supportedReviewSorts)
        let unsupported = values.filter { !allowedValues.contains($0) }
        guard unsupported.isEmpty else {
            throw ASCError.parsing("Unsupported sort value(s): \(unsupported.joined(separator: ", "))")
        }
        return values
    }

    private func reviewRatings(arguments: [String: Value]) throws -> [Int]? {
        if arguments["rating"] != nil, arguments["ratings"] != nil {
            throw ASCError.parsing("Provide rating or ratings, not both")
        }
        if let value = arguments["rating"] {
            guard let rating = value.intValue, (1...5).contains(rating) else {
                throw ASCError.parsing("rating must be an integer from 1 through 5")
            }
            return [rating]
        }
        guard let value = arguments["ratings"] else {
            return nil
        }
        guard let values = value.arrayValue, !values.isEmpty else {
            throw ASCError.parsing("ratings must be a non-empty array")
        }
        let ratings = values.compactMap(\.intValue)
        guard ratings.count == values.count, ratings.allSatisfy({ (1...5).contains($0) }) else {
            throw ASCError.parsing("ratings must contain only integers from 1 through 5")
        }
        guard Set(ratings).count == ratings.count else {
            throw ASCError.parsing("ratings must not contain duplicates")
        }
        return ratings
    }

    private func reviewTerritories(arguments: [String: Value]) throws -> [String]? {
        if arguments["territory"] != nil, arguments["territories"] != nil {
            throw ASCError.parsing("Provide territory or territories, not both")
        }
        if let value = arguments["territory"] {
            guard let rawTerritory = value.stringValue,
                  let territory = normalizedReviewTerritory(rawTerritory) else {
                throw ASCError.parsing("territory must be a three-letter ISO 3166-1 alpha-3 code")
            }
            return [territory]
        }
        guard let value = arguments["territories"] else {
            return nil
        }
        guard let values = value.arrayValue, !values.isEmpty else {
            throw ASCError.parsing("territories must be a non-empty array")
        }
        let rawTerritories = values.compactMap(\.stringValue)
        guard rawTerritories.count == values.count else {
            throw ASCError.parsing("territories must contain only strings")
        }
        let territories = rawTerritories.compactMap(normalizedReviewTerritory)
        guard territories.count == rawTerritories.count else {
            throw ASCError.parsing("territories must contain only three-letter ISO 3166-1 alpha-3 codes")
        }
        guard Set(territories).count == territories.count else {
            throw ASCError.parsing("territories must not contain duplicates")
        }
        return territories
    }

    private func normalizedReviewTerritory(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
            return nil
        }
        return normalized
    }

    private func optionalBool(_ value: Value?, name: String) throws -> Bool? {
        guard let value else {
            return nil
        }
        guard let result = value.boolValue else {
            throw ASCError.parsing("\(name) must be a boolean")
        }
        return result
    }

    private func includedResponsesByID(_ response: ReviewsResponse) -> [String: CustomerReviewResponse] {
        var responses: [String: CustomerReviewResponse] = [:]
        for item in response.included ?? [] where item.type == "customerReviewResponses" {
            responses[item.id] = item
        }
        return responses
    }

    /// Lists customer reviews for an app with filtering and pagination
    /// - Returns: JSON with reviews array and pagination info
    func handleReviewsList(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let options = try reviewCollectionOptions(arguments: arguments)
            let endpoint = "/v1/apps/\(try ASCPathSegment.encode(appId))/customerReviews"
            let response: Data
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(
                        path: endpoint,
                        requiredParameters: options.requiredParameters
                    )
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: options.queryParameters)
            }

            let reviewsResponse = try parseReviewsResponse(data: response)
            let includedResponses = includedResponsesByID(reviewsResponse)
            let reviews = reviewsResponse.data.map {
                formatReviewDict($0, includedResponses: includedResponses)
            }
            var result: [String: Any] = [
                "success": true,
                "reviews": reviews,
                "count": reviewsResponse.data.count
            ]
            if let next = reviewsResponse.links?.next {
                result["next_url"] = next
            }
            if let total = reviewsResponse.meta?.paging.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list reviews: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets detailed information about a specific customer review
    /// - Returns: JSON with review details
    func handleReviewsGet(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let reviewIdValue = arguments["review_id"],
              let reviewId = reviewIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'review_id' is missing")],
                isError: true
            )
        }

        do {
            let reviewResponse: ReviewLookupResponse = try await httpClient.get(
                "/v1/customerReviews/\(try ASCPathSegment.encode(reviewId))",
                as: ReviewLookupResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "review": formatReviewDict(reviewResponse.data)
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get review: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists customer reviews for a specific app version
    /// - Returns: JSON with reviews array and pagination info
    func handleReviewsListForVersion(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let versionIdValue = arguments["version_id"],
              let versionId = versionIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'version_id' is missing")],
                isError: true
            )
        }

        do {
            let options = try reviewCollectionOptions(arguments: arguments)
            let endpoint = "/v1/appStoreVersions/\(try ASCPathSegment.encode(versionId))/customerReviews"
            let response: Data
            if let nextUrl = try paginationURL(from: arguments["next_url"]) {
                response = try await httpClient.getPage(
                    nextUrl,
                    scope: PaginationScope(
                        path: endpoint,
                        requiredParameters: options.requiredParameters
                    )
                )
            } else {
                response = try await httpClient.get(endpoint, parameters: options.queryParameters)
            }

            let reviewsResponse = try parseReviewsResponse(data: response)
            let includedResponses = includedResponsesByID(reviewsResponse)
            let reviews = reviewsResponse.data.map {
                formatReviewDict($0, includedResponses: includedResponses)
            }
            var result: [String: Any] = [
                "success": true,
                "reviews": reviews,
                "count": reviewsResponse.data.count
            ]
            if let next = reviewsResponse.links?.next {
                result["next_url"] = next
            }
            if let total = reviewsResponse.meta?.paging.total {
                result["total"] = total
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to list reviews for version: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets aggregated statistics for customer reviews
    /// - Returns: JSON with review statistics including rating distribution
    func handleReviewsStats(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let rawAppId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        let appId = rawAppId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !appId.isEmpty else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'app_id' must not be empty")],
                isError: true
            )
        }

        let requestedPeriod = arguments["period"]?.stringValue ?? "last_month"
        guard let period = normalizeReviewPeriod(requestedPeriod) else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Unsupported period '\(requestedPeriod)'. Use last_week, last_month, last_3_months, or all_time")],
                isError: true
            )
        }
        let territory: String?
        if let rawTerritory = arguments["territory"]?.stringValue {
            if rawTerritory.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "all" {
                territory = "all"
            } else if let normalized = normalizedReviewTerritory(rawTerritory) {
                territory = normalized
            } else {
                return CallTool.Result(
                    content: [MCPContent.text("Error: territory must be 'all' or a three-letter ISO 3166-1 alpha-3 code")],
                    isError: true
                )
            }
        } else {
            territory = nil
        }
        let hasPublishedResponse: Bool?
        if let value = arguments["has_published_response"] {
            guard let parsed = value.boolValue else {
                return CallTool.Result(
                    content: [MCPContent.text("Error: has_published_response must be a boolean")],
                    isError: true
                )
            }
            hasPublishedResponse = parsed
        } else {
            hasPublishedResponse = nil
        }
        let now = Date()
        let startDate = reviewPeriodStart(for: period, now: now)

        do {
            let collection = try await loadReviewStats(
                appId: appId,
                territory: territory,
                hasPublishedResponse: hasPublishedResponse,
                startDate: startDate,
                now: now
            )
            let stats = collection.stats

            var ratingDist: [String: Any] = [:]
            for (key, value) in stats.ratingDistribution {
                ratingDist[String(key)] = value
            }

            var result: [String: Any] = [
                "success": true,
                "period": period,
                "total_in_sample": stats.totalCount,
                "total_in_period": stats.totalCount,
                "reviews_scanned": collection.reviewsScanned,
                "unique_reviews_scanned": collection.uniqueReviewsScanned,
                "duplicates_skipped": collection.duplicatesSkipped,
                "pages_fetched": collection.pagesFetched,
                "complete": true,
                "average_rating": Double(String(format: "%.2f", stats.averageRating)) ?? stats.averageRating,
                "rating_distribution": ratingDist
            ]

            if let periodStart = stats.periodStart {
                result["period_start"] = periodStart
            }
            if let periodEnd = stats.periodEnd {
                result["period_end"] = periodEnd
            }

            if let territory = territory {
                result["territory"] = territory
            }
            if let hasPublishedResponse {
                result["has_published_response"] = hasPublishedResponse
            }

            if let topTerritories = stats.topTerritories {
                result["top_territories"] = topTerritories.map { t in
                    [
                        "territory": t.territory,
                        "count": t.count,
                        "average_rating": Double(String(format: "%.2f", t.averageRating)) ?? t.averageRating
                    ] as [String: Any]
                }
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get review stats: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates a developer response to a customer review
    /// - Returns: JSON with created response details
    func handleReviewsCreateResponse(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let reviewIdValue = arguments["review_id"],
              let reviewId = reviewIdValue.stringValue,
              let responseBodyValue = arguments["response_body"],
              let responseBody = responseBodyValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameters 'review_id' and 'response_body' are missing")],
                isError: true
            )
        }

        if responseBody.count > 5000 {
            return CallTool.Result(
                content: [MCPContent.text("Error: Response body exceeds 5000 characters limit")],
                isError: true
            )
        }

        do {
            let request = CreateReviewResponseRequest(
                data: CreateReviewResponseRequest.RequestData(
                    attributes: CreateReviewResponseRequest.Attributes(
                        responseBody: responseBody
                    ),
                    relationships: CreateReviewResponseRequest.Relationships(
                        review: CreateReviewResponseRequest.ReviewRelation(
                            data: CreateReviewResponseRequest.ResourceId(
                                type: "customerReviews",
                                id: reviewId
                            )
                        )
                    )
                )
            )

            let bodyData = try JSONEncoder().encode(request)
            let responseRaw = try await httpClient.post("/v1/customerReviewResponses", body: bodyData)
            let responseData = try JSONDecoder().decode(ReviewResponseData.self, from: responseRaw)

            let result: [String: Any] = [
                "success": true,
                "response": formatResponseDict(responseData.data)
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to create response: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Deletes a developer response to a customer review
    /// - Returns: JSON confirmation of deletion
    func handleReviewsDeleteResponse(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let responseIdValue = arguments["response_id"],
              let responseId = responseIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'response_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/customerReviewResponses/\(try ASCPathSegment.encode(responseId))")

            let result: [String: Any] = [
                "success": true,
                "message": "Response '\(responseId)' deleted"
            ]

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to delete response: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets developer response for a specific review
    /// - Returns: JSON with response details or message if no response exists
    func handleReviewsGetResponse(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let reviewIdValue = arguments["review_id"],
              let reviewId = reviewIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'review_id' is missing")],
                isError: true
            )
        }

        do {
            let responseData: ReviewResponseData = try await httpClient.get(
                "/v1/customerReviews/\(try ASCPathSegment.encode(reviewId))/response",
                as: ReviewResponseData.self
            )

            let result: [String: Any] = [
                "success": true,
                "has_response": true,
                "response": formatResponseDict(responseData.data)
            ]

            return MCPResult.jsonObject(result)

        } catch let error as ASCError {
            switch error {
            case .api(_, 404), .apiResponse(_, 404):
                do {
                    let parent: ReviewExistenceResponse = try await httpClient.get(
                        "/v1/customerReviews/\(try ASCPathSegment.encode(reviewId))",
                        as: ReviewExistenceResponse.self
                    )
                    guard parent.data.id == reviewId,
                          parent.data.type == "customerReviews" else {
                        throw ASCError.parsing("Parent review lookup returned an unexpected resource")
                    }
                } catch {
                    return CallTool.Result(
                        content: [MCPContent.text("Error: Failed to verify review after response lookup returned 404: \(error.localizedDescription)")],
                        isError: true
                    )
                }
                return MCPResult.jsonObject([
                    "success": true,
                    "has_response": false,
                    "message": "No developer response found for this review"
                ])
            default:
                return CallTool.Result(
                    content: [MCPContent.text("Error: Failed to get response: \(error.localizedDescription)")],
                    isError: true
                )
            }
        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get response: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets AI-generated summaries of customer reviews
    /// - Returns: JSON with review summarizations
    func handleReviewsSummarizations(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [MCPContent.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let platform = arguments["platform"]?.stringValue ?? "IOS"
            let allowedPlatforms: Set<String> = ["IOS", "MAC_OS", "TV_OS", "VISION_OS"]
            guard allowedPlatforms.contains(platform) else {
                throw ASCError.parsing("platform must be IOS, MAC_OS, TV_OS, or VISION_OS")
            }
            let limit: Int
            if let value = arguments["limit"] {
                guard let parsed = value.intValue, (1...200).contains(parsed) else {
                    throw ASCError.parsing("limit must be an integer from 1 through 200")
                }
                limit = parsed
            } else {
                limit = 25
            }

            let endpoint = "/v1/apps/\(try ASCPathSegment.encode(appId))/customerReviewSummarizations"
            var queryParams: [String: String] = [
                "filter[platform]": platform,
                "limit": String(limit)
            ]
            if let rawTerritoryID = arguments["territory_id"]?.stringValue {
                let territoryID = rawTerritoryID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !territoryID.isEmpty else {
                    throw ASCError.parsing("territory_id must not be empty")
                }
                queryParams["filter[territory]"] = territoryID
            }

            var requiredParameters = queryParams
            requiredParameters.removeValue(forKey: "limit")
            let responseData: Data
            if let nextURL = try paginationURL(from: arguments["next_url"]) {
                responseData = try await httpClient.getPage(
                    nextURL,
                    scope: PaginationScope(path: endpoint, requiredParameters: requiredParameters)
                )
            } else {
                responseData = try await httpClient.get(endpoint, parameters: queryParams)
            }

            let response = try JSONDecoder().decode(PassthroughAPIResponse.self, from: responseData)

            var result: [String: Any] = [
                "success": true,
                "summarizations": response.data.asAny
            ]

            if case .object(let linksObj) = response.links,
               case .string(let nextUrl) = linksObj["next"] {
                result["next_url"] = nextUrl
            }

            return MCPResult.jsonObject(result)

        } catch {
            return CallTool.Result(
                content: [MCPContent.text("Error: Failed to get review summarizations: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
}
