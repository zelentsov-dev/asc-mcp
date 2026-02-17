import Testing
import Foundation
@testable import asc_mcp

@Suite("BuildProcessing Model Tests")
struct BuildProcessingModelTests {
    @Test func decodeEncryptionDeclaration() throws {
        let json = """
        {"type":"appEncryptionDeclarations","id":"enc-1","attributes":{"platform":"IOS","appEncryptionDeclarationState":"APPROVED","usesEncryption":false,"exempt":true}}
        """.data(using: .utf8)!
        let decl = try JSONDecoder().decode(ASCAppEncryptionDeclaration.self, from: json)
        #expect(decl.id == "enc-1")
        #expect(decl.type == "appEncryptionDeclarations")
        #expect(decl.attributes?.platform == "IOS")
        #expect(decl.attributes?.appEncryptionDeclarationState == "APPROVED")
        #expect(decl.attributes?.usesEncryption == false)
        #expect(decl.attributes?.exempt == true)
    }

    @Test func decodeEncryptionDeclarationFullAttributes() throws {
        let json = """
        {"type":"appEncryptionDeclarations","id":"enc-2","attributes":{"platform":"MAC_OS","availableOnFrenchStore":true,"containsProprietaryCryptography":false,"containsThirdPartyCryptography":true,"isExportCompliant":true,"complianceCode":"CODE123"}}
        """.data(using: .utf8)!
        let decl = try JSONDecoder().decode(ASCAppEncryptionDeclaration.self, from: json)
        #expect(decl.attributes?.availableOnFrenchStore == true)
        #expect(decl.attributes?.containsProprietaryCryptography == false)
        #expect(decl.attributes?.containsThirdPartyCryptography == true)
        #expect(decl.attributes?.isExportCompliant == true)
        #expect(decl.attributes?.complianceCode == "CODE123")
    }

    @Test func encryptionDeclarationResponse() throws {
        let json = """
        {"data":{"type":"appEncryptionDeclarations","id":"enc-1","attributes":{"platform":"IOS"}}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCAppEncryptionDeclarationResponse.self, from: json)
        #expect(response.data.id == "enc-1")
        #expect(response.data.attributes?.platform == "IOS")
    }

    @Test func encryptionDeclarationsResponse() throws {
        let json = """
        {"data":[{"type":"appEncryptionDeclarations","id":"e1","attributes":{"platform":"IOS"}},{"type":"appEncryptionDeclarations","id":"e2","attributes":{"platform":"MAC_OS"}}]}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCAppEncryptionDeclarationsResponse.self, from: json)
        #expect(response.data.count == 2)
        #expect(response.data[0].id == "e1")
        #expect(response.data[1].id == "e2")
        #expect(response.data[0].attributes?.platform == "IOS")
        #expect(response.data[1].attributes?.platform == "MAC_OS")
    }

    @Test func updateBuildProcessingRequest() throws {
        let request = UpdateBuildProcessingRequest(
            data: .init(id: "b1", attributes: .init(expired: nil, usesNonExemptEncryption: false))
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(UpdateBuildProcessingRequest.self, from: data)
        #expect(decoded.data.id == "b1")
        #expect(decoded.data.type == "builds")
        #expect(decoded.data.attributes.usesNonExemptEncryption == false)
        #expect(decoded.data.attributes.expired == nil)
    }

    @Test func updateBuildProcessingRequestWithExpired() throws {
        let request = UpdateBuildProcessingRequest(
            data: .init(id: "b2", attributes: .init(expired: true, usesNonExemptEncryption: nil))
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(UpdateBuildProcessingRequest.self, from: data)
        #expect(decoded.data.id == "b2")
        #expect(decoded.data.attributes.expired == true)
        #expect(decoded.data.attributes.usesNonExemptEncryption == nil)
    }

    @Test func updateEncryptionDeclarationRequest() throws {
        let request = UpdateAppEncryptionDeclarationRequest(
            data: .init(id: "enc-1", attributes: .init(usesNonExemptEncryption: true))
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(UpdateAppEncryptionDeclarationRequest.self, from: data)
        #expect(decoded.data.id == "enc-1")
        #expect(decoded.data.type == "appEncryptionDeclarations")
        #expect(decoded.data.attributes.usesNonExemptEncryption == true)
    }

    @Test func updateEncryptionDeclarationRequestNilValue() throws {
        let request = UpdateAppEncryptionDeclarationRequest(
            data: .init(id: "enc-2", attributes: .init(usesNonExemptEncryption: nil))
        )
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(UpdateAppEncryptionDeclarationRequest.self, from: data)
        #expect(decoded.data.id == "enc-2")
        #expect(decoded.data.attributes.usesNonExemptEncryption == nil)
    }

    @Test func encryptionDeclarationWithRelationships() throws {
        let json = """
        {"type":"appEncryptionDeclarations","id":"enc-1","attributes":{"platform":"IOS"},"relationships":{"app":{"data":{"type":"apps","id":"app-1"}}}}
        """.data(using: .utf8)!
        let decl = try JSONDecoder().decode(ASCAppEncryptionDeclaration.self, from: json)
        #expect(decl.relationships?.app?.data?.id == "app-1")
    }

    @Test func encryptionDeclarationsResponseWithLinks() throws {
        let json = """
        {"data":[{"type":"appEncryptionDeclarations","id":"e1","attributes":{"platform":"IOS"}}],"links":{"self":"https://api.example.com/enc","next":"https://api.example.com/enc?page=2"}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCAppEncryptionDeclarationsResponse.self, from: json)
        #expect(response.data.count == 1)
        #expect(response.links?.next != nil)
    }
}
