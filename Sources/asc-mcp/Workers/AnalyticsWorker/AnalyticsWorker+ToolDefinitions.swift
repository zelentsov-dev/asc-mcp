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
            Get sales, subscription, and download reports from App Store Connect. Returns structured JSON with parsed TSV data, a report-type summary, and optional individual rows. Gzip integrity and decoded size are validated, with limits of 64 MiB decompressed, 256 columns, 1,000,000 scanned rows, 10,000,000 scanned data cells, 100,000 matched rows, and 1,000,000 retained cells; larger reports fail without returning partial summaries. Monetary summaries use Decimal accumulation, retain numeric proceeds_by_currency for compatibility, and include proceeds_by_currency_exact strings without binary floating-point loss. FIRST_ANNUAL, INSTALLS, SUBSCRIPTION_OFFER_CODE_REDEMPTION, and WIN_BACK_ELIGIBILITY use an honest row-count summary; set summary_only=false to inspect their report-specific columns.

            Report types and their use cases:
            - SALES (version 1_0): Downloads, updates, re-downloads, proceeds. Frequency: DAILY/WEEKLY/MONTHLY/YEARLY. Sub-type: SUMMARY.
            - SUBSCRIPTION (version 1_3): Active standard-price, free/pay-up-front/pay-as-you-go introductory, promotional, offer-code, and win-back counts, plus marketing opt-ins, billing retry, grace period, and subscriber counts. Frequency: DAILY. Sub-type: SUMMARY. Apple's Subscribers cell is blank when a record represents 3 or fewer subscriptions, so total_subscribers is retained as a compatibility alias for the reported lower bound; subscriber_rows_suppressed and total_subscribers_is_lower_bound make suppression explicit.
            - SUBSCRIPTION_EVENT (version 1_3): Subscriber activity — new subscriptions, renewals, upgrades, downgrades, cancellations, reactivations, refunds, conversions from trial. Frequency: DAILY. Sub-type: SUMMARY.
            - SUBSCRIBER (version 1_3): Transaction-level subscriber activity with anonymous Subscriber IDs, purchase dates, proceeds. Frequency: DAILY. Sub-type: DETAILED.
            - SUBSCRIPTION_OFFER_CODE_REDEMPTION (version 1_0): Offer code redemptions. Frequency: DAILY. Sub-type: SUMMARY.
            - PRE_ORDER (version 1_0): Pre-order units. Frequency: DAILY/WEEKLY/MONTHLY/YEARLY. Sub-type: SUMMARY.
            - INSTALLS: Monthly SUMMARY/DETAILED reports use version 1_2; yearly DETAILED and SUMMARY_CHANNEL/SUMMARY_INSTALL_TYPE/SUMMARY_TERRITORY reports default to version 1_1.
            - FIRST_ANNUAL (version 1_0): DAILY/DETAILED or YEARLY/SUMMARY.
            - WIN_BACK_ELIGIBILITY (version 1_0): DAILY/SUMMARY.

            Typical workflows:
            1. Installs/downloads: SALES + SUMMARY + DAILY
            2. Active subscribers: SUBSCRIPTION + SUMMARY + DAILY
            3. Trial conversions, cancellations, renewals: SUBSCRIPTION_EVENT + SUMMARY + DAILY
            4. Per-subscriber transaction history: SUBSCRIBER + DETAILED + DAILY
            5. Revenue by product: SALES + SUMMARY + DAILY
            """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "vendor_number": .object([
                        "type": .string("string"),
                        "description": .string("Vendor number from App Store Connect (found in Sales and Trends > Reports). If not provided, uses vendor_number from company config."),
                        "minLength": .int(1)
                    ]),
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("Apple ID of the app to filter by (numeric, e.g., '1234567890'). If omitted, returns data for all apps. Use apps_list to find app IDs."),
                        "minLength": .int(1)
                    ]),
                    "report_type": .object([
                        "type": .string("string"),
                        "description": .string("Apple sales report type"),
                        "enum": .array([
                            .string("SALES"),
                            .string("PRE_ORDER"),
                            .string("NEWSSTAND"),
                            .string("SUBSCRIPTION"),
                            .string("SUBSCRIPTION_EVENT"),
                            .string("SUBSCRIBER"),
                            .string("SUBSCRIPTION_OFFER_CODE_REDEMPTION"),
                            .string("INSTALLS"),
                            .string("FIRST_ANNUAL"),
                            .string("WIN_BACK_ELIGIBILITY")
                        ])
                    ]),
                    "report_sub_type": .object([
                        "type": .string("string"),
                        "description": .string("Apple sales report sub-type. Valid combinations depend on report_type and frequency."),
                        "enum": .array([
                            .string("SUMMARY"),
                            .string("DETAILED"),
                            .string("SUMMARY_INSTALL_TYPE"),
                            .string("SUMMARY_TERRITORY"),
                            .string("SUMMARY_CHANNEL")
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
                        "description": .string("Apple report date in YYYY-MM-DD format. Optional for DAILY reports to request the latest available report; required in the same YYYY-MM-DD format for WEEKLY, MONTHLY, and YEARLY reports."),
                        "pattern": .string("^\\d{4}-\\d{2}-\\d{2}$")
                    ]),
                    "version": .object([
                        "type": .string("string"),
                        "description": .string("Report version. If omitted, uses the latest version Apple supports for the selected report type, sub-type, and frequency.")
                    ]),
                    "summary_only": .object([
                        "type": .string("boolean"),
                        "description": .string("If true (default), returns only summary statistics (by app, by country, by product type, proceeds). Set to false to include raw rows.")
                    ]),
                    "limit": .object([
                        "type": .string("integer"),
                        "description": .string("Max raw rows to return when summary_only=false (1-200, default: 25). Summary is always computed from all rows."),
                        "minimum": .int(1),
                        "maximum": .int(200)
                    ])
                ]),
                "required": .array([
                    .string("report_type"),
                    .string("report_sub_type"),
                    .string("frequency")
                ])
            ])
        )
    }

    /// Creates tool definition for combined app analytics summary
    func getAppSummaryTool() -> Tool {
        return Tool(
            name: "analytics_app_summary",
            description: """
            Get a combined analytics summary for an app in a single call. Fetches 4 report types with bounded sequential processing and returns all results together. Each report is integrity-checked and limited to 64 MiB after decompression, 256 columns, 1,000,000 scanned rows, 10,000,000 scanned data cells, 100,000 matched rows, and 1,000,000 retained cells; oversized sections fail without partial summaries.

            Sections returned:
            - downloads: Units, proceeds, by country/product type (from SALES/SUMMARY/DAILY)
            - subscriptions: All version 1_3 standard, introductory, promotional, offer-code, and win-back active counts; marketing opt-ins, billing retry, grace period, and reported/lower-bound subscriber semantics (from SUBSCRIPTION/SUMMARY/DAILY)
            - subscription_events: Renewals, cancellations, trials, upgrades, downgrades (from SUBSCRIPTION_EVENT/SUMMARY/DAILY)
            - revenue: Per-subscriber transaction data with proceeds (from SUBSCRIBER/DETAILED/DAILY)

            Each section has status "success" or "error". Partial success is returned when at least one section succeeds; the tool returns an error when every section fails.

            Example use cases:
            - "How did my app do yesterday?" → analytics_app_summary with the latest available completed report date
            - "Show me downloads and revenue for app X" → analytics_app_summary with app_id filter
            """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "report_date": .object([
                        "type": .string("string"),
                        "description": .string("Completed daily report date in YYYY-MM-DD format. Daily reports are normally available the following day by 8 a.m. PT."),
                        "pattern": .string("^\\d{4}-\\d{2}-\\d{2}$")
                    ]),
                    "app_id": .object([
                        "type": .string("string"),
                        "description": .string("Apple ID of the app to filter by (numeric, e.g., '1234567890'). If omitted, returns data for all apps."),
                        "minLength": .int(1)
                    ]),
                    "vendor_number": .object([
                        "type": .string("string"),
                        "description": .string("Vendor number from App Store Connect. If not provided, uses vendor_number from company config."),
                        "minLength": .int(1)
                    ])
                ]),
                "required": .array([
                    .string("report_date")
                ])
            ])
        )
    }

    /// Creates tool definition for getting financial reports
    func getFinancialReportTool() -> Tool {
        return Tool(
            name: "analytics_financial_report",
            description: "Get financial reports from App Store Connect. Returns summary with total quantity, partner share by currency, exact decimal partner-share strings, and top countries. Gzip integrity and decoded size are validated, with limits of 64 MiB decompressed, 256 columns, 1,000,000 scanned rows, 10,000,000 scanned data cells, 100,000 matched rows, and 1,000,000 retained cells; larger reports fail without returning partial summaries. Aggregation prefers Apple's signed Extended Partner Share and falls back to Quantity multiplied by per-unit Partner Share. Set summary_only=false to include raw rows.",
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
                        "description": .string("Max raw rows to return when summary_only=false (1-200, default: 25). Summary is always computed from all rows."),
                        "minimum": .int(1),
                        "maximum": .int(200)
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
                        "description": .string("Maximum number of results to return (1-200, default: 25)"),
                        "minimum": .int(1),
                        "maximum": .int(200)
                    ]),
                    "access_types": .object([
                        "type": .string("array"),
                        "description": .string("Filter by one or more analytics report access types"),
                        "items": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("ONE_TIME_SNAPSHOT"),
                                .string("ONGOING")
                            ])
                        ]),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true)
                    ]),
                    "include_reports": .object([
                        "type": .string("boolean"),
                        "description": .string("Include related analytics report resources and relationship IDs")
                    ]),
                    "limit_reports": .object([
                        "type": .string("integer"),
                        "description": .string("Maximum included reports per request (1-50; requires include_reports=true)"),
                        "minimum": .int(1),
                        "maximum": .int(50)
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
                        "description": .string("Maximum number of results to return (1-200, default: 25)"),
                        "minimum": .int(1),
                        "maximum": .int(200)
                    ]),
                    "names": .object([
                        "type": .string("array"),
                        "description": .string("Filter by one or more exact analytics report names"),
                        "items": .object([
                            "type": .string("string"),
                            "minLength": .int(1)
                        ]),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true)
                    ]),
                    "categories": .object([
                        "type": .string("array"),
                        "description": .string("Filter by one or more analytics report categories"),
                        "items": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("APP_USAGE"),
                                .string("APP_STORE_ENGAGEMENT"),
                                .string("COMMERCE"),
                                .string("FRAMEWORK_USAGE"),
                                .string("PERFORMANCE")
                            ])
                        ]),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true)
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
                        "description": .string("Maximum number of results to return (1-200, default: 25)"),
                        "minimum": .int(1),
                        "maximum": .int(200)
                    ]),
                    "granularities": .object([
                        "type": .string("array"),
                        "description": .string("Filter by one or more report granularities"),
                        "items": .object([
                            "type": .string("string"),
                            "enum": .array([
                                .string("DAILY"),
                                .string("WEEKLY"),
                                .string("MONTHLY")
                            ])
                        ]),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true)
                    ]),
                    "processing_dates": .object([
                        "type": .string("array"),
                        "description": .string("Filter by one or more processing dates in YYYY-MM-DD format"),
                        "items": .object([
                            "type": .string("string"),
                            "format": .string("date")
                        ]),
                        "minItems": .int(1),
                        "uniqueItems": .bool(true)
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
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Optional exact report-name filter"),
                        "minLength": .int(1)
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
                        "description": .string("Maximum number of results to return (1-200, default: 25)"),
                        "minimum": .int(1),
                        "maximum": .int(200)
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
