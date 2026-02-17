//
//  AnalyticsWorker+ToolDefinitions.swift
//  asc-mcp
//
//  Tool definitions for analytics and reports operations
//

import Foundation
import MCP

extension AnalyticsWorker {
    /// Creates tool definition for getting sales/download reports
    func getSalesReportTool() -> Tool {
        return Tool(
            name: "analytics_sales_report",
            description: "Get sales and download reports from App Store Connect. Returns CSV data with sales metrics including units, proceeds, and download statistics.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "vendor_number": .object([
                        "type": .string("string"),
                        "description": .string("Vendor number from App Store Connect (found in Sales and Trends > Reports)")
                    ]),
                    "report_type": .object([
                        "type": .string("string"),
                        "description": .string("Type of sales report"),
                        "enum": .array([
                            .string("SALES"),
                            .string("PRE_ORDER"),
                            .string("NEWSSTAND"),
                            .string("SUBSCRIPTION"),
                            .string("SUBSCRIPTION_EVENT"),
                            .string("SUBSCRIBER"),
                            .string("SUBSCRIPTION_OFFER_CODE_REDEMPTION")
                        ])
                    ]),
                    "report_sub_type": .object([
                        "type": .string("string"),
                        "description": .string("Report sub-type"),
                        "enum": .array([
                            .string("SUMMARY"),
                            .string("DETAILED"),
                            .string("OPT_IN")
                        ])
                    ]),
                    "frequency": .object([
                        "type": .string("string"),
                        "description": .string("Report frequency"),
                        "enum": .array([
                            .string("DAILY"),
                            .string("WEEKLY"),
                            .string("MONTHLY"),
                            .string("YEARLY")
                        ])
                    ]),
                    "report_date": .object([
                        "type": .string("string"),
                        "description": .string("Report date in YYYY-MM-DD format (e.g., 2025-01-15)")
                    ])
                ]),
                "required": .array([
                    .string("vendor_number"),
                    .string("report_type"),
                    .string("report_sub_type"),
                    .string("frequency"),
                    .string("report_date")
                ])
            ])
        )
    }

    /// Creates tool definition for getting financial reports
    func getFinancialReportTool() -> Tool {
        return Tool(
            name: "analytics_financial_report",
            description: "Get financial reports from App Store Connect. Returns CSV data with financial metrics including earnings, taxes, and currency details.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "vendor_number": .object([
                        "type": .string("string"),
                        "description": .string("Vendor number from App Store Connect")
                    ]),
                    "region_code": .object([
                        "type": .string("string"),
                        "description": .string("Financial region code (e.g., US, EU, JP, AU, CA)")
                    ]),
                    "report_date": .object([
                        "type": .string("string"),
                        "description": .string("Report date in YYYY-MM format (e.g., 2025-01)")
                    ]),
                    "report_type": .object([
                        "type": .string("string"),
                        "description": .string("Type of financial report"),
                        "enum": .array([
                            .string("FINANCIAL"),
                            .string("FINANCE_DETAIL")
                        ])
                    ])
                ]),
                "required": .array([
                    .string("vendor_number"),
                    .string("region_code"),
                    .string("report_date"),
                    .string("report_type")
                ])
            ])
        )
    }

    /// Creates tool definition for listing analytics report requests
    func listAnalyticsReportRequestsTool() -> Tool {
        return Tool(
            name: "analytics_list_report_requests",
            description: "List analytics report requests for an app. Shows existing report requests with their access type and status.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum number of results to return (1-200, default: 25)")
                    ]),
                    "next_url": .object([
                        "type": .string("string"),
                        "description": .string("URL for next page of results (from previous response)")
                    ])
                ]),
                "required": .array([.string("app_id")])
            ])
        )
    }

    /// Creates tool definition for creating an analytics report request
    func createAnalyticsReportRequestTool() -> Tool {
        return Tool(
            name: "analytics_create_report_request",
            description: "Create an analytics report request for an app. Use ONE_TIME_SNAPSHOT for a single report or ONGOING for continuous reporting.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("App Store Connect app ID")
                    ]),
                    "access_type": .object([
                        "type": .string("string"),
                        "description": .string("Report access type"),
                        "enum": .array([
                            .string("ONE_TIME_SNAPSHOT"),
                            .string("ONGOING")
                        ])
                    ])
                ]),
                "required": .array([.string("app_id"), .string("access_type")])
            ])
        )
    }
}
