import Testing
import Foundation
@testable import asc_mcp

@Suite("TSVParser Tests")
struct TSVParserTests {

    @Test func parseEmpty() throws {
        let result = try TSVParser.parse(data: "")
        #expect(result.headers.isEmpty)
        #expect(result.rows.isEmpty)
        #expect(result.totalRowCount == 0)
    }

    @Test func parseHeaderOnly() throws {
        let result = try TSVParser.parse(data: "Col1\tCol2\tCol3")
        #expect(result.headers == ["Col1", "Col2", "Col3"])
        #expect(result.rows.isEmpty)
        #expect(result.totalRowCount == 0)
    }

    @Test func parseSingleRow() throws {
        let tsv = "Name\tAge\nAlice\t30"
        let result = try TSVParser.parse(data: tsv)
        #expect(result.headers == ["Name", "Age"])
        #expect(result.rows.count == 1)
        #expect(result.rows[0]["Name"] == "Alice")
        #expect(result.rows[0]["Age"] == "30")
        #expect(result.totalRowCount == 1)
    }

    @Test func parseMultipleRows() throws {
        let tsv = "Provider\tSKU\tUnits\nAPPLE\tcom.app\t10\nAPPLE\tcom.app2\t5\nAPPLE\tcom.app3\t3"
        let result = try TSVParser.parse(data: tsv)
        #expect(result.headers == ["Provider", "SKU", "Units"])
        #expect(result.rows.count == 3)
        #expect(result.totalRowCount == 3)
        #expect(result.rows[0]["SKU"] == "com.app")
        #expect(result.rows[2]["Units"] == "3")
    }

    @Test func parseLimitRows() throws {
        let tsv = "A\tB\n1\t2\n3\t4\n5\t6\n7\t8"
        let result = try TSVParser.parse(data: tsv, limit: 2)
        #expect(result.rows.count == 2)
        #expect(result.totalRowCount == 4)
        #expect(result.rows[0]["A"] == "1")
        #expect(result.rows[1]["A"] == "3")
    }

    @Test func parseLimitExceedsRows() throws {
        let tsv = "X\n1\n2"
        let result = try TSVParser.parse(data: tsv, limit: 100)
        #expect(result.rows.count == 2)
        #expect(result.totalRowCount == 2)
    }

    @Test func parseLimitZero() throws {
        let tsv = "X\n1\n2\n3"
        let result = try TSVParser.parse(data: tsv, limit: 0)
        #expect(result.rows.isEmpty)
        #expect(result.totalRowCount == 3)
    }

    @Test func parseFiltersRowsWithoutChangingSourceCount() throws {
        let tsv = "App ID\tUnits\n111\t1\n222\t2\n111\t3"
        let result = try TSVParser.parse(data: tsv) { row in
            row["App ID"] == "111"
        }

        #expect(result.rows.count == 2)
        #expect(result.rows.map { $0["Units"] } == ["1", "3"])
        #expect(result.totalRowCount == 3)
    }

    @Test func parseAppliesFilterBeforeLimit() throws {
        let tsv = "App ID\tUnits\n222\t1\n111\t2\n111\t3"
        let result = try TSVParser.parse(data: tsv, limit: 1) { row in
            row["App ID"] == "111"
        }

        #expect(result.rows.map { $0["Units"] } == ["2"])
        #expect(result.totalRowCount == 3)
    }

