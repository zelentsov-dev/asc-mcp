import Foundation

/// ASC Error types
public enum ASCError: LocalizedError, Sendable {
    case configuration(String)
    case api(String, Int)
    case network(String)
    case authentication(String)
    case parsing(String)
    
    public var errorDescription: String? {
        switch self {
        case .configuration(let message):
            return "Configuration error: \(message)"
        case .api(let message, let code):
            return "API error (\(code)): \(message)"
        case .network(let message):
            return "Network error: \(message)"
        case .authentication(let message):
            return "Authentication error: \(message)"
        case .parsing(let message):
            return "Parsing error: \(message)"
        }
    }
}