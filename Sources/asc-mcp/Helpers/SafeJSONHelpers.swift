import Foundation

/// Helper for safe JSON conversion of optional values
public enum SafeJSONHelpers {
    
    /// Safely converts optional to JSON-safe value
    /// - Parameter optional: Optional value to convert
    /// - Returns: Value or NSNull for nil
    public static func safeValue<T>(_ optional: T?) -> Any {
        return optional ?? NSNull()
    }
    
    /// Safely converts optional string to JSON-safe value
    /// - Parameter optional: Optional string to convert  
    /// - Returns: String or NSNull for nil
    public static func safeString(_ optional: String?) -> Any {
        return optional ?? NSNull()
    }
    
    /// Safely converts optional bool to JSON-safe value
    /// - Parameter optional: Optional bool to convert
    /// - Returns: Bool or NSNull for nil
    public static func safeBool(_ optional: Bool?) -> Any {
        return optional ?? NSNull()
    }
    
    /// Safely converts optional int to JSON-safe value
    /// - Parameter optional: Optional int to convert
    /// - Returns: Int or NSNull for nil
    public static func safeInt(_ optional: Int?) -> Any {
        return optional ?? NSNull()
    }
    
    /// Creates a safe JSON dictionary with proper null handling
    /// - Parameter builder: Dictionary builder closure
    /// - Returns: JSON-safe dictionary
    public static func safeDictionary(_ builder: () -> [String: Any]) -> [String: Any] {
        return builder()
    }
}

/// Extension for more convenient usage
extension Optional {
    /// Convert optional to JSON-safe value
    var jsonSafe: Any {
        return SafeJSONHelpers.safeValue(self)
    }
}