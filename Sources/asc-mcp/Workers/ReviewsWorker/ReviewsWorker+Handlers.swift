//
//  ReviewsWorker+Handlers.swift
//  asc-mcp
//
//  Implementation of customer reviews handlers
//

import Foundation
import MCP

extension ReviewsWorker {

    /// Lists customer reviews for an app with filtering and pagination
    /// - Returns: JSON with reviews array and pagination info
    func handleReviewsList(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'app_id' is missing")],
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
               let parsed = parsePaginationUrl(nextUrl) {
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list reviews: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'review_id' is missing")],
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get review: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'version_id' is missing")],
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
               let parsed = parsePaginationUrl(nextUrl) {
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to list reviews for version: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets aggregated statistics for customer reviews
    /// - Returns: JSON with review statistics including rating distribution
    func handleReviewsStats(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Error: Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        let period = arguments["period"]?.stringValue ?? "last_month"
        let territory = arguments["territory"]?.stringValue

        var queryParams: [String: String] = [
            "limit": "200",
            "sort": "-createdDate"
        ]

        if let territory = territory, territory != "all" {
            queryParams["filter[territory]"] = territory
        }

        do {
            let response = try await httpClient.get("/v1/apps/\(appId)/customerReviews", parameters: queryParams)
            let reviewsResponse = try parseReviewsResponse(data: response)
            let stats = calculateStats(from: reviewsResponse.data, period: period)

            var ratingDist: [String: Any] = [:]
            for (key, value) in stats.ratingDistribution {
                ratingDist[String(key)] = value
            }

            var result: [String: Any] = [
                "success": true,
                "period": period,
                "total_in_sample": stats.totalCount,
                "average_rating": Double(String(format: "%.2f", stats.averageRating)) ?? stats.averageRating,
                "rating_distribution": ratingDist
            ]

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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get review stats: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameters 'review_id' and 'response_body' are missing")],
                isError: true
            )
        }

        if responseBody.count > 5000 {
            return CallTool.Result(
                content: [.text("Error: Response body exceeds 5000 characters limit")],
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

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to create response: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'response_id' is missing")],
                isError: true
            )
        }

        do {
            _ = try await httpClient.delete("/v1/customerReviewResponses/\(responseId)")

            let result: [String: Any] = [
                "success": true,
                "message": "Response '\(responseId)' deleted"
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to delete response: \(error.localizedDescription)")],
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
                content: [.text("Error: Required parameter 'review_id' is missing")],
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
                return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
            }

            let result: [String: Any] = [
                "success": true,
                "has_response": true,
                "response": formatResponseDict(responseData)
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Error: Failed to get response: \(error.localizedDescription)")],
                isError: true
            )
        }
    }
}
