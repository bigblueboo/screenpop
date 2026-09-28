import Foundation
import Testing
@testable import ScreenpopCore

@Suite struct SlugTests {
    @Test func keepsCleanKebabCase() {
        #expect(FileNaming.slug("stripe-checkout-card-declined") == "stripe-checkout-card-declined")
    }

    @Test func normalizesCaseSpacingAndPunctuation() {
        #expect(FileNaming.slug("  Red Macaw: Portrait!! ") == "red-macaw-portrait")
        #expect(FileNaming.slug("figma_pricing--table") == "figma-pricing-table")
    }

    @Test func stripsImageExtensionAndDiacritics() {
        #expect(FileNaming.slug("Café Menü.png") == "cafe-menu")
    }

    @Test func dropsPathSeparators() {
        #expect(FileNaming.slug("../../etc/passwd") == "etc-passwd")
    }

    @Test func truncatesOnWordBoundary() {
        let slug = FileNaming.slug("alpha bravo charlie delta", maxLength: 18)
        #expect(slug == "alpha-bravo")
    }

    @Test func truncatesSingleLongWord() {
        #expect(FileNaming.slug(String(repeating: "a", count: 80), maxLength: 10) == "aaaaaaaaaa")
    }

    @Test func rejectsEmpty() {
        #expect(FileNaming.slug("  ...  ") == nil)
        #expect(FileNaming.slug("日本語") == nil)
    }
}

@Suite struct FileNamingTests {
    let folder = URL(fileURLWithPath: "/tmp/shots")

    @Test func uniqueURLAppendsCounter() {
        let taken: Set<String> = ["/tmp/shots/parrot.png", "/tmp/shots/parrot-2.png"]
        let url = FileNaming.uniqueURL(in: folder, base: "parrot") { taken.contains($0.path) }
        #expect(url.path == "/tmp/shots/parrot-3.png")
    }

    @Test func timestampIsDeterministic() {
        let date = Date(timeIntervalSince1970: 0)
        #expect(FileNaming.timestamp(date, timeZone: TimeZone(identifier: "UTC")!) == "Screenpop 1970-01-01 at 00.00.00")
    }
}

@Suite struct EnvFileTests {
    @Test func readsExportedQuotedValue() {
        let text = """
            # comment
            OTHER=1
            export OPENAI_API_KEY="sk-abc"
            """
        #expect(EnvFile.value(for: "OPENAI_API_KEY", in: text) == "sk-abc")
    }

    @Test func ignoresPrefixMatchesAndBlanks() {
        #expect(EnvFile.value(for: "OPENAI_API_KEY", in: "OPENAI_API_KEY_OLD=x\nOPENAI_API_KEY=") == nil)
    }
}

@Suite struct NamerParsingTests {
    @Test func extractsNameFromResponsesOutput() throws {
        let json = """
            {"output":[{"type":"reasoning","summary":[]},
             {"type":"message","content":[{"type":"output_text","text":"{\\"name\\":\\"red-macaw-portrait\\"}"}]}]}
            """
        #expect(try Namer.parseName(from: Data(json.utf8)) == "red-macaw-portrait")
    }

    @Test func throwsWhenNoMessage() {
        #expect(throws: NamerError.unusableReply) {
            try Namer.parseName(from: Data(#"{"output":[]}"#.utf8))
        }
    }

    @Test func readsAPIErrorMessage() {
        let json = #"{"error":{"message":"You have no credits remaining.","type":"insufficient_quota"}}"#
        #expect(Namer.errorMessage(in: Data(json.utf8)) == "You have no credits remaining.")
    }

    @Test func requestBodyIsValidJSON() throws {
        let body = Namer.body(model: "gpt-6-luna", jpeg: Data([0xFF, 0xD8]))
        let data = try JSONSerialization.data(withJSONObject: body)
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(decoded["model"] as? String == "gpt-6-luna")
    }
}
