import Testing
@testable import asc_mcp

@Suite("CompaniesManager Environment Loading Tests")
struct CompaniesManagerEnvTests {
    @Test("Single team key loads with issuer ID")
    func loadFromEnvironment_singleTeamKey() {
        let env = [
            "ASC_KEY_ID": "TESTKEY",
            "ASC_ISSUER_ID": "TESTISSUER",
            "ASC_PRIVATE_KEY_PATH": "/tmp/key.p8"
        ]

        let config = CompaniesManager.loadFromEnvironment(env: env)

        #expect(config?.companies.count == 1)
        #expect(config?.companies.first?.issuerID != nil)
        #expect(config?.companies.first?.isIndividualKey == false)
    }

    @Test("Single individual key loads without issuer ID")
    func loadFromEnvironment_singleIndividualKey() {
        let env = [
            "ASC_KEY_ID": "TESTKEY",
            "ASC_PRIVATE_KEY_PATH": "/tmp/key.p8"
        ]

        let config = CompaniesManager.loadFromEnvironment(env: env)

        #expect(config?.companies.count == 1)
        #expect(config?.companies.first?.issuerID == nil)
        #expect(config?.companies.first?.isIndividualKey == true)
    }

    @Test("Multi-company env loads team and individual keys")
    func loadFromEnvironment_multiCompanyMixed() {
        let env = [
            "ASC_COMPANY_1_KEY_ID": "TEAMKEY",
            "ASC_COMPANY_1_ISSUER_ID": "TEAMISSUER",
            "ASC_COMPANY_1_KEY_PATH": "/tmp/team.p8",
            "ASC_COMPANY_2_KEY_ID": "INDIVKEY",
            "ASC_COMPANY_2_KEY_PATH": "/tmp/individual.p8"
        ]

        let config = CompaniesManager.loadFromEnvironment(env: env)

        #expect(config?.companies.count == 2)
        #expect(config?.companies.first?.isIndividualKey == false)
        #expect(config?.companies.dropFirst().first?.isIndividualKey == true)
    }

    @Test("Missing key ID returns nil")
    func loadFromEnvironment_missingKeyIDReturnsNil() {
        let config = CompaniesManager.loadFromEnvironment(env: [:])

        #expect(config == nil)
    }

    @Test("Individual key loads from key content")
    func loadFromEnvironment_individualKeyWithKeyContent() {
        let env = [
            "ASC_KEY_ID": "TESTKEY",
            "ASC_PRIVATE_KEY": "-----BEGIN PRIVATE KEY-----\nTEST\n-----END PRIVATE KEY-----"
        ]

        let config = CompaniesManager.loadFromEnvironment(env: env)

        #expect(config?.companies.count == 1)
        #expect(config?.companies.first?.isIndividualKey == true)
        #expect(config?.companies.first?.privateKeyContent != nil)
        #expect(config?.companies.first?.privateKeyPath == "")
    }
}
