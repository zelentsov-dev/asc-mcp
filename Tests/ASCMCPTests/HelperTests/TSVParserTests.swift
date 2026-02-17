import Testing
import Foundation
@testable import asc_mcp

@Suite("TSVParser Tests")
struct TSVParserTests {

    @Test func parseEmpty() {
        let result = TSVParser.parse(data: "")
        #expect(result.headers.isEmpty)
        #expect(result.rows.isEmpty)
        #expect(result.totalRowCount == 0)
    }

    @Test func parseHeaderOnly() {
        let result = TSVParser.parse(data: "Col1\tCol2\tCol3")
        #expect(result.headers == ["Col1", "Col2", "Col3"])
        #expect(result.rows.isEmpty)
        #expect(result.totalRowCount == 0)
    }

    @Test func parseSingleRow() {
        let tsv = "Name\tAge\nAlice\t30"
        let result = TSVParser.parse(data: tsv)
        #expect(result.headers == ["Name", "Age"])
        #expect(result.rows.count == 1)
        #expect(result.rows[0]["Name"] == "Alice")
        #expect(result.rows[0]["Age"] == "30")
        #expect(result.totalRowCount == 1)
    }

    @Test func parseMultipleRows() {
        let tsv = "Provider\tSKU\tUnits\nAPPLE\tcom.app\t10\nAPPLE\tcom.app2\t5\nAPPLE\tcom.app3\t3"
        let result = TSVParser.parse(data: tsv)
        #expect(result.headers == ["Provider", "SKU", "Units"])
        #expect(result.rows.count == 3)
        #expect(result.totalRowCount == 3)
        #expect(result.rows[0]["SKU"] == "com.app")
        #expect(result.rows[2]["Units"] == "3")
    }

    @Test func parseLimitRows() {
        let tsv = "A\tB\n1\t2\n3\t4\n5\t6\n7\t8"
        let result = TSVParser.parse(data: tsv, limit: 2)
        #expect(result.rows.count == 2)
        #expect(result.totalRowCount == 4)
        #expect(result.rows[0]["A"] == "1")
        #expect(result.rows[1]["A"] == "3")
    }

    @Test func parseLimitExceedsRows() {
        let tsv = "X\n1\n2"
        let result = TSVParser.parse(data: tsv, limit: 100)
        #expect(result.rows.count == 2)
        #expect(result.totalRowCount == 2)
    }

    @Test func parseLimitZero() {
        let tsv = "X\n1\n2\n3"
        let result = TSVParser.parse(data: tsv, limit: 0)
        #expect(result.rows.isEmpty)
        #expect(result.totalRowCount == 3)
    }

    @Test func parseTrailingNewline() {
        let tsv = "Col\nVal1\nVal2\n"
        let result = TSVParser.parse(data: tsv)
        #expect(result.rows.count == 2)
        #expect(result.totalRowCount == 2)
    }

    @Test func parseFewerValuesThanHeaders() {
        let tsv = "A\tB\tC\n1\t2"
        let result = TSVParser.parse(data: tsv)
        #expect(result.rows.count == 1)
        #expect(result.rows[0]["A"] == "1")
        #expect(result.rows[0]["B"] == "2")
        #expect(result.rows[0]["C"] == "")
    }

    @Test func parseSalesReport() {
        let tsv = """
        Provider\tProvider Country\tSKU\tDeveloper\tTitle\tVersion\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCountry Code
        APPLE\tUS\tcom.app.pro\tDev Inc\tMy App\t1.0\t1F\t10\t6.99\tUSD\tUS
        APPLE\tUS\tcom.app.pro\tDev Inc\tMy App\t1.0\t1F\t5\t6.99\tEUR\tDE
        """
        let result = TSVParser.parse(data: tsv)
        #expect(result.headers.contains("SKU"))
        #expect(result.headers.contains("Units"))
        #expect(result.rows.count == 2)
        #expect(result.rows[0]["Country Code"] == "US")
        #expect(result.rows[1]["Currency of Proceeds"] == "EUR")
    }

    @Test func parseFinancialReport() {
        let tsv = """
        Start Date\tEnd Date\tCountry Of Sale (Region)\tQuantity\tPartner Share\tPartner Share Currency\tSKU
        01/01/2025\t01/31/2025\tUS\t100\t699.00\tUSD\tcom.app
        01/01/2025\t01/31/2025\tDE\t25\t175.00\tEUR\tcom.app
        """
        let result = TSVParser.parse(data: tsv)
        #expect(result.headers.contains("Quantity"))
        #expect(result.headers.contains("Partner Share"))
        #expect(result.rows.count == 2)
        #expect(result.rows[0]["Country Of Sale (Region)"] == "US")
    }
}
