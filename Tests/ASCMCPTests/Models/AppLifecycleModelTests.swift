import Testing
import Foundation
@testable import asc_mcp

@Suite("AppLifecycle Model Tests")
struct AppLifecycleModelTests {
    @Test func createVersionRequest() throws {
        let request = CreateAppStoreVersionRequest(platform: "IOS", versionString: "2.0", releaseType: "MANUAL", earliestReleaseDate: nil, appId: "app-1")
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CreateAppStoreVersionRequest.self, from: data)
        #expect(decoded.data.attributes.versionString == "2.0")
        #expect(decoded.data.attributes.platform == "IOS")
    }

    @Test func updateVersionRequest() throws {
        let request = UpdateAppStoreVersionRequest(id: "ver-1", releaseType: "AFTER_APPROVAL", copyright: "2025 Corp")
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(UpdateAppStoreVersionRequest.self, from: data)
        #expect(decoded.data.id == "ver-1")
        #expect(decoded.data.attributes.copyright == "2025 Corp")
    }

    @Test func attachBuildRequest() throws {
        let request = AttachBuildRequest(buildId: "b-123")
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(AttachBuildRequest.self, from: data)
        #expect(decoded.data.id == "b-123")
        #expect(decoded.data.type == "builds")
    }

    @Test func createReviewSubmissionRequest() throws {
        let request = CreateReviewSubmissionRequest(platform: "IOS", appId: "app-1")
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CreateReviewSubmissionRequest.self, from: data)
        #expect(decoded.data.attributes.platform == "IOS")
    }

    @Test func confirmReviewSubmission() throws {
        let request = ConfirmReviewSubmissionRequest(submissionId: "sub-1")
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ConfirmReviewSubmissionRequest.self, from: data)
        #expect(decoded.data.id == "sub-1")
        #expect(decoded.data.attributes.submitted == true)
    }

    @Test func createPhasedRelease() throws {
        let request = CreatePhasedReleaseRequest(versionId: "ver-1", state: "ACTIVE")
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CreatePhasedReleaseRequest.self, from: data)
        #expect(decoded.data.attributes.phasedReleaseState == "ACTIVE")
    }

    @Test func updatePhasedRelease() throws {
        let request = UpdatePhasedReleaseRequest(phasedReleaseId: "pr-1", state: "COMPLETE")
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(UpdatePhasedReleaseRequest.self, from: data)
        #expect(decoded.data.id == "pr-1")
    }

    @Test func createReleaseRequest() throws {
        let request = CreateReleaseRequest(versionId: "ver-1")
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(CreateReleaseRequest.self, from: data)
        #expect(decoded.data.type == "appStoreVersionReleaseRequests")
    }
}