    @Test func parseRejectsTinyRowAmplificationAtRetentionThreshold() {
        let limits = TSVParsingLimits(
            maximumColumns: 4,
            maximumScannedRows: 10,
            maximumScannedCells: 20,
            maximumRetainedRows: 2,
            maximumRetainedCells: 10
        )
        let tsv = "A\nx\nx\nx"

        #expect(throws: TSVParsingError.retainedRowLimitExceeded(limit: 2)) {
            try TSVParser.parse(data: tsv, limits: limits)
        }
    }

    @Test func parseRejectsCellAmplificationBeforeAppending() {
        let limits = TSVParsingLimits(
            maximumColumns: 4,
            maximumScannedRows: 10,
            maximumScannedCells: 20,
            maximumRetainedRows: 10,
            maximumRetainedCells: 3
        )
        let tsv = "A\tB\n1\t2\n3\t4"

        #expect(throws: TSVParsingError.retainedCellLimitExceeded(limit: 3)) {
            try TSVParser.parse(data: tsv, limits: limits)
        }
    }

    @Test func parseRejectsColumnAmplificationBeforeMaterializingFields() {
        let limits = TSVParsingLimits(
            maximumColumns: 2,
            maximumScannedRows: 10,
            maximumScannedCells: 20,
            maximumRetainedRows: 10,
            maximumRetainedCells: 10
        )

        #expect(throws: TSVParsingError.columnLimitExceeded(limit: 2)) {
            try TSVParser.parse(data: "A\tB\tC\n1\t2\t3", limits: limits)
        }
        #expect(throws: TSVParsingError.columnLimitExceeded(limit: 2)) {
            try TSVParser.parse(data: "A\n1\t2\t3", limits: limits)
        }
    }

    @Test func parseAcceptsScannedRowBoundaryWhenFilterRejectsTinyRows() throws {
        let limits = TSVParsingLimits(
            maximumColumns: 2,
            maximumScannedRows: 3,
            maximumScannedCells: 10,
            maximumRetainedRows: 1,
            maximumRetainedCells: 1
        )
        let result = try TSVParser.parse(
            data: "App ID\nx\nx\nx",
            limits: limits,
            including: { _ in false }
        )

        #expect(result.totalRowCount == 3)
        #expect(result.rows.isEmpty)
    }

    @Test func parseRejectsScannedRowOverageBeforeMaterializingTheRow() {
        let limits = TSVParsingLimits(
            maximumColumns: 2,
            maximumScannedRows: 2,
            maximumScannedCells: 10,
            maximumRetainedRows: 1,
            maximumRetainedCells: 1
        )

        #expect(throws: TSVParsingError.scannedRowLimitExceeded(limit: 2)) {
            try TSVParser.parse(
                data: "App ID\nx\nx\nx\ty\tz",
                limits: limits,
                including: { _ in false }
            )
        }
    }

    @Test func parseAcceptsScannedCellBoundaryWhenFilterRejectsRows() throws {
        let limits = TSVParsingLimits(
            maximumColumns: 3,
            maximumScannedRows: 10,
            maximumScannedCells: 6,
            maximumRetainedRows: 1,
            maximumRetainedCells: 1
        )
        let result = try TSVParser.parse(
            data: "A\tB\tC\nx\nx",
            limits: limits,
            including: { _ in false }
        )

        #expect(result.totalRowCount == 2)
        #expect(result.rows.isEmpty)
    }

    @Test func parseRejectsScannedCellOverageBeforeDictionaryConstruction() {
        let limits = TSVParsingLimits(
            maximumColumns: 3,
            maximumScannedRows: 10,
            maximumScannedCells: 5,
            maximumRetainedRows: 1,
            maximumRetainedCells: 1
        )

        #expect(throws: TSVParsingError.scannedCellLimitExceeded(limit: 5)) {
            try TSVParser.parse(
                data: "A\tB\tC\nx\nx",
                limits: limits,
                including: { _ in false }
            )
        }
        #expect(throws: TSVParsingError.scannedCellLimitExceeded(limit: 5)) {
            try TSVParser.parse(
                data: "A\nx\ty\tz\nx\ty\tz",
                limits: limits,
                including: { _ in false }
            )
        }
    }

    @Test func parseTrailingNewline() throws {
        let tsv = "Col\nVal1\nVal2\n"
        let result = try TSVParser.parse(data: tsv)
        #expect(result.rows.count == 2)
        #expect(result.totalRowCount == 2)
    }

    @Test func parseFewerValuesThanHeaders() throws {
        let tsv = "A\tB\tC\n1\t2"
        let result = try TSVParser.parse(data: tsv)
        #expect(result.rows.count == 1)
        #expect(result.rows[0]["A"] == "1")
        #expect(result.rows[0]["B"] == "2")
        #expect(result.rows[0]["C"] == "")
    }

    @Test func parseSalesReport() throws {
        let tsv = """
        Provider\tProvider Country\tSKU\tDeveloper\tTitle\tVersion\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCountry Code
        APPLE\tUS\tcom.app.pro\tDev Inc\tMy App\t1.0\t1F\t10\t6.99\tUSD\tUS
        APPLE\tUS\tcom.app.pro\tDev Inc\tMy App\t1.0\t1F\t5\t6.99\tEUR\tDE
        """
        let result = try TSVParser.parse(data: tsv)
        #expect(result.headers.contains("SKU"))
        #expect(result.headers.contains("Units"))
        #expect(result.rows.count == 2)
        #expect(result.rows[0]["Country Code"] == "US")
        #expect(result.rows[1]["Currency of Proceeds"] == "EUR")
    }

    @Test func parseFinancialReport() throws {
        let tsv = """
        Start Date\tEnd Date\tCountry Of Sale (Region)\tQuantity\tPartner Share\tPartner Share Currency\tSKU
        01/01/2025\t01/31/2025\tUS\t100\t699.00\tUSD\tcom.app
        01/01/2025\t01/31/2025\tDE\t25\t175.00\tEUR\tcom.app
        """
        let result = try TSVParser.parse(data: tsv)
        #expect(result.headers.contains("Quantity"))
        #expect(result.headers.contains("Partner Share"))
        #expect(result.rows.count == 2)
        #expect(result.rows[0]["Country Of Sale (Region)"] == "US")
    }
}
