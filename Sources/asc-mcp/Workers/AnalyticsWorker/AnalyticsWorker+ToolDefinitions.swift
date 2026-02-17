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
            description: """
            Get sales, subscription, and download reports from App Store Connect. Returns structured JSON with parsed TSV data, summary statistics, and individual rows.

            Report types and their use cases:
            - SALES (version 1_0): Downloads, updates, re-downloads, proceeds. Frequency: DAILY/WEEKLY/MONTHLY/YEARLY. Sub-type: SUMMARY/DETAILED.
            - SUBSCRIPTION (version 1_3): Active subscriber counts by state/country/device, intro offers, promo offers, billing retry, grace period. Frequency: DAILY. Sub-type: SUMMARY.
            - SUBSCRIPTION_EVENT (version 1_4): Subscriber activity — new subscriptions, renewals, upgrades, downgrades, cancellations, reactivations, refunds, conversions from trial. Frequency: DAILY. Sub-type: SUMMARY.
            - SUBSCRIBER (version 1_3): Transaction-level subscriber activity with anonymous Subscriber IDs, purchase dates, proceeds. Frequency: DAILY. Sub-type: DETAILED.
            - SUBSCRIPTION_OFFER_CODE_REDEMPTION (version 1_0): Offer code redemptions. Frequency: DAILY. Sub-type: SUMMARY.
            - PRE_ORDER (version 1_1): Pre-order units. Frequency: DAILY/WEEKLY/MONTHLY/YEARLY. Sub-type: SUMMARY.

            Typical workflows:
            1. Installs/downloads: SALES + SUMMARY + DAILY
            2. Active subscribers: SUBSCRIPTION + SUMMARY + DAILY
            3. Trial conversions, cancellations, renewals: SUBSCRIPTION_EVENT + SUMMARY + DAILY
            4. Per-subscriber transaction history: SUBSCRIBER + DETAILED + DAILY
            5. Revenue by product: SALES + DETAILED + DAILY
            """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "vendor_number": .object([
                        "type": .string("string"),
                        "description": .string("Vendor number from App Store Connect (found in Sales and Trends > Reports). If not provided, uses vendor_number from company config.")
                    ]),
                    "report_type": .object([
                        "type": .string("string"),
                        "description": .string("Type of report: SALES (downloads/revenue), SUBSCRIPTION (active subs), SUBSCRIPTION_EVENT (renewals/cancellations/trials), SUBSCRIBER (per-user transactions), PRE_ORDER, SUBSCRIPTION_OFFER_CODE_REDEMPTION"),
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
                        "description": .string("Report sub-type: SUMMARY (aggregated), DETAILED (per-transaction), OPT_IN (marketing opt-ins)"),
                        "enum": .array([
                            .string("SUMMARY"),
                            .string("DETAILED"),
                            .string("OPT_IN")
                        ])
                    ]),
                    "frequency": .object([
                        "type": .string("string"),
                        "description": .string("Report frequency. SUBSCRIPTION/SUBSCRIPTION_EVENT/SUBSCRIBER only support DAILY."),
                        "enum": .array([
                            .string("DAILY"),
                            .string("WEEKLY"),
                            .string("MONTHLY"),
                            .string("YEARLY")
                        ])
                    ]),
                    "report_date": .object([
                        "type": .string("string"),
                        "description": .string("Report date in YYYY-MM-DD format (e.g., 2025-01-15). Reports available next day by 8am PT.")
                    ]),
                    "version": .object([
                        "type": .string("string"),
                        "description": .string("Report version (e.g., 1_0, 1_3, 1_4). If omitted, uses the latest known default for the report type.")
                    ]),
                    "summary_only": .object([
                        "type": .string("boolean"),
                        "description": .string("If true (default), returns only summary statistics (by app, by country, by product type, proceeds). Set to false to include raw rows.")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max raw rows to return when summary_only=false (default: 25). Summary is always computed from all rows.")
                    ])
                ]),
                "required": .array([
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
            description: "Get financial reports from App Store Connect. Returns summary with total quantity, partner share by currency, and top countries. Set summary_only=false to include raw rows.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "vendor_number": .object([
                        "type": .string("string"),
                        "description": .string("Vendor number from App Store Connect. If not provided, uses vendor_number from company config.")
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
                    ]),
                    "summary_only": .object([
                        "type": .string("boolean"),
                        "description": .string("If true (default), returns only summary statistics. Set to false to include raw rows.")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max raw rows to return when summary_only=false (default: 25). Summary is always computed from all rows.")
                    ])
                ]),
                "required": .array([
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

    /// Creates tool definition for listing analytics reports for a report request
    func listAnalyticsReportsTool() -> Tool {
        return Tool(
            name: "analytics_list_reports",
            description: "List analytics reports for a report request. Returns report categories and names available for download.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "request_id": .object([
                        "type": .string("string"),
                        "description": .string("Analytics report request ID")
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
                "required": .array([.string("request_id")])
            ])
        )
    }

    /// Creates tool definition for getting details of a specific analytics report
    func getAnalyticsReportTool() -> Tool {
        return Tool(
            name: "analytics_get_report",
            description: "Get details of a specific analytics report including its category and name.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "report_id": .object([
                        "type": .string("string"),
                        "description": .string("Analytics report ID")
                    ])
                ]),
                "required": .array([.string("report_id")])
            ])
        )
    }

    /// Creates tool definition for listing instances of an analytics report
    func listAnalyticsReportInstancesTool() -> Tool {
        return Tool(
            name: "analytics_list_instances",
            description: "List instances of an analytics report. Each instance represents a specific time period of data.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "report_id": .object([
                        "type": .string("string"),
                        "description": .string("Analytics report ID")
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
                "required": .array([.string("report_id")])
            ])
        )
    }

    /// Creates tool definition for getting a specific analytics report instance
    func getAnalyticsReportInstanceTool() -> Tool {
        return Tool(
            name: "analytics_get_instance",
            description: "Get a specific analytics report instance with its granularity and processing date.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "instance_id": .object([
                        "type": .string("string"),
                        "description": .string("Analytics report instance ID")
                    ])
                ]),
                "required": .array([.string("instance_id")])
            ])
        )
    }

    /// Creates tool definition for checking snapshot readiness status
    func checkSnapshotStatusTool() -> Tool {
        return Tool(
            name: "analytics_check_snapshot_status",
            description: "Check readiness of all reports in an analytics snapshot. Returns summary with ready/pending counts and report details. Useful after creating a ONE_TIME_SNAPSHOT to monitor when reports become available.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "request_id": .object([
                        "type": .string("string"),
                        "description": .string("Analytics report request ID (from analytics_create_report_request or analytics_list_report_requests)")
                    ]),
                    "category": .object([
                        "type": .string("string"),
                        "description": .string("Optional filter by report category"),
                        "enum": .array([
                            .string("APP_USAGE"),
                            .string("APP_STORE_ENGAGEMENT"),
                            .string("COMMERCE"),
                            .string("FRAMEWORK_USAGE"),
                            .string("PERFORMANCE")
                        ])
                    ])
                ]),
                "required": .array([.string("request_id")])
            ])
        )
    }

    /// Creates tool definition for listing segments of an analytics report instance
    func listAnalyticsReportSegmentsTool() -> Tool {
        return Tool(
            name: "analytics_list_segments",
            description: "List segments of an analytics report instance. Each segment contains a download URL for the actual report data.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "instance_id": .object([
                        "type": .string("string"),
                        "description": .string("Analytics report instance ID")
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
                "required": .array([.string("instance_id")])
            ])
        )
    }
}
