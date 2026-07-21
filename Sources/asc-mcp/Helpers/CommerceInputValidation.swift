import MCP

func validatedCommerceLimit(_ value: Value?, defaultValue: Int, maximum: Int) throws -> Int {
    guard let value else {
        return defaultValue
    }
    guard let limit = value.intValue, (1...maximum).contains(limit) else {
        throw ASCError.parsing("'limit' must be an integer from 1 through \(maximum)")
    }
    return limit
}
