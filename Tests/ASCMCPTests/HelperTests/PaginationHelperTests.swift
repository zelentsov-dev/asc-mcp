import Foundation
import MCP
import Testing
@testable import asc_mcp

@Suite("Pagination Scope Tests")
struct PaginationHelperTests {
    private let baseURL = "https://api.appstoreconnect.apple.com"

    @Test func acceptsValidAppleNextLink() throws {
        let request = try validatedPaginationRequest(
            "https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=app-1&limit=25&cursor=abc",
            baseURL: baseURL,
            scope: PaginationScope(
                path: "/v1/builds",
                requiredParameters: ["filter[app]": "app-1"]
            )
        )

        #expect(request.path == "/v1/builds")
        #expect(request.parameters["filter[app]"] == "app-1")
        #expect(request.parameters["cursor"] == "abc")
    }

    @Test func acceptsEquivalentExplicitDefaultPort() throws {
        let request = try validatedPaginationRequest(
            "https://api.appstoreconnect.apple.com:443/v1/apps?cursor=abc",
            baseURL: baseURL,
            scope: PaginationScope(path: "/v1/apps")
        )

        #expect(request.parameters["cursor"] == "abc")
    }

    @Test func distinguishesMissingPaginationArgument() throws {
        #expect(try paginationURL(from: nil) == nil)
        #expect(try paginationURL(from: .string("https://api.example.test/v1/apps?cursor=abc")) != nil)
    }

    @Test(arguments: [
        Value.int(1),
        Value.bool(true),
        Value.null,
        Value.array([]),
        Value.string(""),
        Value.string("  \n")
    ])
    func rejectsPresentInvalidPaginationArgument(_ value: Value) {
        #expect(throws: ASCError.self) {
            try paginationURL(from: value)
        }
    }

    @Test(arguments: [
        "",
        "/v1/apps?cursor=abc",
        "not a URL"
    ])
    func rejectsMalformedOrRelativeLink(_ nextURL: String) {
        #expect(throws: ASCError.self) {
            try validatedPaginationRequest(
                nextURL,
                baseURL: baseURL,
                scope: PaginationScope(path: "/v1/apps")
            )
        }
    }

    @Test(arguments: [
        "https://evil.example.com/v1/apps?cursor=abc",
        "http://api.appstoreconnect.apple.com/v1/apps?cursor=abc",
        "https://api.appstoreconnect.apple.com:444/v1/apps?cursor=abc",
        "https://user@api.appstoreconnect.apple.com/v1/apps?cursor=abc",
        "https://api.appstoreconnect.apple.com/v1/apps?cursor=abc#fragment"
    ])
    func rejectsDifferentOriginOrURLAuthority(_ nextURL: String) {
        #expect(throws: ASCError.self) {
            try validatedPaginationRequest(
                nextURL,
                baseURL: baseURL,
                scope: PaginationScope(path: "/v1/apps")
            )
        }
    }

    @Test func rejectsSameOriginCrossRoute() {
        #expect(throws: ASCError.self) {
            try validatedPaginationRequest(
                "https://api.appstoreconnect.apple.com/v1/users?cursor=abc",
                baseURL: baseURL,
                scope: PaginationScope(path: "/v1/apps/app-1/appStoreVersions")
            )
        }
    }

    @Test func rejectsWrongParentIdentifier() {
        #expect(throws: ASCError.self) {
            try validatedPaginationRequest(
                "https://api.appstoreconnect.apple.com/v1/inAppPurchases/wrong/images?cursor=abc",
                baseURL: baseURL,
                scope: PaginationScope(path: "/v1/inAppPurchases/iap-1/images")
            )
        }
    }

    @Test(arguments: [
        "https://api.appstoreconnect.apple.com/v1/apps/../users?cursor=abc",
        "https://api.appstoreconnect.apple.com/v1/apps%2Fapp-1%2FappStoreVersions?cursor=abc",
        "https://api.appstoreconnect.apple.com/v1/apps%5Capp-1%5CappStoreVersions?cursor=abc"
    ])
    func rejectsNonCanonicalPathForms(_ nextURL: String) {
        #expect(throws: ASCError.self) {
            try validatedPaginationRequest(
                nextURL,
                baseURL: baseURL,
                scope: PaginationScope(path: "/v1/apps/app-1/appStoreVersions")
            )
        }
    }

    @Test func rejectsChangedRequiredFilter() {
        #expect(throws: ASCError.self) {
            try validatedPaginationRequest(
                "https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=app-2&cursor=abc",
                baseURL: baseURL,
                scope: PaginationScope(
                    path: "/v1/builds",
                    requiredParameters: ["filter[app]": "app-1"]
                )
            )
        }
    }

    @Test func rejectsMissingRequiredFilter() {
        #expect(throws: ASCError.self) {
            try validatedPaginationRequest(
                "https://api.appstoreconnect.apple.com/v1/builds?cursor=abc",
                baseURL: baseURL,
                scope: PaginationScope(
                    path: "/v1/builds",
                    requiredParameters: ["filter[app]": "app-1"]
                )
            )
        }
    }

    @Test func rejectsDuplicateQueryNames() {
        #expect(throws: ASCError.self) {
            try validatedPaginationRequest(
                "https://api.appstoreconnect.apple.com/v1/apps?cursor=one&cursor=two",
                baseURL: baseURL,
                scope: PaginationScope(path: "/v1/apps")
            )
        }
    }

    @Test func rejectsQueryParameterWithoutValue() {
        #expect(throws: ASCError.self) {
            try validatedPaginationRequest(
                "https://api.appstoreconnect.apple.com/v1/apps?cursor",
                baseURL: baseURL,
                scope: PaginationScope(path: "/v1/apps")
            )
        }
    }

    @Test func acceptsForwardCompatibleQueryNamesByDefault() throws {
        let request = try validatedPaginationRequest(
            "https://api.appstoreconnect.apple.com/v1/apps?cursor=abc&futureAppleField=value",
            baseURL: baseURL,
            scope: PaginationScope(path: "/v1/apps")
        )

        #expect(request.parameters["futureAppleField"] == "value")
    }

    @Test func optionalAllowlistRejectsUnknownQueryNames() {
        #expect(throws: ASCError.self) {
            try validatedPaginationRequest(
                "https://api.appstoreconnect.apple.com/v1/apps?cursor=abc&unexpected=value",
                baseURL: baseURL,
                scope: PaginationScope(
                    path: "/v1/apps",
                    allowedParameters: ["cursor"]
                )
            )
        }
    }

    @Test(arguments: [
        "https://api.appstoreconnect.apple.com/v1/apps?limit=25",
        "https://api.appstoreconnect.apple.com/v1/apps?limit=25&cursor=",
        "https://api.appstoreconnect.apple.com/v1/apps?limit=25&cursor=%20"
    ])
    func rejectsMissingOrEmptyRequiredQueryValue(_ nextURL: String) {
        #expect(throws: ASCError.self) {
            try validatedPaginationRequest(
                nextURL,
                baseURL: baseURL,
                scope: PaginationScope(
                    path: "/v1/apps",
                    requiredParameters: ["limit": "25"],
                    allowedParameters: ["limit", "cursor"],
                    requiredNonEmptyParameters: ["cursor"]
                )
            )
        }
    }

    @Test func acceptsConfiguredOrigin() throws {
        let request = try validatedPaginationRequest(
            "https://proxy.example.test/v1/apps?cursor=abc",
            baseURL: "https://proxy.example.test",
            scope: PaginationScope(path: "/v1/apps")
        )

        #expect(request.parameters["cursor"] == "abc")
    }
}

