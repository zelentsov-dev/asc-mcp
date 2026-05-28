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
        // Apple's `Developer Proceeds` column is per-unit. Each row represents `Units`
        // sales at `Developer Proceeds` each, so the row's contribution to the total is
        // Units × Developer Proceeds.
        let rows: [[String: String]] = [
            ["Units": "10", "Developer Proceeds": "6.99", "Currency of Proceeds": "USD"],
            ["Units": "5",  "Developer Proceeds": "6.99", "Currency of Proceeds": "EUR"],
            ["Units": "3",  "Developer Proceeds": "6.70", "Currency of Proceeds": "USD"]
        ]
        let summary = ReportSummary.salesSummary(from: rows)
        let proceeds = summary["proceeds_by_currency"] as? [String: Double]
        // USD: 10 × 6.99 + 3 × 6.70 = 69.90 + 20.10 = 90.00
        #expect(proceeds?["USD"] == 90.0)
        // EUR: 5 × 6.99 = 34.95
        #expect(proceeds?["EUR"] == 34.95)
    }

    @Test func salesSummary_proceedsScalesWithUnits() {
        // Regression test: previously `Developer Proceeds` was summed directly,
        // ignoring `Units`, which undercounted multi-unit rows.
        let rows: [[String: String]] = [
            // 100 sales at $0.70 each in one aggregated row.
            ["Units": "100", "Developer Proceeds": "0.70", "Currency of Proceeds": "USD"]
        ]
        let summary = ReportSummary.salesSummary(from: rows)
        let proceeds = summary["proceeds_by_currency"] as? [String: Double]
        #expect(proceeds?["USD"] == 70.0) // 100 × 0.70, not 0.70
    }

    @Test func salesSummary_perAppProceedsScalesWithUnits() {
        // Same regression for the per-app breakdown (by_app).
        let rows: [[String: String]] = [
            ["Title": "MyApp", "Units": "10", "Developer Proceeds": "0.70", "Currency of Proceeds": "USD"],
            ["Title": "MyApp", "Units": "5",  "Developer Proceeds": "0.62", "Currency of Proceeds": "EUR"]
        ]
        let summary = ReportSummary.salesSummary(from: rows)
        let byApp = summary["by_app"] as? [[String: Any]]
        #expect(byApp?.count == 1)
        let stats = byApp?.first?["proceeds_by_currency"] as? [String: Double]
        #expect(stats?["USD"] == 7.0)  // 10 × 0.70
        #expect(stats?["EUR"] == 3.10) // 5 × 0.62
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
        // Each row has Units=1 so row proceeds == per-unit proceeds.
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

    // MARK: - Summary Router

    @Test func summaryRouter_sales() {
        let rows: [[String: String]] = [["Units": "5"]]
        let summary = ReportSummary.summary(for: "SALES", from: rows)
        #expect(summary["total_units"] as? Int == 5)
    }

    @Test func summaryRouter_subscription() {
        let rows: [[String: String]] = [["Active Standard Price Subscriptions": "10"]]
        let summary = ReportSummary.summary(for: "SUBSCRIPTION", from: rows)
        #expect(summary["active_standard_subscriptions"] as? Int == 10)
    }

    @Test func summaryRouter_subscriptionEvent() {
        let rows: [[String: String]] = [["Event": "Renew", "Quantity": "3"]]
        let summary = ReportSummary.summary(for: "SUBSCRIPTION_EVENT", from: rows)
        #expect(summary["total_events"] as? Int == 3)
    }

    @Test func summaryRouter_subscriber() {
        let rows: [[String: String]] = [["Units": "1", "Subscriber ID": "abc"]]
        let summary = ReportSummary.summary(for: "SUBSCRIBER", from: rows)
        #expect(summary["unique_subscribers"] as? Int == 1)
    }

    @Test func summaryRouter_preOrder_fallsBackToSales() {
        let rows: [[String: String]] = [["Units": "7"]]
        let summary = ReportSummary.summary(for: "PRE_ORDER", from: rows)
        #expect(summary["total_units"] as? Int == 7)
    }

    // MARK: - Subscription Summary

    @Test func subscriptionSummary_empty() {
        let summary = ReportSummary.subscriptionSummary(from: [])
        #expect(summary["active_standard_subscriptions"] as? Int == 0)
        #expect(summary["active_free_trials"] as? Int == 0)
        #expect(summary["total_subscribers"] as? Int == 0)
    }

    @Test func subscriptionSummary_aggregates() {
        let rows: [[String: String]] = [
            ["Active Standard Price Subscriptions": "100", "Active Free Trial Introductory Offer Subscriptions": "20", "Billing Retry": "5", "Grace Period": "3", "Marketing Opt-Ins": "10", "Subscribers": "120", "Country": "US", "Subscription Name": "Pro Monthly"],
            ["Active Standard Price Subscriptions": "50", "Active Free Trial Introductory Offer Subscriptions": "10", "Billing Retry": "2", "Grace Period": "1", "Marketing Opt-Ins": "5", "Subscribers": "55", "Country": "DE", "Subscription Name": "Pro Annual"]
        ]
        let summary = ReportSummary.subscriptionSummary(from: rows)
        #expect(summary["active_standard_subscriptions"] as? Int == 150)
        #expect(summary["active_free_trials"] as? Int == 30)
        #expect(summary["billing_retry"] as? Int == 7)
        #expect(summary["grace_period"] as? Int == 4)
        #expect(summary["total_subscribers"] as? Int == 175)

        let byProduct = summary["by_product"] as? [String: Int]
        #expect(byProduct?["Pro Monthly"] == 120)
        #expect(byProduct?["Pro Annual"] == 60)
    }

    // MARK: - Subscription Event Summary

    @Test func subscriptionEventSummary_empty() {
        let summary = ReportSummary.subscriptionEventSummary(from: [])
        #expect(summary["total_events"] as? Int == 0)
    }

    @Test func subscriptionEventSummary_byEventType() {
        let rows: [[String: String]] = [
            ["Event": "Subscribe", "Quantity": "10", "Country": "US", "Subscription Name": "Pro"],
            ["Event": "Renew", "Quantity": "50", "Country": "US", "Subscription Name": "Pro"],
            ["Event": "Cancel", "Quantity": "3", "Country": "DE", "Subscription Name": "Pro"],
            ["Event": "Subscribe", "Quantity": "5", "Country": "JP", "Subscription Name": "Basic"]
        ]
        let summary = ReportSummary.subscriptionEventSummary(from: rows)
        #expect(summary["total_events"] as? Int == 68)

        let byEvent = summary["by_event_type"] as? [String: Int]
        #expect(byEvent?["Subscribe"] == 15)
        #expect(byEvent?["Renew"] == 50)
        #expect(byEvent?["Cancel"] == 3)

        let byProduct = summary["by_product"] as? [String: Int]
        #expect(byProduct?["Pro"] == 63)
        #expect(byProduct?["Basic"] == 5)
    }

    // MARK: - Subscriber Summary

    @Test func subscriberSummary_empty() {
        let summary = ReportSummary.subscriberSummary(from: [])
        #expect(summary["total_units"] as? Int == 0)
        #expect(summary["unique_subscribers"] as? Int == 0)
    }

    @Test func subscriberSummary_uniqueSubscribersAndRefunds() {
        let rows: [[String: String]] = [
            ["Units": "1", "Subscriber ID": "AAA", "Refund": "No", "Developer Proceeds": "9.99", "Proceeds Currency": "USD", "Country": "US", "Subscription Name": "Pro"],
            ["Units": "1", "Subscriber ID": "BBB", "Refund": "Yes", "Developer Proceeds": "9.99", "Proceeds Currency": "USD", "Country": "US", "Subscription Name": "Pro"],
            ["Units": "1", "Subscriber ID": "AAA", "Refund": "No", "Developer Proceeds": "9.99", "Proceeds Currency": "USD", "Country": "US", "Subscription Name": "Pro"]
        ]
        let summary = ReportSummary.subscriberSummary(from: rows)
        #expect(summary["total_units"] as? Int == 3)
        #expect(summary["total_refunds"] as? Int == 1)
        #expect(summary["unique_subscribers"] as? Int == 2)

        let proceeds = summary["proceeds_by_currency"] as? [String: Double]
        #expect(proceeds?["USD"] == 29.97)
    }
}
