import Foundation

/// Helper for formatting JSON responses
public enum JSONFormatter {
    /// Format an object as pretty-printed JSON string
    public static func formatJSON(_ object: Any) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{\"error\": \"Failed to format JSON: \(error.localizedDescription)\"}"
        }
    }
    
    /// Format an object as compact JSON string
    public static func formatCompactJSON(_ object: Any) -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{\"error\": \"Failed to format JSON: \(error.localizedDescription)\"}"
        }
    }
}