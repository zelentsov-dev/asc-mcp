import Foundation
import Testing
@testable import asc_mcp

@Suite("Xcode Cloud Response Contract Tests")
struct XcodeCloudResponseContractTests {
    @Test("document links are required for single and collection responses")
    func documentLinksAreRequired() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ASCCIProductResponse.self,
                from: Data(#"{"data":{"type":"ciProducts","id":"product-1"}}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ASCCIProductsResponse.self,
                from: Data(#"{"data":[]}"#.utf8)
            )
        }
    }

    @Test("wrong resource types and noncanonical IDs are rejected")
    func resourceIdentityIsStrict() {
        #expect(throws: ASCError.self) {
            try JSONDecoder().decode(
                ASCCIProductResponse.self,
                from: Data(#"{"data":{"type":"ciWorkflows","id":"product-1"},"links":{"self":"/v1/ciProducts/product-1"}}"#.utf8)
            )
        }
        #expect(throws: ASCError.self) {
            try JSONDecoder().decode(
                ASCCIProductResponse.self,
                from: Data(#"{"data":{"type":"ciProducts","id":"bad/id"},"links":{"self":"/v1/ciProducts/bad%2Fid"}}"#.utf8)
            )
        }
    }

    @Test("relationship lineage is validated")
    func relationshipTypesAreStrict() {
        #expect(throws: ASCError.self) {
            try JSONDecoder().decode(
                ASCCIWorkflowResponse.self,
                from: Data(
                    #"{"data":{"type":"ciWorkflows","id":"workflow-1","relationships":{"repository":{"data":{"type":"apps","id":"repository-1"}}}},"links":{"self":"/v1/ciWorkflows/workflow-1"}}"#.utf8
                )
            )
        }
    }

    @Test("links-only relationships reject fabricated linkage and metadata")
    func linksOnlyRelationshipsAreExact() throws {
        let relationship = try JSONDecoder().decode(
            ASCXcodeCloudRelationshipLinksOnly.self,
            from: Data(
                #"{"links":{"self":"/v1/ciBuildRuns/run-1/relationships/actions","related":"/v1/ciBuildRuns/run-1/actions"}}"#.utf8
            )
        )
        #expect(relationship.links?.related == "/v1/ciBuildRuns/run-1/actions")

        for body in [
            #"{"links":{},"data":[]}"#,
            #"{"links":{},"meta":{"paging":{"limit":1}}}"#
        ] {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(
                    ASCXcodeCloudRelationshipLinksOnly.self,
                    from: Data(body.utf8)
                )
            }
        }

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ASCCIBuildRunResponse.self,
                from: Data(
                    #"{"data":{"type":"ciBuildRuns","id":"run-1","relationships":{"actions":{"data":[{"type":"ciBuildActions","id":"action-1"}]}}},"links":{"self":"/v1/ciBuildRuns/run-1"}}"#.utf8
                )
            )
        }
    }

    @Test("unsupported included members are rejected")
    func unsupportedIncludedMembersAreRejected() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ASCCIArtifactResponse.self,
                from: Data(
                    #"{"data":{"type":"ciArtifacts","id":"artifact-1"},"included":[],"links":{"self":"/v1/ciArtifacts/artifact-1"}}"#.utf8
                )
            )
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                ASCScmProvidersResponse.self,
                from: Data(
                    #"{"data":[],"included":[],"links":{"self":"/v1/scmProviders?limit=25"}}"#.utf8
                )
            )
        }
    }

    @Test("paging and relationship paging metadata stay contract strict")
    func pagingMetadataIsValidatedAndPreserved() throws {
        #expect(throws: ASCError.self) {
            try JSONDecoder().decode(
                ASCCIProductsResponse.self,
                from: Data(
                    #"{"data":[],"links":{"self":"/v1/ciProducts?limit=25"},"meta":{"paging":{"total":0}}}"#.utf8
                )
            )
        }

        let response = try JSONDecoder().decode(
            ASCCIProductsResponse.self,
            from: Data(
                #"{"data":[{"type":"ciProducts","id":"product-1","relationships":{"primaryRepositories":{"data":[{"type":"scmRepositories","id":"repository-1"}],"meta":{"paging":{"total":3,"limit":1,"nextCursor":"next"}}}}}],"links":{"self":"/v1/ciProducts?limit=1"},"meta":{"paging":{"total":1,"limit":1}}}"#.utf8
            )
        )
        #expect(response.data.first?.relationships?.primaryRepositories?.meta?.paging?.total == 3)
        #expect(response.data.first?.relationships?.primaryRepositories?.meta?.paging?.nextCursor == "next")
    }

    @Test("typed relationship paging rejects duplicate linkage over-limit pages and blank cursors")
    func typedRelationshipPagingRejectsInvalidPages() throws {
        let invalidResponses = [
            #"{"data":[{"type":"ciProducts","id":"product-1","relationships":{"primaryRepositories":{"data":[{"type":"scmRepositories","id":"repository-1"},{"type":"scmRepositories","id":"repository-1"}]}}}],"links":{"self":"/v1/ciProducts?limit=1"}}"#,
            #"{"data":[{"type":"ciProducts","id":"product-1","relationships":{"primaryRepositories":{"data":[{"type":"scmRepositories","id":"repository-1"},{"type":"scmRepositories","id":"repository-2"}],"meta":{"paging":{"total":2,"limit":1}}}}}],"links":{"self":"/v1/ciProducts?limit=1"}}"#,
            #"{"data":[{"type":"ciProducts","id":"product-1","relationships":{"primaryRepositories":{"data":[],"meta":{"paging":{"total":1,"limit":1,"nextCursor":""}}}}}],"links":{"self":"/v1/ciProducts?limit=1"}}"#,
            #"{"data":[{"type":"ciProducts","id":"product-1","relationships":{"primaryRepositories":{"data":[],"meta":{"paging":{"total":1,"limit":1,"nextCursor":"   "}}}}}],"links":{"self":"/v1/ciProducts?limit=1"}}"#
        ]

        for response in invalidResponses {
            #expect(throws: ASCError.self) {
                try JSONDecoder().decode(
                    ASCCIProductsResponse.self,
                    from: Data(response.utf8)
                )
            }
        }
    }
}
