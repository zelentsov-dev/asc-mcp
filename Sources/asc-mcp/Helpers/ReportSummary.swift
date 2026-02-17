//
//  ReportSummary.swift
//  asc-mcp
//
//  Generates summaries for ASC sales and financial reports
//

import Foundation

/// Generates summary statistics from parsed report rows
enum ReportSummary {

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
        default:
            return salesSummary(from: rows)
        }
    }

    // MARK: - Sales Report Summary

    /// Creates a summary for a sales report (SALES, PRE_ORDER, NEWSSTAND)
    /// - Parameter rows: All parsed TSV rows (not limited)
    /// - Returns: Dictionary with summary statistics including per-app breakdown
    static func salesSummary(from rows: [[String: String]]) -> [String: Any] {
        var totalUnits = 0
        var proceedsByCurrency: [String: Double] = [:]
        var unitsByCountry: [String: Int] = [:]
        var unitsByProductType: [String: Int] = [:]
        var appStats: [String: AppSalesStats] = [:]

        for row in rows {
            let units = Int(row["Units"] ?? "") ?? 0
            totalUnits += units

            let currency = row["Currency of Proceeds"] ?? row["Customer Currency"] ?? ""
            let proceeds = Double(row["Developer Proceeds"] ?? "") ?? 0.0
            if !currency.isEmpty {
                proceedsByCurrency[currency, default: 0.0] += proceeds
            }

            let country = row["Country Code"] ?? ""
            if !country.isEmpty {
                unitsByCountry[country, default: 0] += units
            }

            let productType = row["Product Type Identifier"] ?? ""
            if !productType.isEmpty {
                unitsByProductType[productType, default: 0] += units
            }

            let title = row["Title"] ?? ""
            if !title.isEmpty {
                appStats[title, default: AppSalesStats()].units += units
                appStats[title, default: AppSalesStats()].proceedsByCurrency[currency, default: 0.0] += proceeds
            }
        }

        // Top countries by units (descending), max 10
        let topCountries = unitsByCountry
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { ["country": $0.key, "units": $0.value] as [String: Any] }

        // Round proceeds to 2 decimal places
        let roundedProceeds = proceedsByCurrency.mapValues { (value: Double) -> Double in
            (value * 100).rounded() / 100
        }

        // Per-app breakdown sorted by units descending
        let byApp = appStats
            .sorted { $0.value.units > $1.value.units }
            .map { (title, stats) -> [String: Any] in
                let roundedAppProceeds = stats.proceedsByCurrency.mapValues { ($0 * 100).rounded() / 100 }
                return [
                    "title": title,
                    "units": stats.units,
                    "proceeds_by_currency": roundedAppProceeds
                ]
            }

        var summary: [String: Any] = [
            "total_units": totalUnits,
            "proceeds_by_currency": roundedProceeds,
            "by_product_type": unitsByProductType,
            "by_app": byApp
        ]

        if !topCountries.isEmpty {
            summary["top_countries"] = topCountries
        }

        return summary
    }

    /// Accumulator for per-app sales statistics
    private struct AppSalesStats {
        var units: Int = 0
        var proceedsByCurrency: [String: Double] = [:]
    }

    // MARK: - Subscription Report Summary

    /// Creates a summary for SUBSCRIPTION report (active subscriber counts)
    /// - Parameter rows: All parsed TSV rows
    /// - Returns: Dictionary with active subs, trials, billing retry, grace period counts
    static func subscriptionSummary(from rows: [[String: String]]) -> [String: Any] {
        var totalActiveSubs = 0
        var totalFreeTrials = 0
        var totalBillingRetry = 0
        var totalGracePeriod = 0
        var totalMarketingOptIns = 0
        var totalSubscribers = 0
        var subsByCountry: [String: Int] = [:]
        var subsByProduct: [String: Int] = [:]

        for row in rows {
            let active = Int(row["Active Standard Price Subscriptions"] ?? "") ?? 0
            let freeTrials = Int(row["Active Free Trial Introductory Offer Subscriptions"] ?? "") ?? 0
            let billingRetry = Int(row["Billing Retry"] ?? "") ?? 0
            let gracePeriod = Int(row["Grace Period"] ?? "") ?? 0
            let optIns = Int(row["Marketing Opt-Ins"] ?? "") ?? 0
            let subscribers = Int(row["Subscribers"] ?? "") ?? 0

            totalActiveSubs += active
            totalFreeTrials += freeTrials
            totalBillingRetry += billingRetry
            totalGracePeriod += gracePeriod
            totalMarketingOptIns += optIns
            totalSubscribers += subscribers

            let country = row["Country"] ?? ""
            if !country.isEmpty {
                subsByCountry[country, default: 0] += active + freeTrials
            }

            let subName = row["Subscription Name"] ?? ""
            if !subName.isEmpty {
                subsByProduct[subName, default: 0] += active + freeTrials
            }
        }

        let topCountries = subsByCountry
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { ["country": $0.key, "subscriptions": $0.value] as [String: Any] }

        var summary: [String: Any] = [
            "active_standard_subscriptions": totalActiveSubs,
            "active_free_trials": totalFreeTrials,
            "billing_retry": totalBillingRetry,
            "grace_period": totalGracePeriod,
            "marketing_opt_ins": totalMarketingOptIns,
            "total_subscribers": totalSubscribers,
            "by_product": subsByProduct
        ]

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
        var eventCounts: [String: Int] = [:]
        var totalQuantity = 0
        var eventsByCountry: [String: Int] = [:]
        var eventsByProduct: [String: Int] = [:]

        for row in rows {
            let event = row["Event"] ?? ""
            let quantity = Int(row["Quantity"] ?? "") ?? 1

            if !event.isEmpty {
                eventCounts[event, default: 0] += quantity
            }
            totalQuantity += quantity

            let country = row["Country"] ?? ""
            if !country.isEmpty {
                eventsByCountry[country, default: 0] += quantity
            }

            let subName = row["Subscription Name"] ?? ""
            if !subName.isEmpty {
                eventsByProduct[subName, default: 0] += quantity
            }
        }

        let topCountries = eventsByCountry
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { ["country": $0.key, "events": $0.value] as [String: Any] }

        var summary: [String: Any] = [
            "total_events": totalQuantity,
            "by_event_type": eventCounts,
            "by_product": eventsByProduct
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
        var totalUnits = 0
        var totalRefunds = 0
        var proceedsByCurrency: [String: Double] = [:]
        var unitsByCountry: [String: Int] = [:]
        var unitsByProduct: [String: Int] = [:]
        var uniqueSubscribers: Set<String> = []

        for row in rows {
            let units = Int(row["Units"] ?? "") ?? 0
            totalUnits += units

            let refund = row["Refund"] ?? ""
            if refund.lowercased() == "yes" {
                totalRefunds += units
            }

            let currency = row["Proceeds Currency"] ?? row["Customer Currency"] ?? ""
            let proceeds = Double(row["Developer Proceeds"] ?? "") ?? 0.0
            if !currency.isEmpty {
                proceedsByCurrency[currency, default: 0.0] += proceeds
            }

            let country = row["Country"] ?? ""
            if !country.isEmpty {
                unitsByCountry[country, default: 0] += units
            }

            let subName = row["Subscription Name"] ?? ""
            if !subName.isEmpty {
                unitsByProduct[subName, default: 0] += units
            }

            let subscriberId = row["Subscriber ID"] ?? ""
            if !subscriberId.isEmpty {
                uniqueSubscribers.insert(subscriberId)
            }
        }

        let roundedProceeds = proceedsByCurrency.mapValues { (value: Double) -> Double in
            (value * 100).rounded() / 100
        }

        let topCountries = unitsByCountry
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { ["country": $0.key, "units": $0.value] as [String: Any] }

        var summary: [String: Any] = [
            "total_units": totalUnits,
            "total_refunds": totalRefunds,
            "unique_subscribers": uniqueSubscribers.count,
            "proceeds_by_currency": roundedProceeds,
            "by_product": unitsByProduct
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
        var totalQuantity = 0
        var partnerShareByCurrency: [String: Double] = [:]
        var quantityByCountry: [String: Int] = [:]

        for row in rows {
            let quantity = Int(row["Quantity"] ?? "") ?? 0
            totalQuantity += quantity

            let currency = row["Partner Share Currency"] ?? row["Currency of Proceeds"] ?? ""
            let partnerShare = Double(row["Partner Share"] ?? "") ?? 0.0
            if !currency.isEmpty {
                partnerShareByCurrency[currency, default: 0.0] += partnerShare
            }

            let country = row["Country Of Sale (Region)"] ?? row["Country or Region"] ?? ""
            if !country.isEmpty {
                quantityByCountry[country, default: 0] += quantity
            }
        }

        // Round partner share to 2 decimal places
        let roundedPartnerShare = partnerShareByCurrency.mapValues { (value: Double) -> Double in
            (value * 100).rounded() / 100
        }

        // Top countries by quantity (descending), max 10
        let topCountries = quantityByCountry
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { ["country": $0.key, "quantity": $0.value] as [String: Any] }

        var summary: [String: Any] = [
            "total_quantity": totalQuantity,
            "partner_share_by_currency": roundedPartnerShare
        ]

        if !topCountries.isEmpty {
            summary["top_countries"] = topCountries
        }

        return summary
    }
}
