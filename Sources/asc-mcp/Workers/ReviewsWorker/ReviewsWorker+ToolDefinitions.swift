//
//  ReviewsWorker+ToolDefinitions.swift
//  asc-mcp
//
//  Tool definitions for customer reviews operations
//

import Foundation
import MCP

extension ReviewsWorker {
    /// Creates tool definition for listing customer reviews
    func createReviewsListTool() -> Tool {
        return Tool(
            name: "reviews_list",
            description: "Get customer reviews for an app with filtering and pagination support",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of reviews to return (1-200, default: 100)")
                    ]),
                    "rating": .object([
                        "type": .string("integer"),
                        "description": .string("Filter by rating (1-5)")
                    ]),
                    "territory": .object([
                        "type": .string("string"),
                        "description": .string("Filter by territory code (e.g., US, RU, DE)")
                    ]),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Sort order: -createdDate (newest first), createdDate, rating, -rating")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("URL for next page of results (from previous response)")
                    ]),
                    "include_response": .object([
                        "type": .string("boolean"),
                        "description": .string("Include developer responses inline with reviews (default: false)")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    /// Creates tool definition for getting a specific review
    func createReviewsGetTool() -> Tool {
        return Tool(
            name: "reviews_get",
            description: "Get detailed information about a specific customer review",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "review_id": .object([
                        "type": .string("string"),
                        "description": .string("Customer review ID")
                    ])
                ]),
                "required": .array([.string("review_id")])
            ])
        )
    }
    
    /// Creates tool definition for listing reviews for a specific app version
    func createReviewsListForVersionTool() -> Tool {
        return Tool(
            name: "reviews_list_for_version",
            description: "Get customer reviews for a specific app version",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "version_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store version ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of reviews to return (1-200, default: 100)")
                    ]),
                    "rating": .object([
                        "type": .string("integer"),
                        "description": .string("Filter by rating (1-5)")
                    ]),
                    "territory": .object([
                        "type": .string("string"),
                        "description": .string("Filter by territory code (e.g., US, RU, DE)")
                    ]),
                    "sort": .object([
                        "type": .string("string"),
                        "description": .string("Sort order: -createdDate (newest first), createdDate, rating, -rating")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("URL for next page of results (from previous response)")
                    ]),
                    "include_response": .object([
                        "type": .string("boolean"),
                        "description": .string("Include developer responses inline with reviews (default: false)")
                    ])
                ]),
                "required": .array([.string("version_id")])
            ])
        )
    }

    /// Creates tool definition for getting review statistics
    func createReviewsStatsTool() -> Tool {
        return Tool(
            name: "reviews_stats",
            description: "Get aggregated statistics for customer reviews without loading all reviews",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "period": .object([
                        "type": .string("string"),
                        "description": .string("Time period: last_week, last_month, last_3_months, all_time")
                    ]),
                    "territory": .object([
                        "type": .string("string"),
                        "description": .string("Filter by territory code (e.g., US, RU, DE) or 'all' for all territories")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }
    
    /// Creates tool definition for creating a response to a review
    func createReviewsCreateResponseTool() -> Tool {
        return Tool(
            name: "reviews_create_response",
            description: "Create a developer response to a customer review",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "review_id": .object([
                        "type": .string("string"),
                        "description": .string("Customer review ID to respond to")
                    ]),
                    "response_body": .object([
                        "type": .string("string"),
                        "description": .string("Developer response text (max 5000 characters)")
                    ])
                ]),
                "required": .array([.string("review_id"), .string("response_body")])
            ])
        )
    }
    
    /// Creates tool definition for deleting a review response
    func createReviewsDeleteResponseTool() -> Tool {
        return Tool(
            name: "reviews_delete_response",
            description: "Delete a developer response to a customer review",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "response_id": .object([
                        "type": .string("string"),
                        "description": .string("Review response ID to delete")
                    ])
                ]),
                "required": .array([.string("response_id")])
            ])
        )
    }
    
    /// Creates tool definition for getting a review response
    func createReviewsGetResponseTool() -> Tool {
        return Tool(
            name: "reviews_get_response",
            description: "Get developer response for a specific review",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "review_id": .object([
                        "type": .string("string"),
                        "description": .string("Customer review ID to get response for")
                    ])
                ]),
                "required": .array([.string("review_id")])
            ])
        )
    }
}