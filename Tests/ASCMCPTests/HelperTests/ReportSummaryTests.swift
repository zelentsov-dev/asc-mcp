import Testing
import Foundation
@testable import asc_mcp

@Suite("ReportSummary Tests")
struct ReportSummaryTests {

    // MARK: - Sales Summary

    @Test func salesSummary_empty() {
        let summary = ReportSummary.salesSummary(from: [])
        #expect(summary["total_units"] as? Int == 0)
        let proceeds = summary["proceeds_by_currency"] as? [String: Double]
        #expect(proceeds?.isEmpty == true)
    }

    @Test func salesSummary_totalUnits() {
        let rows: [[String: String]] = [
            ["Units": "10", "Country Code": "US", "Product Type Identifier": "1F", "Developer Proceeds": "69.90", "Currency of Proceeds": "USD"],
            ["Units": "5", "Country Code": "DE", "Product Type Identifier": "1F", "Developer Proceeds": "34.95", "Currency of Proceeds": "EUR"],
            ["Units": "3", "Country Code": "US", "Product Type Identifier": "7", "Developer Proceeds": "2.97", "Currency of Proceeds": "USD"]
        ]
        let summary = ReportSummary.salesSummary(from: rows)
        #expect(summary["total_units"] as? Int == 18)
    }

    @Test func salesSummary_proceedsByCurrency() {
        let rows: [[String: String]] = [
            ["Units": "10", "Developer Proceeds": "69.90", "Currency of Proceeds": "USD"],
            ["Units": "5", "Developer Proceeds": "34.95", "Currency of Proceeds": "EUR"],
            ["Units": "3", "Developer Proceeds": "20.10", "Currency of Proceeds": "USD"]
        ]
        let summary = ReportSummary.salesSummary(from: rows)
        let proceeds = summary["proceeds_by_currency"] as? [String: Double]
        #expect(proceeds?["USD"] == 90.0)
        #expect(proceeds?["EUR"] == 34.95)
    }

    @Test func salesSummary_topCountries() {
        let rows: [[String: String]] = [
            ["Units": "50", "Country Code": "US"],
            ["Units": "30", "Country Code": "US"],
            ["Units": "20", "Country Code": "DE"],
            ["Units": "10", "Country Code": "JP"]
        ]
        let summary = ReportSummary.salesSummary(from: rows)
        let topCountries = summary["top_countries"] as? [[String: Any]]
        #expect(topCountries != nil)
        #expect(topCountries?.count == 3)
        // US should be first (80 units)
        #expect(topCountries?[0]["country"] as? String == "US")
        #expect(topCountries?[0]["units"] as? Int == 80)
    }

    @Test func salesSummary_byProductType() {
        let rows: [[String: String]] = [
            ["Units": "10", "Product Type Identifier": "1F"],
            ["Units": "5", "Product Type Identifier": "7"],
            ["Units": "3", "Product Type Identifier": "1F"]
        ]
        let summary = ReportSummary.salesSummary(from: rows)
        let byType = summary["by_product_type"] as? [String: Int]
        #expect(byType?["1F"] == 13)
        #expect(byType?["7"] == 5)
    }

    @Test func salesSummary_proceedsRounding() {
        let rows: [[String: String]] = [
            ["Units": "1", "Developer Proceeds": "1.111", "Currency of Proceeds": "USD"],
            ["Units": "1", "Developer Proceeds": "2.222", "Currency of Proceeds": "USD"]
        ]
        let summary = ReportSummary.salesSummary(from: rows)
        let proceeds = summary["proceeds_by_currency"] as? [String: Double]
        #expect(proceeds?["USD"] == 3.33)
    }

    // MARK: - Financial Summary

    @Test func financialSummary_empty() {
        let summary = ReportSummary.financialSummary(from: [])
        #expect(summary["total_quantity"] as? Int == 0)
        let partnerShare = summary["partner_share_by_currency"] as? [String: Double]
        #expect(partnerShare?.isEmpty == true)
    }

    @Test func financialSummary_totalQuantity() {
        let rows: [[String: String]] = [
            ["Quantity": "100", "Partner Share": "699.00", "Partner Share Currency": "USD", "Country Of Sale (Region)": "US"],
            ["Quantity": "25", "Partner Share": "175.00", "Partner Share Currency": "EUR", "Country Of Sale (Region)": "DE"]
        ]
        let summary = ReportSummary.financialSummary(from: rows)
        #expect(summary["total_quantity"] as? Int == 125)
    }

    @Test func financialSummary_partnerShareByCurrency() {
        let rows: [[String: String]] = [
            ["Quantity": "10", "Partner Share": "100.50", "Partner Share Currency": "USD"],
            ["Quantity": "5", "Partner Share": "50.25", "Partner Share Currency": "EUR"],
            ["Quantity": "3", "Partner Share": "30.75", "Partner Share Currency": "USD"]
        ]
        let summary = ReportSummary.financialSummary(from: rows)
        let share = summary["partner_share_by_currency"] as? [String: Double]
        #expect(share?["USD"] == 131.25)
        #expect(share?["EUR"] == 50.25)
    }

    @Test func financialSummary_topCountries() {
        let rows: [[String: String]] = [
            ["Quantity": "100", "Country Of Sale (Region)": "US"],
            ["Quantity": "50", "Country Of Sale (Region)": "DE"],
            ["Quantity": "25", "Country Of Sale (Region)": "JP"]
        ]
        let summary = ReportSummary.financialSummary(from: rows)
        let topCountries = summary["top_countries"] as? [[String: Any]]
        #expect(topCountries?.count == 3)
        #expect(topCountries?[0]["country"] as? String == "US")
        #expect(topCountries?[0]["quantity"] as? Int == 100)
    }

    @Test func financialSummary_missingFields() {
        // Rows with missing/empty fields shouldn't crash
        let rows: [[String: String]] = [
            ["Quantity": "", "Partner Share": "abc"],
            ["SomeOtherField": "value"]
        ]
        let summary = ReportSummary.financialSummary(from: rows)
        #expect(summary["total_quantity"] as? Int == 0)
    }
}
