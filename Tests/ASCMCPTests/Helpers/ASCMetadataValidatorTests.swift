import Testing
@testable import asc_mcp

@Suite("ASC Metadata Validator Tests")
struct ASCMetadataValidatorTests {
    @Test("rejects emoji in metadata text")
    func rejectsEmoji() {
        let errors = ASCMetadataValidator.validateTextFields(["description": "Hello 👋"])
        #expect(errors.contains { $0.field == "description" })

        for emoji in ["1️⃣", "#️⃣", "*️⃣", "1⃣", "©️", "®️", "™️", "ℹ️", "🎉", "🔥", "❤️", "☀️", "🇺🇸"] {
            #expect(ASCMetadataValidator.containsEmoji(emoji), "Expected '\(emoji)' to be detected as emoji")
        }
        for plain in ["1", "#", "*", "©", "®", "™", "𠮷", "𠮟", "𠮷野の便利な機能を継続"] {
            #expect(!ASCMetadataValidator.containsEmoji(plain), "Expected '\(plain)' not to be detected as emoji")
        }
    }

    @Test("rejects over-limit text")
    func rejectsOverLimitText() {
        let errors = ASCMetadataValidator.validateTextFields(
            ["keywords": String(repeating: "a", count: 101)],
            limits: ["keywords": 100]
        )

        #expect(errors == [
            ASCMetadataValidator.FieldError(field: "keywords", message: "Value exceeds 100 characters")
        ])
    }

    @Test("rejects invalid locale")
    func rejectsInvalidLocale() {
        let errors = ASCMetadataValidator.validateLocale("english_US")
        #expect(errors.count == 1)
    }

    @Test("accepts valid locale formats")
    func acceptsValidLocales() {
        #expect(ASCMetadataValidator.validateLocale("en-US").isEmpty)
        #expect(ASCMetadataValidator.validateLocale("ru-RU").isEmpty)
        #expect(ASCMetadataValidator.validateLocale("ja").isEmpty)
        #expect(ASCMetadataValidator.validateLocale("zh-Hans").isEmpty)
    }

    @Test("validates absolute HTTP URLs")
    func validatesHTTPURLs() {
        #expect(ASCMetadataValidator.validateHTTPURL("https://example.com/privacy", field: "privacyPolicyUrl").isEmpty)
        #expect(!ASCMetadataValidator.validateHTTPURL("ftp://example.com/file", field: "privacyPolicyUrl").isEmpty)
        #expect(!ASCMetadataValidator.validateHTTPURL("/relative/path", field: "privacyPolicyUrl").isEmpty)
    }
}
