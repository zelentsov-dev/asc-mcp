//
//  AnalyticsWorker+Handlers.swift
//  asc-mcp
//
//  Implementation of analytics and reports handlers
//

import Foundation
import MCP

extension AnalyticsWorker {

    /// Gets a sales/download report from App Store Connect
    /// - Returns: CSV data with sales metrics or base64-encoded gzip data
    /// - Throws: Error if required parameters are missing or API call fails
    func getSalesReport(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let vendorNumber = arguments["vendor_number"]?.stringValue,
              let reportType = arguments["report_type"]?.stringValue,
              let reportSubType = arguments["report_sub_type"]?.stringValue,
              let frequency = arguments["frequency"]?.stringValue,
              let reportDate = arguments["report_date"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Missing required parameters: vendor_number, report_type, report_sub_type, frequency, report_date")],
                isError: true
            )
        }

        do {
            let queryParams: [String: String] = [
                "filter[vendorNumber]": vendorNumber,
                "filter[reportType]": reportType,
                "filter[reportSubType]": reportSubType,
                "filter[frequency]": frequency,
                "filter[reportDate]": reportDate
            ]

            let data = try await httpClient.getRaw("/v1/salesReports", parameters: queryParams, accept: "application/a-gzip")

            // Reports return gzip-compressed CSV; URLSession may auto-decompress
            if let csvString = String(data: data, encoding: .utf8) {
                let result: [String: Any] = [
                    "success": true,
                    "format": "csv",
                    "data": csvString
                ]
                return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
            } else {
                // If not decompressed, return base64 for manual processing
                let result: [String: Any] = [
                    "success": true,
                    "format": "gzip_base64",
                    "data": data.base64EncodedString(),
                    "note": "Data is gzip-compressed. Decode base64 then decompress gzip to get CSV."
                ]
                return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
            }
        } catch {
            return CallTool.Result(
                content: [.text("Failed to get sales report: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets a financial report from App Store Connect
    /// - Returns: CSV data with financial metrics or base64-encoded gzip data
    /// - Throws: Error if required parameters are missing or API call fails
    func getFinancialReport(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let vendorNumber = arguments["vendor_number"]?.stringValue,
              let regionCode = arguments["region_code"]?.stringValue,
              let reportDate = arguments["report_date"]?.stringValue,
              let reportType = arguments["report_type"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Missing required parameters: vendor_number, region_code, report_date, report_type")],
                isError: true
            )
        }

        do {
            let queryParams: [String: String] = [
                "filter[vendorNumber]": vendorNumber,
                "filter[regionCode]": regionCode,
                "filter[reportDate]": reportDate,
                "filter[reportType]": reportType
            ]

            let data = try await httpClient.getRaw("/v1/financeReports", parameters: queryParams, accept: "application/a-gzip")

            // Reports return gzip-compressed CSV; URLSession may auto-decompress
            if let csvString = String(data: data, encoding: .utf8) {
                let result: [String: Any] = [
                    "success": true,
                    "format": "csv",
                    "data": csvString
                ]
                return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
            } else {
                // If not decompressed, return base64 for manual processing
                let result: [String: Any] = [
                    "success": true,
                    "format": "gzip_base64",
                    "data": data.base64EncodedString(),
                    "note": "Data is gzip-compressed. Decode base64 then decompress gzip to get CSV."
                ]
                return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])
            }
        } catch {
            return CallTool.Result(
                content: [.text("Failed to get financial report: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists analytics report requests for an app
    /// - Returns: JSON array of report requests with attributes and pagination
    func listAnalyticsReportRequests(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'app_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAnalyticsReportRequestsResponse

            // Check for pagination URL
            if let nextUrlValue = arguments["next_url"],
               let nextUrl = nextUrlValue.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCAnalyticsReportRequestsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limitValue = arguments["limit"],
                   let limit = limitValue.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/apps/\(appId)/analyticsReportRequests",
                    parameters: queryParams,
                    as: ASCAnalyticsReportRequestsResponse.self
                )
            }

            let requests = response.data.map { formatReportRequest($0) }

            var result: [String: Any] = [
                "success": true,
                "report_requests": requests,
                "count": requests.count
            ]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list analytics report requests: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Creates an analytics report request for an app
    /// - Returns: JSON with created report request details
    func createAnalyticsReportRequest(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let appIdValue = arguments["app_id"],
              let appId = appIdValue.stringValue,
              let accessTypeValue = arguments["access_type"],
              let accessType = accessTypeValue.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameters 'app_id' and 'access_type' are missing")],
                isError: true
            )
        }

        do {
            let request = CreateAnalyticsReportRequestRequest(
                data: CreateAnalyticsReportRequestRequest.CreateAnalyticsReportRequestData(
                    attributes: CreateAnalyticsReportRequestRequest.CreateAnalyticsReportRequestAttributes(
                        accessType: accessType
                    ),
                    relationships: CreateAnalyticsReportRequestRequest.CreateAnalyticsReportRequestRelationships(
                        app: CreateAnalyticsReportRequestRequest.AppRelationship(
                            data: ASCResourceIdentifier(type: "apps", id: appId)
                        )
                    )
                )
            )

            let response: ASCAnalyticsReportRequestResponse = try await httpClient.post(
                "/v1/analyticsReportRequests",
                body: request,
                as: ASCAnalyticsReportRequestResponse.self
            )

            let reportRequest = formatReportRequest(response.data)

            let result: [String: Any] = [
                "success": true,
                "report_request": reportRequest
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to create analytics report request: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Analytics Reports

    /// Lists analytics reports for a report request
    /// - Returns: JSON array of reports with category and name
    /// - Throws: Error if required parameters are missing or API call fails
    func listAnalyticsReports(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let requestId = arguments["request_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'request_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAnalyticsReportsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCAnalyticsReportsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/analyticsReportRequests/\(requestId)/reports",
                    parameters: queryParams,
                    as: ASCAnalyticsReportsResponse.self
                )
            }

            let reports = response.data.map { formatReport($0) }

            var result: [String: Any] = [
                "success": true,
                "reports": reports,
                "count": reports.count
            ]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list analytics reports: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets details of a specific analytics report
    /// - Returns: JSON with report details including category and name
    /// - Throws: Error if required parameters are missing or API call fails
    func getAnalyticsReport(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let reportId = arguments["report_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'report_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAnalyticsReportResponse = try await httpClient.get(
                "/v1/analyticsReports/\(reportId)",
                parameters: [:],
                as: ASCAnalyticsReportResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "report": formatReport(response.data)
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to get analytics report: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists instances of an analytics report
    /// - Returns: JSON array of report instances with granularity and processing date
    /// - Throws: Error if required parameters are missing or API call fails
    func listAnalyticsReportInstances(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let reportId = arguments["report_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'report_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAnalyticsReportInstancesResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCAnalyticsReportInstancesResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/analyticsReports/\(reportId)/instances",
                    parameters: queryParams,
                    as: ASCAnalyticsReportInstancesResponse.self
                )
            }

            let instances = response.data.map { formatReportInstance($0) }

            var result: [String: Any] = [
                "success": true,
                "instances": instances,
                "count": instances.count
            ]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list analytics report instances: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Gets a specific analytics report instance
    /// - Returns: JSON with report instance details
    /// - Throws: Error if required parameters are missing or API call fails
    func getAnalyticsReportInstance(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let instanceId = arguments["instance_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'instance_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAnalyticsReportInstanceResponse = try await httpClient.get(
                "/v1/analyticsReportInstances/\(instanceId)",
                parameters: [:],
                as: ASCAnalyticsReportInstanceResponse.self
            )

            let result: [String: Any] = [
                "success": true,
                "instance": formatReportInstance(response.data)
            ]

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to get analytics report instance: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    /// Lists segments of an analytics report instance
    /// - Returns: JSON array of report segments with download URLs
    /// - Throws: Error if required parameters are missing or API call fails
    func listAnalyticsReportSegments(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        guard let arguments = params.arguments,
              let instanceId = arguments["instance_id"]?.stringValue else {
            return CallTool.Result(
                content: [.text("Required parameter 'instance_id' is missing")],
                isError: true
            )
        }

        do {
            let response: ASCAnalyticsReportSegmentsResponse

            if let nextUrl = arguments["next_url"]?.stringValue,
               let parsed = parsePaginationUrl(nextUrl) {
                response = try await httpClient.get(parsed.path, parameters: parsed.parameters, as: ASCAnalyticsReportSegmentsResponse.self)
            } else {
                var queryParams: [String: String] = [:]

                if let limit = arguments["limit"]?.intValue {
                    queryParams["limit"] = String(min(max(limit, 1), 200))
                } else {
                    queryParams["limit"] = "25"
                }

                response = try await httpClient.get(
                    "/v1/analyticsReportInstances/\(instanceId)/segments",
                    parameters: queryParams,
                    as: ASCAnalyticsReportSegmentsResponse.self
                )
            }

            let segments = response.data.map { formatReportSegment($0) }

            var result: [String: Any] = [
                "success": true,
                "segments": segments,
                "count": segments.count
            ]

            if let nextUrl = response.links?.next {
                result["next_url"] = nextUrl
            }

            return CallTool.Result(content: [.text(JSONFormatter.formatJSON(result))])

        } catch {
            return CallTool.Result(
                content: [.text("Failed to list analytics report segments: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Formatting

    /// Formats an analytics report request as a dictionary for JSON output
    private func formatReportRequest(_ request: ASCAnalyticsReportRequest) -> [String: Any] {
        var dict: [String: Any] = [
            "id": request.id,
            "type": request.type
        ]
        if let accessType = request.attributes?.accessType {
            dict["access_type"] = accessType
        }
        if let stoppedDueToInactivity = request.attributes?.stoppedDueToInactivity {
            dict["stopped_due_to_inactivity"] = stoppedDueToInactivity
        }
        return dict
    }

    /// Formats an analytics report as a dictionary for JSON output
    private func formatReport(_ report: ASCAnalyticsReport) -> [String: Any] {
        var dict: [String: Any] = [
            "id": report.id,
            "type": report.type
        ]
        dict["category"] = report.attributes?.category.jsonSafe ?? NSNull()
        dict["name"] = report.attributes?.name.jsonSafe ?? NSNull()
        return dict
    }

    /// Formats an analytics report instance as a dictionary for JSON output
    private func formatReportInstance(_ instance: ASCAnalyticsReportInstance) -> [String: Any] {
        var dict: [String: Any] = [
            "id": instance.id,
            "type": instance.type
        ]
        dict["granularity"] = instance.attributes?.granularity.jsonSafe ?? NSNull()
        dict["processing_date"] = instance.attributes?.processingDate.jsonSafe ?? NSNull()
        return dict
    }

    /// Formats an analytics report segment as a dictionary for JSON output
    private func formatReportSegment(_ segment: ASCAnalyticsReportSegment) -> [String: Any] {
        var dict: [String: Any] = [
            "id": segment.id,
            "type": segment.type
        ]
        dict["checksum"] = segment.attributes?.checksum.jsonSafe ?? NSNull()
        dict["size_in_bytes"] = segment.attributes?.sizeInBytes.jsonSafe ?? NSNull()
        dict["url"] = segment.attributes?.url.jsonSafe ?? NSNull()
        return dict
    }
}