@Suite("Pagination Architecture Tests")
struct PaginationArchitectureTests {
    @Test func workersCannotParsePaginationURLsDirectly() throws {
        let workersURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/asc-mcp/Workers", isDirectory: true)
        let enumerator = FileManager.default.enumerator(
            at: workersURL,
            includingPropertiesForKeys: nil
        )
        var violations: [String] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            if source.contains("parsePaginationUrl") || source.contains("validatedPaginationRequest") {
                violations.append(fileURL.path.replacingOccurrences(
                    of: FileManager.default.currentDirectoryPath + "/",
                    with: ""
                ))
            }
        }

        #expect(violations.isEmpty, "Workers must use HTTPClient.getPage with an explicit PaginationScope: \(violations)")
    }

    @Test func workersCannotTreatPresentInvalidPaginationAsAbsent() throws {
        let workersURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/asc-mcp/Workers", isDirectory: true)
        let enumerator = FileManager.default.enumerator(
            at: workersURL,
            includingPropertiesForKeys: nil
        )
        let patterns = [
            #"\["next_url"\]\?\.stringValue"#,
            #"next(?:URL|Url)Value\.stringValue"#
        ].map { try! NSRegularExpression(pattern: $0) }
        var violations: [String] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.lastPathComponent.hasSuffix("Handlers.swift") else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            if patterns.contains(where: { $0.firstMatch(in: source, range: range) != nil }) {
                violations.append(fileURL.path.replacingOccurrences(
                    of: FileManager.default.currentDirectoryPath + "/",
                    with: ""
                ))
            }
        }

        #expect(violations.isEmpty, "Workers must extract next_url with paginationURL(from:): \(violations)")
    }
}
