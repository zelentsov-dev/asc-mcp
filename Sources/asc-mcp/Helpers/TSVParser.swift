//
//  TSVParser.swift
//  asc-mcp
//
//  Parses tab-separated values (TSV) data from ASC reports
//

import Foundation

/// Result of TSV parsing
struct TSVResult: Sendable {
    /// Column headers from the first row
    let headers: [String]
    /// Parsed rows as dictionaries [header: value], limited by `limit`
    let rows: [[String: String]]
    /// Total number of data rows in the original TSV (before limit)
    let totalRowCount: Int
}

struct TSVParsingLimits: Equatable, Sendable {
    let maximumColumns: Int
    let maximumScannedRows: Int
    let maximumScannedCells: Int
    let maximumRetainedRows: Int
    let maximumRetainedCells: Int

    static let reportDefault = TSVParsingLimits(
        maximumColumns: ReportDataLimits.maximumTSVColumns,
        maximumScannedRows: ReportDataLimits.maximumScannedTSVRows,
        maximumScannedCells: ReportDataLimits.maximumScannedTSVCells,
        maximumRetainedRows: ReportDataLimits.maximumRetainedTSVRows,
        maximumRetainedCells: ReportDataLimits.maximumRetainedTSVCells
    )
}

enum TSVParsingError: Error, Equatable, LocalizedError, Sendable {
    case columnLimitExceeded(limit: Int)
    case scannedRowLimitExceeded(limit: Int)
    case scannedCellLimitExceeded(limit: Int)
    case retainedRowLimitExceeded(limit: Int)
    case retainedCellLimitExceeded(limit: Int)

    var errorDescription: String? {
        switch self {
        case .columnLimitExceeded(let limit):
            return "TSV report exceeds the safety limit of \(limit) columns. Request a narrower report or process it outside this MCP."
        case .scannedRowLimitExceeded(let limit):
            return "TSV report exceeds the safety limit of \(limit) scanned rows. Request a smaller reporting period or process it outside this MCP."
        case .scannedCellLimitExceeded(let limit):
            return "TSV report exceeds the safety limit of \(limit) scanned data cells. Request a smaller or narrower report, or process it outside this MCP."
        case .retainedRowLimitExceeded(let limit):
            return "TSV report exceeds the safety limit of \(limit) matched rows. Add an app_id filter, request a narrower report, or process it outside this MCP."
        case .retainedCellLimitExceeded(let limit):
            return "TSV report exceeds the safety limit of \(limit) retained cells. Add an app_id filter, request a narrower report, or process it outside this MCP."
        }
    }
}

/// Parses TSV (tab-separated values) data from App Store Connect reports
enum TSVParser {
    /// Parses TSV string into structured data
    /// - Parameters:
    ///   - data: TSV string with tab-separated columns and newline-separated rows
    ///   - limit: Maximum number of data rows to return (nil = all rows)
    ///   - limits: Maximum materialized columns, scanned rows and cells, and retained rows and cells
    ///   - shouldInclude: Optional row predicate applied before the limit
    /// - Returns: Parsed TSV result with headers, rows, and total count
    static func parse(
        data: String,
        limit: Int? = nil,
        limits: TSVParsingLimits = .reportDefault,
        including shouldInclude: (([String: String]) -> Bool)? = nil
    ) throws -> TSVResult {
        let rowLimit = max(limit ?? Int.max, 0)
        var headers: [String]?
        var rows: [[String: String]] = []
        if rowLimit != Int.max {
            rows.reserveCapacity(min(rowLimit, 1_024))
        }
        var totalRowCount = 0
        var scannedCellCount = 0
        var retainedCellCount = 0
        var lineStart = data.startIndex

        while lineStart < data.endIndex {
            let newline = data[lineStart...].firstIndex(of: "\n")
            let lineEnd = newline ?? data.endIndex
            let line = data[lineStart ..< lineEnd]

            if !line.allSatisfy({ $0.isWhitespace }) {
                if headers == nil {
                    headers = try fields(in: line, maximumCount: limits.maximumColumns)
                } else {
                    guard totalRowCount < limits.maximumScannedRows else {
                        throw TSVParsingError.scannedRowLimitExceeded(
                            limit: limits.maximumScannedRows
                        )
                    }
                    totalRowCount += 1

                    if rows.count < rowLimit, let headers {
                        let values = try fields(in: line, maximumCount: limits.maximumColumns)
                        let materializedCellCount = max(headers.count, values.count)
                        guard scannedCellCount <= limits.maximumScannedCells,
                              materializedCellCount <= limits.maximumScannedCells - scannedCellCount else {
                            throw TSVParsingError.scannedCellLimitExceeded(
                                limit: limits.maximumScannedCells
                            )
                        }
                        scannedCellCount += materializedCellCount

                        var dict: [String: String] = [:]
                        dict.reserveCapacity(headers.count)
                        for (index, header) in headers.enumerated() {
                            dict[header] = index < values.count ? values[index] : ""
                        }

                        if shouldInclude?(dict) ?? true {
                            guard rows.count < limits.maximumRetainedRows else {
                                throw TSVParsingError.retainedRowLimitExceeded(
                                    limit: limits.maximumRetainedRows
                                )
                            }
                            guard retainedCellCount <= limits.maximumRetainedCells,
                                  headers.count <= limits.maximumRetainedCells - retainedCellCount else {
                                throw TSVParsingError.retainedCellLimitExceeded(
                                    limit: limits.maximumRetainedCells
                                )
                            }
                            rows.append(dict)
                            retainedCellCount += headers.count
                        }
                    }
                }
            }

            guard let newline else { break }
            lineStart = data.index(after: newline)
        }

        guard let headers else {
            return TSVResult(headers: [], rows: [], totalRowCount: 0)
        }
        return TSVResult(headers: headers, rows: rows, totalRowCount: totalRowCount)
    }

    private static func fields(in line: Substring, maximumCount: Int) throws -> [String] {
        var result: [String] = []
        result.reserveCapacity(min(max(maximumCount, 0), 32))
        var fieldStart = line.startIndex

        while true {
            guard result.count < maximumCount else {
                throw TSVParsingError.columnLimitExceeded(limit: maximumCount)
            }
            let separator = line[fieldStart...].firstIndex(of: "\t")
            let fieldEnd = separator ?? line.endIndex
            result.append(
                String(line[fieldStart ..< fieldEnd])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )

            guard let separator else { break }
            fieldStart = line.index(after: separator)
        }
        return result
    }
}
