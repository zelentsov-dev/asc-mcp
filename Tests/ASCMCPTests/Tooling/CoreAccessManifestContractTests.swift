import Testing
@testable import asc_mcp

@Suite("Core Access Manifest Contract Tests")
struct CoreAccessManifestContractTests {
    @Test("optional relationship linkages declare every fixed resource type")
    func optionalRelationshipTypes() throws {
        let manifest = try ASCOperationManifestBundle.loadBundled()
        let invitation = try #require(manifest.mapping(for: "users_invite"))
        let profile = try #require(manifest.mapping(for: "provisioning_create_profile"))

        let invitationInputs = try #require(invitation.operations.first?.inputs)
        #expect(invitationInputs.contains {
            $0.jsonPointer == "/data/relationships/visibleApps/data/*/type" &&
                $0.fixedValue == .string("apps")
        })

        let profileInputs = try #require(profile.operations.first?.inputs)
        #expect(profileInputs.contains {
            $0.jsonPointer == "/data/relationships/bundleId/data/type" &&
                $0.fixedValue == .string("bundleIds")
        })
        #expect(profileInputs.contains {
            $0.jsonPointer == "/data/relationships/certificates/data/*/type" &&
                $0.fixedValue == .string("certificates")
        })
        #expect(profileInputs.contains {
            $0.jsonPointer == "/data/relationships/devices/data/*/type" &&
                $0.fixedValue == .string("devices")
        })
    }
}
