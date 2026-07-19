//
//  ReportSummary.swift
//  asc-mcp
//
//  Generates summaries for ASC sales and financial reports
//

import Foundation

/// Generates summary statistics from parsed report rows
enum ReportSummary {

    private static let decimalLocale = Locale(identifier: "en_US_POSIX")

    private static func decimal(_ value: String?) -> Decimal {
        guard let value else { return .zero }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(string: trimmed, locale: decimalLocale) ?? .zero
    }

    private static func optionalDecimal(_ value: String?) -> Decimal? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed, locale: decimalLocale)
    }

    private static func magnitude(_ value: Decimal) -> Decimal {
        value < .zero ? -value : value
    }

    private static func jsonCount(_ value: Decimal) -> Any {
        let number = NSDecimalNumber(decimal: value)
        if value >= Decimal(Int.min), value <= Decimal(Int.max) {
            let integer = number.intValue
            if Decimal(integer) == value {
                return integer
            }
        }
        return number.doubleValue
    }

    private static func jsonCountMap(_ values: [String: Decimal]) -> Any {
        let mapped = values.mapValues(jsonCount)
        if let integers = mapped as? [String: Int] {
            return integers
        }
        return mapped
    }

    private static func roundedDecimal(_ value: Decimal, scale: Int) -> Decimal {
        var source = value
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &source, scale, .plain)
        return rounded
    }

    private static func jsonDecimal(_ value: Decimal) -> Double {
        let number = NSDecimalNumber(decimal: value)
        return Double(number.stringValue) ?? number.doubleValue
    }

    private static func exactDecimalMap(_ values: [String: Decimal]) -> [String: String] {
        values.mapValues { NSDecimalNumber(decimal: $0).stringValue }
    }

    // MARK: - Router

    /// Selects the appropriate summary method based on report type
    /// - Parameters:
    ///   - reportType: The sales report type (SALES, SUBSCRIPTION, SUBSCRIPTION_EVENT, SUBSCRIBER, etc.)
    ///   - rows: All parsed TSV rows (not limited)
    /// - Returns: Dictionary with summary statistics tailored to the report type
    static func summary(for reportType: String, from rows: [[String: String]]) -> [String: Any] {
        switch reportType {
        case "SUBSCRIPTION":
            return subscriptionSummary(from: rows)
        case "SUBSCRIPTION_EVENT":
            return subscriptionEventSummary(from: rows)
        case "SUBSCRIBER":
            return subscriberSummary(from: rows)
        case "FIRST_ANNUAL", "INSTALLS", "SUBSCRIPTION_OFFER_CODE_REDEMPTION", "WIN_BACK_ELIGIBILITY":
            return ["row_count": rows.count]
        default:
            return salesSummary(from: rows)
        }
    }

    // MARK: - Sales Report Summary

    /// Creates a summary for a sales report (SALES, PRE_ORDER, NEWSSTAND)
    /// - Parameter rows: All parsed TSV rows (not limited)
    /// - Returns: Dictionary with summary statistics including per-app breakdown
    static func salesSummary(from rows: [[String: String]]) -> [String: Any] {
        var totalUnits = Decimal.zero
        var proceedsByCurrency: [String: Decimal] = [:]
        var unitsByCountry: [String: Decimal] = [:]
        var unitsByProductType: [String: Decimal] = [:]
        var appStats: [String: AppSalesStats] = [:]
        var zeroUnitPartialRefundRows = 0
        var zeroUnitUnclassifiedAdjustmentRows = 0
        var zeroUnitProceedsAdjustments: [[String: Any]] = []

        for row in rows {
            let units = decimal(row["Units"])
            totalUnits += units

            let currency = row["Currency of Proceeds"] ?? row["Customer Currency"] ?? ""
            let perUnitProceeds = decimal(row["Developer Proceeds"])
            let customerPrice = optionalDecimal(row["Customer Price"])
            let isZeroUnitProceedsAdjustment = units == .zero && perUnitProceeds != .zero
            let proceeds = isZeroUnitProceedsAdjustment ? Decimal.zero : perUnitProceeds * units
            if units == .zero {
                if let customerPrice, customerPrice < .zero {
                    zeroUnitPartialRefundRows += 1
                } else if isZeroUnitProceedsAdjustment {
                    zeroUnitUnclassifiedAdjustmentRows += 1
                }
            }
            if isZeroUnitProceedsAdjustment {
                var adjustment: [String: Any] = [
                    "classification": customerPrice.map { $0 < .zero ? "partial_refund" : "unclassified" } ?? "unclassified",
                    "developer_proceeds_per_unit": jsonDecimal(perUnitProceeds),
                    "developer_proceeds_per_unit_exact": NSDecimalNumber(decimal: perUnitProceeds).stringValue
                ]
                if let customerPrice {
                    adjustment["customer_price"] = jsonDecimal(customerPrice)
                    adjustment["customer_price_exact"] = NSDecimalNumber(decimal: customerPrice).stringValue
                }
                if !currency.isEmpty {
                    adjustment["currency"] = currency
                }
                if let title = row["Title"], !title.isEmpty {
                    adjustment["title"] = title
                }
                zeroUnitProceedsAdjustments.append(adjustment)
            }
            if !currency.isEmpty {
                proceedsByCurrency[currency, default: .zero] += proceeds
            }

            let country = row["Country Code"] ?? ""
            if !country.isEmpty {
                unitsByCountry[country, default: .zero] += units
            }

            let productType = row["Product Type Identifier"] ?? ""
            if !productType.isEmpty {
                unitsByProductType[productType, default: .zero] += units
            }

            let title = row["Title"] ?? ""
            if !title.isEmpty {
                appStats[title, default: AppSalesStats()].units += units
                if !currency.isEmpty {
                    appStats[title, default: AppSalesStats()].proceedsByCurrency[currency, default: .zero] += proceeds
                }
                if isZeroUnitProceedsAdjustment {
                    appStats[title, default: AppSalesStats()].proceedsByCurrencyIsComplete = false
                }
            }
        }

        // Top countries by units (descending), max 10
        let topCountries = unitsByCountry
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { ["country": $0.key, "units": jsonCount($0.value)] as [String: Any] }

        let numericProceeds = proceedsByCurrency.mapValues(jsonDecimal)
        let exactProceeds = exactDecimalMap(proceedsByCurrency)

        // Per-app breakdown sorted by units descending
        let byApp = appStats
            .sorted { $0.value.units > $1.value.units }
            .map { (title, stats) -> [String: Any] in
                let numericAppProceeds = stats.proceedsByCurrency.mapValues(jsonDecimal)
                return [
                    "title": title,
                    "units": jsonCount(stats.units),
                    "proceeds_by_currency": numericAppProceeds,
                    "proceeds_by_currency_exact": exactDecimalMap(stats.proceedsByCurrency),
                    "proceeds_by_currency_is_complete": stats.proceedsByCurrencyIsComplete
                ]
            }

        var summary: [String: Any] = [
            "total_units": jsonCount(totalUnits),
            "proceeds_by_currency": numericProceeds,
            "proceeds_by_currency_exact": exactProceeds,
            "proceeds_by_currency_is_complete": zeroUnitProceedsAdjustments.isEmpty,
            "by_product_type": jsonCountMap(unitsByProductType),
            "by_app": byApp,
            "zero_unit_partial_refund_rows": zeroUnitPartialRefundRows,
            "zero_unit_unclassified_adjustment_rows": zeroUnitUnclassifiedAdjustmentRows,
            "zero_unit_proceeds_adjustments": zeroUnitProceedsAdjustments
        ]

        if !topCountries.isEmpty {
            summary["top_countries"] = topCountries
        }

        return summary
    }

    /// Accumulator for per-app sales statistics
    private struct AppSalesStats {
        var units = Decimal.zero
        var proceedsByCurrency: [String: Decimal] = [:]
        var proceedsByCurrencyIsComplete = true
    }

    // MARK: - Subscription Report Summary

    /// Creates a summary for SUBSCRIPTION report (active subscriber counts)
    /// - Parameter rows: All parsed TSV rows
    /// - Returns: Dictionary with active subs, trials, billing retry, grace period counts
    static func subscriptionSummary(from rows: [[String: String]]) -> [String: Any] {
        let activeMetrics: [(header: String, output: String)] = [
            ("Active Standard Price Subscriptions", "active_standard_subscriptions"),
            ("Active Free Trial Introductory Offer Subscriptions", "active_free_trial_introductory_offer_subscriptions"),
            ("Active Pay Up Front Introductory Offer Subscriptions", "active_pay_up_front_introductory_offer_subscriptions"),
            ("Active Pay as You Go Introductory Offer Subscriptions", "active_pay_as_you_go_introductory_offer_subscriptions"),
            ("Free Trial Promotional Offer Subscriptions", "active_free_trial_promotional_offer_subscriptions"),
            ("Pay Up Front Promotional Offer Subscriptions", "active_pay_up_front_promotional_offer_subscriptions"),
            ("Pay As You Go Promotional Offer Subscriptions", "active_pay_as_you_go_promotional_offer_subscriptions"),
            ("Free Trial Offer Code Subscriptions", "active_free_trial_offer_code_subscriptions"),
            ("Pay Up Front Offer Code Subscriptions", "active_pay_up_front_offer_code_subscriptions"),
            ("Pay As You Go Offer Code Subscriptions", "active_pay_as_you_go_offer_code_subscriptions"),
            ("Free Trial Win-Back Offers", "active_free_trial_win_back_offers"),
            ("Pay Up Front Win-Back Offers", "active_pay_up_front_win_back_offers"),
            ("Pay As You Go Win-Back Offers", "active_pay_as_you_go_win_back_offers")
        ]
        var totals = Dictionary(uniqueKeysWithValues: activeMetrics.map { ($0.output, Decimal.zero) })
        var totalBillingRetry = Decimal.zero
        var totalGracePeriod = Decimal.zero
        var totalMarketingOptIns = Decimal.zero
        var totalSubscribersReported = Decimal.zero
        var subscriberRowsReported = 0
        var subscriberRowsSuppressed = 0
        var subsByCountry: [String: Decimal] = [:]
        var subsByProduct: [String: Decimal] = [:]

        for row in rows {
            var reportedActive = Decimal.zero
            for metric in activeMetrics {
                let value = decimal(row[metric.header])
                totals[metric.output, default: .zero] += value
                reportedActive += value
            }

            let billingRetry = decimal(row["Billing Retry"])
            let gracePeriod = decimal(row["Grace Period"])
            let optIns = decimal(row["Marketing Opt-Ins"])
            totalBillingRetry += billingRetry
            totalGracePeriod += gracePeriod
            totalMarketingOptIns += optIns
            reportedActive += optIns

            if let subscribers = optionalDecimal(row["Subscribers"]) {
                totalSubscribersReported += subscribers
                subscriberRowsReported += 1
            } else {
                subscriberRowsSuppressed += 1
            }

            let country = row["Country"] ?? ""
            if !country.isEmpty {
                subsByCountry[country, default: .zero] += reportedActive
            }

            let subName = row["Subscription Name"] ?? ""
            if !subName.isEmpty {
                subsByProduct[subName, default: .zero] += reportedActive
            }
        }

        let topCountries = subsByCountry
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { ["country": $0.key, "subscriptions": jsonCount($0.value)] as [String: Any] }

        var reportedActiveSubscriptions = totalMarketingOptIns
        for metric in activeMetrics {
            reportedActiveSubscriptions += totals[metric.output, default: .zero]
        }

        var summary: [String: Any] = [
            "active_free_trials": jsonCount(totals["active_free_trial_introductory_offer_subscriptions", default: .zero]),
            "billing_retry": jsonCount(totalBillingRetry),
            "grace_period": jsonCount(totalGracePeriod),
            "marketing_opt_ins": jsonCount(totalMarketingOptIns),
            "reported_active_subscriptions": jsonCount(reportedActiveSubscriptions),
            "total_subscribers": jsonCount(totalSubscribersReported),
            "total_subscribers_reported": jsonCount(totalSubscribersReported),
            "total_subscribers_lower_bound": jsonCount(totalSubscribersReported),
            "total_subscribers_is_lower_bound": subscriberRowsSuppressed > 0,
            "subscriber_rows_reported": subscriberRowsReported,
            "subscriber_rows_suppressed": subscriberRowsSuppressed,
            "subscriber_suppression_rule": "Subscribers is blank when an Apple report record represents 3 or fewer subscriptions",
            "by_product": jsonCountMap(subsByProduct)
        ]

        for metric in activeMetrics {
            summary[metric.output] = jsonCount(totals[metric.output, default: .zero])
        }

        if !topCountries.isEmpty {
            summary["top_countries"] = topCountries
        }

        return summary
    }

    // MARK: - Subscription Event Report Summary

    /// Creates a summary for SUBSCRIPTION_EVENT report (renewals, cancellations, trials, etc.)
    /// - Parameter rows: All parsed TSV rows
    /// - Returns: Dictionary with event counts by type, country, and product
    static func subscriptionEventSummary(from rows: [[String: String]]) -> [String: Any] {
        var eventCounts: [String: Decimal] = [:]
        var totalQuantity = Decimal.zero
        var eventsByCountry: [String: Decimal] = [:]
        var eventsByProduct: [String: Decimal] = [:]

        for row in rows {
            let event = row["Event"] ?? ""
            let quantity = optionalDecimal(row["Quantity"]) ?? 1

            if !event.isEmpty {
                eventCounts[event, default: .zero] += quantity
            }
            totalQuantity += quantity

            let country = row["Country"] ?? ""
            if !country.isEmpty {
                eventsByCountry[country, default: .zero] += quantity
            }

            let subName = row["Subscription Name"] ?? ""
            if !subName.isEmpty {
                eventsByProduct[subName, default: .zero] += quantity
            }
        }

        let topCountries = eventsByCountry
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { ["country": $0.key, "events": jsonCount($0.value)] as [String: Any] }

        var summary: [String: Any] = [
            "total_events": jsonCount(totalQuantity),
            "by_event_type": jsonCountMap(eventCounts),
            "by_product": jsonCountMap(eventsByProduct)
        ]

        if !topCountries.isEmpty {
            summary["top_countries"] = topCountries
        }

        return summary
    }

    // MARK: - Subscriber Report Summary

    /// Creates a summary for SUBSCRIBER report (per-transaction subscriber data)
    /// - Parameter rows: All parsed TSV rows
    /// - Returns: Dictionary with units, proceeds, refunds, unique subscribers
    static func subscriberSummary(from rows: [[String: String]]) -> [String: Any] {
        var totalUnits = Decimal.zero
        var totalRefunds = Decimal.zero
        var totalRefundReversals = Decimal.zero
        var proceedsByCurrency: [String: Decimal] = [:]
        var unitsByCountry: [String: Decimal] = [:]
        var unitsByProduct: [String: Decimal] = [:]
        var uniqueSubscribers: Set<String> = []
        var zeroUnitPartialRefundRows = 0
        var zeroUnitPartialRefundReversalRows = 0
        var zeroUnitUnclassifiedAdjustmentRows = 0
        var zeroUnitProceedsAdjustments: [[String: Any]] = []

        for row in rows {
            let units = decimal(row["Units"])
            totalUnits += units

            let isRefund = (row["Refund"] ?? "").lowercased() == "yes"
            let isRefundReversal = isRefund && (optionalDecimal(row["Customer Price"]) ?? .zero) > .zero
            if isRefundReversal {
                totalRefundReversals += magnitude(units)
            } else if isRefund {
                totalRefunds += magnitude(units)
            }
            if isRefund, units == .zero {
                if isRefundReversal {
                    zeroUnitPartialRefundReversalRows += 1
                } else {
                    zeroUnitPartialRefundRows += 1
                }
            } else if units == .zero, decimal(row["Developer Proceeds"]) != .zero {
                zeroUnitUnclassifiedAdjustmentRows += 1
            }

            let currency = row["Proceeds Currency"] ?? row["Customer Currency"] ?? ""
            let perUnitProceeds = decimal(row["Developer Proceeds"])
            let isZeroUnitProceedsAdjustment = units == .zero && perUnitProceeds != .zero
            var proceeds = isZeroUnitProceedsAdjustment ? Decimal.zero : perUnitProceeds * units
            if isRefund {
                let absoluteProceeds = magnitude(proceeds)
                proceeds = isRefundReversal ? absoluteProceeds : -absoluteProceeds
            }
            if isZeroUnitProceedsAdjustment {
                let customerPrice = optionalDecimal(row["Customer Price"])
                let classification: String
                if isRefundReversal {
                    classification = "partial_refund_reversal"
                } else if isRefund {
                    classification = "partial_refund"
                } else {
                    classification = "unclassified"
                }
                var adjustment: [String: Any] = [
                    "classification": classification,
                    "developer_proceeds_per_item": jsonDecimal(perUnitProceeds),
                    "developer_proceeds_per_item_exact": NSDecimalNumber(decimal: perUnitProceeds).stringValue
                ]
                if let customerPrice {
                    adjustment["customer_price"] = jsonDecimal(customerPrice)
                    adjustment["customer_price_exact"] = NSDecimalNumber(decimal: customerPrice).stringValue
                }
                if !currency.isEmpty {
                    adjustment["currency"] = currency
                }
                if let subscriptionName = row["Subscription Name"], !subscriptionName.isEmpty {
                    adjustment["subscription_name"] = subscriptionName
                }
                zeroUnitProceedsAdjustments.append(adjustment)
            }
            if !currency.isEmpty {
                proceedsByCurrency[currency, default: .zero] += proceeds
            }

            let country = row["Country"] ?? ""
            if !country.isEmpty {
                unitsByCountry[country, default: .zero] += units
            }

            let subName = row["Subscription Name"] ?? ""
            if !subName.isEmpty {
                unitsByProduct[subName, default: .zero] += units
            }

            let subscriberId = row["Subscriber ID"] ?? ""
            if !subscriberId.isEmpty {
                uniqueSubscribers.insert(subscriberId)
            }
        }

        let numericProceeds = proceedsByCurrency.mapValues(jsonDecimal)

        let topCountries = unitsByCountry
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { ["country": $0.key, "units": jsonCount($0.value)] as [String: Any] }

        var summary: [String: Any] = [
            "total_units": jsonCount(totalUnits),
            "total_refunds": jsonCount(totalRefunds),
            "total_refund_reversals": jsonCount(totalRefundReversals),
            "refunded_units": jsonCount(totalRefunds),
            "refund_reversal_units": jsonCount(totalRefundReversals),
            "zero_unit_partial_refund_rows": zeroUnitPartialRefundRows,
            "zero_unit_partial_refund_reversal_rows": zeroUnitPartialRefundReversalRows,
            "zero_unit_unclassified_adjustment_rows": zeroUnitUnclassifiedAdjustmentRows,
            "zero_unit_proceeds_adjustments": zeroUnitProceedsAdjustments,
            "unique_subscribers": uniqueSubscribers.count,
            "proceeds_by_currency": numericProceeds,
            "proceeds_by_currency_exact": exactDecimalMap(proceedsByCurrency),
            "proceeds_by_currency_is_complete": zeroUnitProceedsAdjustments.isEmpty,
            "by_product": jsonCountMap(unitsByProduct)
        ]

        if !topCountries.isEmpty {
            summary["top_countries"] = topCountries
        }

        return summary
    }

    // MARK: - Financial Report Summary

    /// Creates a summary for a financial report
    /// - Parameter rows: All parsed TSV rows (not limited)
    /// - Returns: Dictionary with summary statistics
    static func financialSummary(from rows: [[String: String]]) -> [String: Any] {
        var totalQuantity = Decimal.zero
        var partnerShareByCurrency: [String: Decimal] = [:]
        var quantityByCountry: [String: Decimal] = [:]

        for row in rows {
            let quantity = decimal(row["Quantity"])
            totalQuantity += quantity

            let currency = row["Partner Share Currency"] ?? row["Currency of Proceeds"] ?? ""
            let partnerShare = optionalDecimal(row["Extended Partner Share"])
                ?? quantity * decimal(row["Partner Share"])
            if !currency.isEmpty {
                partnerShareByCurrency[currency, default: .zero] += partnerShare
            }

            let country = row["Country Of Sale (Region)"] ?? row["Country or Region"] ?? ""
            if !country.isEmpty {
                quantityByCountry[country, default: .zero] += quantity
            }
        }

        let roundedPartnerShare = partnerShareByCurrency.mapValues { roundedDecimal($0, scale: 2) }

        // Top countries by quantity (descending), max 10
        let topCountries = quantityByCountry
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { ["country": $0.key, "quantity": jsonCount($0.value)] as [String: Any] }

        var summary: [String: Any] = [
            "total_quantity": jsonCount(totalQuantity),
            "partner_share_by_currency": roundedPartnerShare.mapValues(jsonDecimal),
            "partner_share_by_currency_exact": exactDecimalMap(roundedPartnerShare)
        ]

        if !topCountries.isEmpty {
            summary["top_countries"] = topCountries
        }

        return summary
    }
}
