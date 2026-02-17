//
//  ReportSummary.swift
//  asc-mcp
//
//  Generates summaries for ASC sales and financial reports
//

import Foundation

/// Generates summary statistics from parsed report rows
enum ReportSummary {

    // MARK: - Sales Report Summary

    /// Creates a summary for a sales report
    /// - Parameter rows: All parsed TSV rows (not limited)
    /// - Returns: Dictionary with summary statistics
    static func salesSummary(from rows: [[String: String]]) -> [String: Any] {
        var totalUnits = 0
        var proceedsByCurrency: [String: Double] = [:]
        var unitsByCountry: [String: Int] = [:]
        var unitsByProductType: [String: Int] = [:]

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

        var summary: [String: Any] = [
            "total_units": totalUnits,
            "proceeds_by_currency": roundedProceeds,
            "by_product_type": unitsByProductType
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
