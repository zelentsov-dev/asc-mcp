//
//  ReviewsWorker+Parsers.swift
//  asc-mcp
//
//  Parsing and formatting utilities for customer reviews
//

import Foundation

extension ReviewsWorker {
    /// Parse reviews response from API
    func parseReviewsResponse(data: Data) throws -> ReviewsResponse {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(ReviewsResponse.self, from: data)
        } catch {
            // Try to parse error response
            if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                let errorMessage = errorResponse.errors.first?.detail ?? "Unknown error"
                throw NSError(domain: "ReviewsWorker", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            }
            throw NSError(domain: "ReviewsWorker", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse reviews response: \(error)"])
        }
    }
    
    /// Format reviews for display
    func formatReviews(_ reviews: [CustomerReview]) -> String {
        if reviews.isEmpty {
            return "No reviews found"
        }
        
        return reviews.enumerated().map { index, review in
            """
            \(index + 1). Rating: \(String(repeating: "⭐", count: review.attributes.rating))
               Title: \(review.attributes.title ?? "No title")
               Review: \(review.attributes.body ?? "No content")
               By: \(review.attributes.reviewerNickname)
               Date: \(formatDate(review.attributes.createdDate))
               Territory: \(review.attributes.territory ?? "Unknown")
               ID: \(review.id)
            """
        }.joined(separator: "\n\n")
    }
    
    /// Format date for display
    func formatDate(_ dateString: String) -> String {
        // Parse ISO8601 date
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }
        
        // Format for display
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        displayFormatter.locale = Locale(identifier: "en_US")
        
        return displayFormatter.string(from: date)
    }
    
    func normalizeReviewPeriod(_ period: String) -> String? {
        switch period {
        case "last_week", "last_month", "last_3_months", "all_time":
            return period
        case "last_quarter":
            return "last_3_months"
        default:
            return nil
        }
    }

    func reviewPeriodStart(for period: String, now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(secondsFromGMT: 0) {
            calendar.timeZone = utc
        }

        switch period {
        case "last_week":
            return calendar.date(byAdding: .day, value: -7, to: now)
        case "last_month":
            return calendar.date(byAdding: .month, value: -1, to: now)
        case "last_3_months":
            return calendar.date(byAdding: .month, value: -3, to: now)
        default:
            return nil
        }
    }

    func parseReviewDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }

    /// Calculate statistics from reviews, filtering by period
    func calculateStats(from reviews: [CustomerReview], period: String, now: Date = Date()) -> ReviewStats {
        let startDate = reviewPeriodStart(for: period, now: now)

        let filteredReviews: [CustomerReview]
        if let startDate {
            filteredReviews = reviews.filter { review in
                guard let reviewDate = parseReviewDate(review.attributes.createdDate) else { return false }
                return reviewDate >= startDate && reviewDate <= now
            }
        } else {
            filteredReviews = reviews
        }

        let totalCount = filteredReviews.count

        // Calculate average rating
        let totalRating = filteredReviews.reduce(0) { $0 + $1.attributes.rating }
        let averageRating = totalCount > 0 ? Double(totalRating) / Double(totalCount) : 0.0

        // Calculate rating distribution
        var ratingDistribution: [Int: Int] = [:]
        for rating in 1...5 {
            ratingDistribution[rating] = filteredReviews.filter { $0.attributes.rating == rating }.count
        }

        // Calculate territory statistics
        var territoryMap: [String: [CustomerReview]] = [:]
        for review in filteredReviews {
            let territory = review.attributes.territory ?? "Unknown"
            territoryMap[territory, default: []].append(review)
        }

        let topTerritories = territoryMap
            .map { territory, reviews in
                let avgRating = Double(reviews.reduce(0) { $0 + $1.attributes.rating }) / Double(reviews.count)
                return TerritoryStats(
                    territory: territory,
                    count: reviews.count,
                    averageRating: avgRating
                )
            }
            .sorted { $0.count > $1.count }
            .prefix(5)
            .map { $0 }

        return ReviewStats(
            totalCount: totalCount,
            averageRating: averageRating,
            ratingDistribution: ratingDistribution,
            periodStart: startDate.map { ISO8601DateFormatter().string(from: $0) },
            periodEnd: ISO8601DateFormatter().string(from: now),
            topTerritories: topTerritories.isEmpty ? nil : topTerritories
        )
    }
    
    /// Format rating distribution for display
    func formatRatingDistribution(_ distribution: [Int: Int]) -> String {
        return (1...5).reversed().map { rating in
            let count = distribution[rating] ?? 0
            let stars = String(repeating: "⭐", count: rating)
            let bar = String(repeating: "█", count: min(count / 2, 20))
            return "\(stars): \(bar) (\(count))"
        }.joined(separator: "\n")
    }
    
    /// Error response structure
    struct ErrorResponse: Codable {
        let errors: [APIError]
    }
    
    struct APIError: Codable {
        let status: String
        let code: String
        let title: String
        let detail: String
    }
}
