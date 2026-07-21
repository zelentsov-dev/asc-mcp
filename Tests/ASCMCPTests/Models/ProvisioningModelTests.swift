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
        #expect(bid.attributes?.identifier == "com.test")
    }

    @Test func decodeDevice() throws {
        let json = """
        {"type":"devices","id":"dev-1","attributes":{"name":"iPhone","platform":"IOS","udid":"AAAA","deviceClass":"IPHONE","status":"ENABLED"}}
        """.data(using: .utf8)!
        let device = try JSONDecoder().decode(ASCDevice.self, from: json)
        #expect(device.attributes?.name == "iPhone")
        #expect(device.attributes?.status == "ENABLED")
    }

    @Test func decodeCertificate() throws {
        let json = """
        {"type":"certificates","id":"cert-1","attributes":{"name":"iOS Dist","certificateType":"IOS_DISTRIBUTION","serialNumber":"ABC123"}}
        """.data(using: .utf8)!
        let cert = try JSONDecoder().decode(ASCCertificate.self, from: json)
        #expect(cert.attributes?.certificateType == "IOS_DISTRIBUTION")
    }

    @Test func decodeProfile() throws {
        let json = """
        {"type":"profiles","id":"prof-1","attributes":{"name":"Test Profile","profileType":"IOS_APP_STORE","profileState":"ACTIVE","uuid":"1234-5678"}}
        """.data(using: .utf8)!
        let profile = try JSONDecoder().decode(ASCProfile.self, from: json)
        #expect(profile.attributes?.profileState == "ACTIVE")
    }

    @Test func decodeCapability() throws {
        let json = """
        {"type":"bundleIdCapabilities","id":"cap-1","attributes":{"capabilityType":"PUSH_NOTIFICATIONS","settings":[{"key":"PUSH","name":"Push","options":[{"key":"ON","enabled":true}]}]}}
        """.data(using: .utf8)!
        let cap = try JSONDecoder().decode(ASCBundleIdCapability.self, from: json)
        #expect(cap.attributes?.capabilityType == "PUSH_NOTIFICATIONS")
        #expect(cap.attributes?.settings?.first?.key == "PUSH")
    }

    @Test func bundleIdResponse() throws {
        let json = """
        {"data":{"type":"bundleIds","id":"bid-1","attributes":{"name":"Test","identifier":"com.test","platform":"IOS"}}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(ASCBundleIdResponse.self, from: json)
        #expect(response.data.id == "bid-1")
    }

    @Test func createBundleIdRequest() throws {
        let request = CreateBundleIdRequest(data: .init(attributes: .init(name: "New App", identifier: "com.new", platform: "IOS", seedId: "SEED123")))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CreateBundleIdRequest.self, from: data)
        #expect(decoded.data.attributes.identifier == "com.new")
        #expect(decoded.data.attributes.seedId == .value("SEED123"))
    }

    @Test func registerDeviceRequest() throws {
        let request = RegisterDeviceRequest(data: .init(attributes: .init(name: "Test iPhone", udid: "AAAA-BBBB", platform: "IOS")))
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(RegisterDeviceRequest.self, from: data)
        #expect(decoded.data.attributes.udid == "AAAA-BBBB")
    }

    @Test("provisioning resources accept Apple responses without attributes")
    func sparseResources() throws {
        let bundleId = try JSONDecoder().decode(
            ASCBundleId.self,
            from: Data(#"{"type":"bundleIds","id":"bundle-1"}"#.utf8)
        )
        let device = try JSONDecoder().decode(
            ASCDevice.self,
            from: Data(#"{"type":"devices","id":"device-1"}"#.utf8)
        )
        let certificate = try JSONDecoder().decode(
            ASCCertificate.self,
            from: Data(#"{"type":"certificates","id":"certificate-1"}"#.utf8)
        )
        let profile = try JSONDecoder().decode(
            ASCProfile.self,
            from: Data(#"{"type":"profiles","id":"profile-1"}"#.utf8)
        )
        let capability = try JSONDecoder().decode(
            ASCBundleIdCapability.self,
            from: Data(#"{"type":"bundleIdCapabilities","id":"capability-1"}"#.utf8)
        )

        #expect(bundleId.attributes == nil)
        #expect(device.attributes == nil)
        #expect(certificate.attributes == nil)
        #expect(profile.attributes == nil)
        #expect(capability.attributes == nil)
    }

    @Test("provisioning requests preserve explicit null attributes")
    func nullableRequestAttributes() throws {
        let bundleRequest = CreateBundleIdRequest(
            data: .init(
                attributes: .init(
                    name: "App",
                    identifier: "com.example.app",
                    platform: "IOS",
                    nullableSeedId: .null
                )
            )
        )
        let deviceRequest = UpdateDeviceRequest(
            data: .init(
                id: "device-1",
                attributes: .init(nullableName: .null, nullableStatus: .null)
            )
        )

        let bundleObject = try provisioningModelObject(JSONEncoder().encode(bundleRequest))
        let bundleData = try provisioningModelObject(bundleObject["data"])
        let bundleAttributes = try provisioningModelObject(bundleData["attributes"])
        #expect(bundleAttributes["seedId"] is NSNull)

        let deviceObject = try provisioningModelObject(JSONEncoder().encode(deviceRequest))
        let deviceData = try provisioningModelObject(deviceObject["data"])
        let deviceAttributes = try provisioningModelObject(deviceData["attributes"])
        #expect(deviceAttributes["name"] is NSNull)
        #expect(deviceAttributes["status"] is NSNull)
    }
}

private func provisioningModelObject(_ data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw ProvisioningModelTestFailure.expectedObject
    }
    return object
}

private func provisioningModelObject(_ value: Any?) throws -> [String: Any] {
    guard let object = value as? [String: Any] else {
        throw ProvisioningModelTestFailure.expectedObject
    }
    return object
}

private enum ProvisioningModelTestFailure: Error {
    case expectedObject
}
