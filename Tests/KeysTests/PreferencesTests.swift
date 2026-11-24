import Testing
@testable import Keys

@Suite("Preferences")
struct PreferencesTests {
    @Test func theLastBackupIsReadAsWrittenNow() {
        #expect(lastBackupSeconds(storedAs: "seconds") == 800_000_000)
    }

    /// Builds before stored a date there, which Settings read as no backup at all.
    @Test func aDateFromEarlierBuildsStillCounts() {
        #expect(lastBackupSeconds(storedAs: "date") == 800_000_000)
    }

    @Test func noBackupIsNone() {
        #expect(lastBackupSeconds(storedAs: "none") == nil)
    }
}
