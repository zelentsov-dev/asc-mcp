//
//  ReviewsWorker+Handlers.swift
//  asc-mcp
//
//  Implementation of customer reviews handlers
//

import Foundation
import MCP

extension ReviewsWorker {

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
        startDate: Date?,
        now: Date
    ) async throws -> StreamedReviewStats {
        var endpoint = "/v1/apps/\(appId)/customerReviews"
        var parameters: [String: String] = [
            "limit": "200",
            "sort": "-createdDate"
        ]
        if let territory, territory != "all" {
            parameters["filter[territory]"] = territory
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

        while true {
            let response = try await httpClient.get(endpoint, parameters: parameters)
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

            guard let nextURL = page.links?.next else { break }
            guard seenNextURLs.insert(nextURL).inserted else {
                throw ASCError.parsing("Customer reviews pagination returned a repeated next URL")
            }
            guard let nextPage = await httpClient.parsePaginationUrl(nextURL) else {
                throw ASCError.parsing("Customer reviews pagination returned an invalid next URL")
            }
            endpoint = nextPage.path
            parameters = nextPage.parameters
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

        let limit = arguments["limit"]?.intValue ?? 100
        let rating = arguments["rating"]?.intValue
        let territory = arguments["territory"]?.stringValue
        let sort = arguments["sort"]?.stringValue ?? "-createdDate"
        let includeResponse = arguments["include_response"]?.boolValue ?? false

        do {
            let response: Data

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = await httpClient.parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters)
            } else {
                var queryParams: [String: String] = [
                    "limit": String(min(max(limit, 1), 200)),
                    "sort": sort
                ]
                if let rating = rating {
                    queryParams["filter[rating]"] = String(rating)
                }
                if let territory = territory {
                    queryParams["filter[territory]"] = territory
                }
                if includeResponse {
                    queryParams["include"] = "response"
                }
                response = try await httpClient.get("/v1/apps/\(appId)/customerReviews", parameters: queryParams)
            }

            let reviewsResponse = try parseReviewsResponse(data: response)

            let reviews = reviewsResponse.data.map { formatReviewDict($0) }
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
            struct SingleReviewResponse: Codable {
                let data: CustomerReview
            }

            let reviewResponse: SingleReviewResponse = try await httpClient.get(
                "/v1/customerReviews/\(reviewId)",
                as: SingleReviewResponse.self
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

        let limit = arguments["limit"]?.intValue ?? 100
        let rating = arguments["rating"]?.intValue
        let territory = arguments["territory"]?.stringValue
        let sort = arguments["sort"]?.stringValue ?? "-createdDate"
        let includeResponse = arguments["include_response"]?.boolValue ?? false

        do {
            let response: Data

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = await httpClient.parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters)
            } else {
                var queryParams: [String: String] = [
                    "limit": String(min(max(limit, 1), 200)),
                    "sort": sort
                ]
                if let rating = rating {
                    queryParams["filter[rating]"] = String(rating)
                }
                if let territory = territory {
                    queryParams["filter[territory]"] = territory
                }
                if includeResponse {
                    queryParams["include"] = "response"
                }
                response = try await httpClient.get("/v1/appStoreVersions/\(versionId)/customerReviews", parameters: queryParams)
            }

            let reviewsResponse = try parseReviewsResponse(data: response)

            let reviews = reviewsResponse.data.map { formatReviewDict($0) }
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
        let territory = arguments["territory"]?.stringValue
        let now = Date()
        let startDate = reviewPeriodStart(for: period, now: now)

        do {
            let collection = try await loadReviewStats(
                appId: appId,
                territory: territory,
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
            _ = try await httpClient.delete("/v1/customerReviewResponses/\(responseId)")

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
            struct ReviewWithResponseData: Codable {
                let data: CustomerReview
                let included: [CustomerReviewResponse]?
            }

            let reviewWithResponse: ReviewWithResponseData = try await httpClient.get(
                "/v1/customerReviews/\(reviewId)",
                parameters: ["include": "response"],
                as: ReviewWithResponseData.self
            )

            guard let responseData = reviewWithResponse.included?.first else {
                let result: [String: Any] = [
                    "success": true,
                    "has_response": false,
                    "message": "No developer response found for this review"
                ]
                return MCPResult.jsonObject(result)
            }

            let result: [String: Any] = [
                "success": true,
                "has_response": true,
                "response": formatResponseDict(responseData)
            ]

            return MCPResult.jsonObject(result)

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
            var queryParams: [String: String] = [
                "filter[platform]": arguments["platform"]?.stringValue ?? "IOS"
            ]

            if let limit = arguments["limit"]?.intValue {
                queryParams["limit"] = String(min(max(limit, 1), 200))
            } else {
                queryParams["limit"] = "25"
            }

            let responseData = try await httpClient.get(
                "/v1/apps/\(appId)/customerReviewSummarizations",
                parameters: queryParams
            )

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
