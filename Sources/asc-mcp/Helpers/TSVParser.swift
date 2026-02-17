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

/// Parses TSV (tab-separated values) data from App Store Connect reports
enum TSVParser {
    /// Parses TSV string into structured data
    /// - Parameters:
    ///   - data: TSV string with tab-separated columns and newline-separated rows
    ///   - limit: Maximum number of data rows to return (nil = all rows)
    /// - Returns: Parsed TSV result with headers, rows, and total count
    static func parse(data: String, limit: Int? = nil) -> TSVResult {
        let lines = data.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard let headerLine = lines.first else {
            return TSVResult(headers: [], rows: [], totalRowCount: 0)
        }

        let headers = headerLine.components(separatedBy: "\t")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let dataLines = Array(lines.dropFirst())
        let totalRowCount = dataLines.count

        let rowLimit = limit ?? totalRowCount
        let limitedLines = dataLines.prefix(max(rowLimit, 0))

        let rows: [[String: String]] = limitedLines.map { line in
            let values = line.components(separatedBy: "\t")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            var dict: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                dict[header] = index < values.count ? values[index] : ""
            }
            return dict
        }

        return TSVResult(headers: headers, rows: rows, totalRowCount: totalRowCount)
    }
}
