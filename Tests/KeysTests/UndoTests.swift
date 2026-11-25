import Testing
@testable import Keys

@Suite("Putting deleted things back")
struct UndoTests {
    @MainActor @Test func deletedThingsGoBackWhereTheyWere() {
        #expect(afterDeletingAndPuttingBack() == "A,B,C|X,Y|One,Two")
    }
}
