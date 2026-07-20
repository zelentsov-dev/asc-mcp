//
//  ReviewsWorker+ToolDefinitions.swift
//  asc-mcp
//
//  Tool definitions for customer reviews operations
//

import Foundation
import MCP

extension ReviewsWorker {
    static let supportedReviewSorts = ["rating", "-rating", "createdDate", "-createdDate"]

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
                        "description": .string("Maximum number of reviews to return (1-200, default: 100)"),
                        "minimum": .int(1),
                        "maximum": .int(200)
                    ]),
                    "rating": .object([
                        "type": .string("integer"),
                        "description": .string("Filter by one rating (1-5). Use ratings for multiple values."),
                        "minimum": .int(1),
                        "maximum": .int(5)
                    ]),
                    "ratings": .object([
                        "type": .string("array"),
                        "description": .string("Filter by one or more ratings"),
                        "items": .object([
                            "type": .string("integer"),
                            "minimum": .int(1),
                            "maximum": .int(5)
                        ]),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true)
                    ]),
                    "territory": .object([
                        "type": .string("string"),
                        "description": .string("One Apple ISO 3166-1 alpha-3 territory code (USA, RUS, DEU, JPN)"),
                        "minLength": .int(3),
                        "maxLength": .int(3)
                    ]),
                    "territories": .object([
                        "type": .string("array"),
                        "description": .string("One or more Apple ISO 3166-1 alpha-3 territory codes"),
                        "items": .object([
                            "type": .string("string"),
                            "minLength": .int(3),
                            "maxLength": .int(3)
                        ]),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true)
                    ]),
                    "sort": reviewSortSchema(),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
                    ]),
                    "include_response": .object([
                        "type": .string("boolean"),
                        "description": .string("Include developer responses inline with reviews (default: false)")
                    ]),
                    "has_published_response": .object([
                        "type": .string("boolean"),
                        "description": .string("Filter reviews by whether they have a published developer response")
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
                        "description": .string("Maximum number of reviews to return (1-200, default: 100)"),
                        "minimum": .int(1),
                        "maximum": .int(200)
                    ]),
                    "rating": .object([
                        "type": .string("integer"),
                        "description": .string("Filter by one rating (1-5). Use ratings for multiple values."),
                        "minimum": .int(1),
                        "maximum": .int(5)
                    ]),
                    "ratings": .object([
                        "type": .string("array"),
                        "description": .string("Filter by one or more ratings"),
                        "items": .object([
                            "type": .string("integer"),
                            "minimum": .int(1),
                            "maximum": .int(5)
                        ]),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true)
                    ]),
                    "territory": .object([
                        "type": .string("string"),
                        "description": .string("Filter by one Apple ISO 3166-1 alpha-3 territory code (e.g., USA, RUS, DEU)"),
                        "minLength": .int(3),
                        "maxLength": .int(3)
                    ]),
                    "territories": .object([
                        "type": .string("array"),
                        "description": .string("One or more Apple ISO 3166-1 alpha-3 territory codes"),
                        "items": .object([
                            "type": .string("string"),
                            "minLength": .int(3),
                            "maxLength": .int(3)
                        ]),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true)
                    ]),
                    "sort": reviewSortSchema(),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
                    ]),
                    "include_response": .object([
                        "type": .string("boolean"),
                        "description": .string("Include developer responses inline with reviews (default: false)")
                    ]),
                    "has_published_response": .object([
                        "type": .string("boolean"),
                        "description": .string("Filter reviews by whether they have a published developer response")
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
            description: "Get complete deduplicated customer-review statistics for a rolling time period. Aggregates each page without retaining full review bodies, follows Apple pagination until the requested period is complete, and follows every page for all_time.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID"),
                        "minLength": .int(1)
                    ]),
                    "period": .object([
                        "type": .string("string"),
                        "description": .string("Rolling UTC time period ending when the tool runs: previous 7 days, previous 1 calendar month, previous 3 calendar months, or all available history. Default: last_month."),
                        "enum": .array([
                            .string("last_week"),
                            .string("last_month"),
                            .string("last_3_months"),
                            .string("all_time")
                        ])
                    ]),
                    "territory": .object([
                        "type": .string("string"),
                        "description": .string("Filter by Apple's ISO 3166-1 alpha-3 territory code (e.g., USA, RUS, DEU) or 'all' for all territories")
                    ]),
                    "has_published_response": .object([
                        "type": .string("boolean"),
                        "description": .string("Restrict statistics to reviews with or without a published developer response")
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

    /// Creates tool definition for getting AI-generated review summarizations
    func createReviewsSummarizationsTool() -> Tool {
        return Tool(
            name: "reviews_summarizations",
            description: "Get AI-generated summaries of customer reviews for an app",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "platform": .object([
                        "type": .string("string"),
                        "description": .string("Platform (default: IOS)"),
                        "enum": .array([.string("IOS"), .string("MAC_OS"), .string("TV_OS"), .string("VISION_OS")])
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of summarizations to return (1-200, default: 25)"),
                        "minimum": .int(1),
                        "maximum": .int(200)
                    ]),
                    "territory_id": .object([
                        "type": .string("string"),
                        "description": .string("Optional related App Store Connect territory resource ID"),
                        "minLength": .int(1)
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("Apple continuation URL from the previous response. Repeat every originating list control, including the effective/default limit, filters, sort, include, fields, and nested limits when supported; the exact query and a non-empty cursor are validated.")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    private func reviewSortSchema() -> Value {
        .object([
            "description": .string("Sort by rating or created date; prefix with - for descending order. Accepts one value or an ordered array (default: -createdDate)."),
            "oneOf": .array([
                .object([
                    "type": .string("string"),
                    "enum": .array(Self.supportedReviewSorts.map(Value.string))
                ]),
                .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("string"),
                        "enum": .array(Self.supportedReviewSorts.map(Value.string))
                    ]),
                    "minItems": .int(1),
                    "uniqueItems": .bool(true)
                ])
            ])
        ])
    }
}
