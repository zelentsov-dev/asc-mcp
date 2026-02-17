import Testing
import Foundation
@testable import asc_mcp

@Suite("Provisioning Model Tests")
struct ProvisioningModelTests {
    @Test func decodeBundleId() throws {
        let json = """
        {"type":"bundleIds","id":"bid-1","attributes":{"name":"Test App","identifier":"com.test","platform":"IOS","seedId":"ABC"}}
        """.data(using: .utf8)!
        let bid = try JSONDecoder().decode(ASCBundleId.self, from: json)
        #expect(bid.id == "bid-1")
        #expect(bid.attributes.identifier == "com.test")
    }

    @Test func decodeDevice() throws {
        let json = """
        {"type":"devices","id":"dev-1","attributes":{"name":"iPhone","platform":"IOS","udid":"AAAA","deviceClass":"IPHONE","status":"ENABLED"}}
        """.data(using: .utf8)!
        let device = try JSONDecoder().decode(ASCDevice.self, from: json)
        #expect(device.attributes.name == "iPhone")
        #expect(device.attributes.status == "ENABLED")
    }

    @Test func decodeCertificate() throws {
        let json = """
        {"type":"certificates","id":"cert-1","attributes":{"name":"iOS Dist","certificateType":"IOS_DISTRIBUTION","serialNumber":"ABC123"}}
        """.data(using: .utf8)!
        let cert = try JSONDecoder().decode(ASCCertificate.self, from: json)
        #expect(cert.attributes.certificateType == "IOS_DISTRIBUTION")
    }

    @Test func decodeProfile() throws {
        let json = """
        {"type":"profiles","id":"prof-1","attributes":{"name":"Test Profile","profileType":"IOS_APP_STORE","profileState":"ACTIVE","uuid":"1234-5678"}}
        """.data(using: .utf8)!
        let profile = try JSONDecoder().decode(ASCProfile.self, from: json)
        #expect(profile.attributes.profileState == "ACTIVE")
    }

    @Test func decodeCapability() throws {
        let json = """
        {"type":"bundleIdCapabilities","id":"cap-1","attributes":{"capabilityType":"PUSH_NOTIFICATIONS","settings":[{"key":"PUSH","name":"Push","options":[{"key":"ON","enabled":true}]}]}}
        """.data(using: .utf8)!
        let cap = try JSONDecoder().decode(ASCBundleIdCapability.self, from: json)
        #expect(cap.attributes.capabilityType == "PUSH_NOTIFICATIONS")
        #expect(cap.attributes.settings?.first?.key == "PUSH")
    }

    @Test func bundleIdResponse() throws {
        let json = """
        {"data":{"type":"bundleIds","id":"bid-1","attributes":{"name":"Test","identifier":"com.test","platform":"IOS"}}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCBundleIdResponse.self, from: json)
        #expect(response.data.id == "bid-1")
    }

    @Test func createBundleIdRequest() throws {
        let request = CreateBundleIdRequest(data: .init(attributes: .init(name: "New App", identifier: "com.new", platform: "IOS")))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CreateBundleIdRequest.self, from: data)
        #expect(decoded.data.attributes.identifier == "com.new")
    }

    @Test func registerDeviceRequest() throws {
        let request = RegisterDeviceRequest(data: .init(attributes: .init(name: "Test iPhone", udid: "AAAA-BBBB", platform: "IOS")))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(RegisterDeviceRequest.self, from: data)
        #expect(decoded.data.attributes.udid == "AAAA-BBBB")
    }
}
