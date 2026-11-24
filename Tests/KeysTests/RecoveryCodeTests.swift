import Testing
@testable import Keys

@Suite("Recovery codes")
struct RecoveryCodeTests {
    @Test func readsNumberedListsAsServicesShowThem() {
        let text = """
        1. aaaa1-bbbb2
        2) cccc3-dddd4
         #3  eeee5-ffff6

        - gggg7-hhhh8
        • iiii9-jjjj0
        10. kkkk1-llll22
        """
        #expect(RecoveryCode.parse(text) == ["aaaa1-bbbb2", "cccc3-dddd4", "eeee5-ffff6", "gggg7-hhhh8", "iiii9-jjjj0", "kkkk1-llll22"])
    }

    @Test func readsCodesSeparatedByCommasOrSpacesAndDropsRepeats() {
        #expect(RecoveryCode.parse("abc-123, def-456 ghi-789,abc-123") == ["abc-123", "def-456", "ghi-789"])
    }

    @Test func aCodeThatIsANumberStaysWhole() {
        // Some services give plain digits: only a number followed by ".", ")" or ":" is numbering.
        #expect(RecoveryCode.parse("12345678\n87654321") == ["12345678", "87654321"])
    }

    @Test func nothingToReadIsNoCodes() {
        #expect(RecoveryCode.parse("  \n\n ").isEmpty)
    }

    @Test func anAccessWithOnlyCodesIsKept() {
        var credential = Credential()
        #expect(credential.isEmpty)
        credential.recoveryCodes = [RecoveryCode(code: "aaaa1-bbbb2")]
        #expect(!credential.isEmpty)
    }

    @Test func codesAndWhichWereUsedSurviveTheVaultFile() {
        #expect(recoveryCodesAfterSaving() == ["aaaa1-bbbb2:used", "cccc3-dddd4:unused"])
        #expect(recoveryCodesFromOldVault().isEmpty)
    }
}
