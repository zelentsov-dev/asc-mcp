//
//  ReviewsWorker.swift
//  asc-mcp
//
//  Customer Reviews management for App Store Connect
//

import Foundation
import MCP

/// Worker for managing customer reviews from App Store Connect
public final class ReviewsWorker: Sendable {
    let httpClient: HTTPClient
    
    public init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }
    
    /// Get all available tools for reviews management
    public func getTools() async -> [Tool] {
        return [
            createReviewsListTool(),
            createReviewsGetTool(),
            createReviewsListForVersionTool(),
            createReviewsStatsTool(),
            createReviewsCreateResponseTool(),
            createReviewsDeleteResponseTool(),
            createReviewsGetResponseTool()
        ]
    }
    
    /// Handle tool call for reviews operations
    public func handleTool(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        switch params.name {
        case "reviews_list":
            return try await handleReviewsList(params)
        case "reviews_get":
            return try await handleReviewsGet(params)
        case "reviews_list_for_version":
            return try await handleReviewsListForVersion(params)
        case "reviews_stats":
            return try await handleReviewsStats(params)
        case "reviews_create_response":
            return try await handleReviewsCreateResponse(params)
        case "reviews_delete_response":
            return try await handleReviewsDeleteResponse(params)
        case "reviews_get_response":
            return try await handleReviewsGetResponse(params)
        default:
            throw MCPError.methodNotFound("Unknown tool: \(params.name)")
        }
    }
}

// MARK: - Review Models
extension ReviewsWorker {
    /// Customer review data structure
    struct CustomerReview: Codable, Sendable {
        let id: String
        let type: String
        let attributes: ReviewAttributes
        let relationships: ReviewRelationships?
        let links: ResourceLinks?
    }
    
    struct ReviewAttributes: Codable, Sendable {
        let rating: Int
        let title: String?
        let body: String?
        let reviewerNickname: String
        let createdDate: String
        let territory: String?
    }
    
    struct ReviewRelationships: Codable, Sendable {
        let response: ResponseData?
    }
    
    struct ResponseData: Codable, Sendable {
        let data: ResponseDataItem?
    }
    
    struct ResponseDataItem: Codable, Sendable {
        let id: String
        let type: String
    }
    
    struct ResourceLinks: Codable, Sendable {
        let `self`: String?
        let related: String?
    }
    
    /// Reviews API response
    struct ReviewsResponse: Codable, Sendable {
        let data: [CustomerReview]
        let links: PageLinks?
        let meta: PagingInformation?
    }
    
    struct PageLinks: Codable, Sendable {
        let `self`: String
        let first: String?
        let next: String?
    }
    
    struct PagingInformation: Codable, Sendable {
        let paging: Paging
    }
    
    struct Paging: Codable, Sendable {
        let total: Int
        let limit: Int
    }
    
    /// Review statistics
    struct ReviewStats: Codable, Sendable {
        let totalCount: Int
        let averageRating: Double
        let ratingDistribution: [Int: Int]
        let periodStart: String?
        let periodEnd: String?
        let topTerritories: [TerritoryStats]?
    }
    
    struct TerritoryStats: Codable, Sendable {
        let territory: String
        let count: Int
        let averageRating: Double
    }
    
    /// Customer review response data structure
    struct CustomerReviewResponse: Codable, Sendable {
        let id: String
        let type: String
        let attributes: ResponseAttributes
        let relationships: ResponseRelationships?
    }
    
    struct ResponseAttributes: Codable, Sendable {
        let responseBody: String
        let createdDate: String?
        let modifiedDate: String?
        let state: String?
    }
    
    struct ResponseRelationships: Codable, Sendable {
        let review: ReviewReference?
    }
    
    struct ReviewReference: Codable, Sendable {
        let data: ReviewReferenceData?
    }
    
    struct ReviewReferenceData: Codable, Sendable {
        let id: String
        let type: String
    }
    
    /// Response API response
    struct ReviewResponseData: Codable, Sendable {
        let data: CustomerReviewResponse
    }
}

// MARK: - Request Models
extension ReviewsWorker {
    /// Request body for creating a developer response to a review
    struct CreateReviewResponseRequest: Encodable, Sendable {
        let data: RequestData

        struct RequestData: Encodable, Sendable {
            let type = "customerReviewResponses"
            let attributes: Attributes
            let relationships: Relationships
        }

        struct Attributes: Encodable, Sendable {
            let responseBody: String
        }

        struct Relationships: Encodable, Sendable {
            let review: ReviewRelation
        }

        struct ReviewRelation: Encodable, Sendable {
            let data: ResourceId
        }

        struct ResourceId: Encodable, Sendable {
            let type: String
            let id: String
        }
    }

}

// MARK: - Formatting Helpers
extension ReviewsWorker {
    /// Format a review as a dictionary for JSON output
    func formatReviewDict(_ review: CustomerReview) -> [String: Any] {
        var dict: [String: Any] = [
            "id": review.id,
            "rating": review.attributes.rating,
            "reviewer": review.attributes.reviewerNickname,
            "created_date": review.attributes.createdDate
        ]
        if let title = review.attributes.title {
            dict["title"] = title
        }
        if let body = review.attributes.body {
            dict["body"] = body
        }
        if let territory = review.attributes.territory {
            dict["territory"] = territory
        }
        dict["has_response"] = review.relationships?.response?.data != nil
        return dict
    }

    /// Format a developer response as a dictionary for JSON output
    func formatResponseDict(_ response: CustomerReviewResponse) -> [String: Any] {
        var dict: [String: Any] = [
            "id": response.id,
            "response_body": response.attributes.responseBody
        ]
        if let created = response.attributes.createdDate {
            dict["created_date"] = created
        }
        if let modified = response.attributes.modifiedDate {
            dict["modified_date"] = modified
        }
        if let state = response.attributes.state {
            dict["state"] = state
        }
        return dict
    }
}