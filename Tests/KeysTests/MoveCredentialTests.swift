import Testing
@testable import Keys

@Suite("Moving accesses")
struct MoveCredentialTests {
    @Test(arguments: ["Grupo", "API", "Checkout", "Site"])
    func anAccessMovesWholeToAnyProjectOrSubproject(destination: String) {
        let result = movingAccess(to: destination)
        #expect(result.places == ["\(destination)/Banco", "Loja/Painel"].sorted())
        #expect(result.intact)
        #expect(result.stamped == [destination, "Loja"].sorted())
    }

    @Test func impossibleMovesLeaveEverythingInPlace() {
        #expect(impossibleMovesChangeNothing() == [true, true, true, true])
    }

    @Test func destinationsLeaveOutItsOwnProjectAndArchivedOnes() {
        #expect(accessDestinations(from: "Loja", archived: "Site") == ["Grupo", "Grupo › API", "Grupo › Loja › Checkout"])
    }

    @Test func aMoveIsSaved() {
        #expect(moveSurvivesSaving())
    }

    @Test(arguments: OtherMac.allCases, [false, true])
    func mergingABackupNeverLosesOrRepeatsAMovedAccess(other: OtherMac, reversed: Bool) {
        let result = mergingAfterMove(other, reversed: reversed)
        let place = other == .movedLater ? "Site" : "API"
        #expect(result.places == ["\(place)/Banco", "Loja/Painel"].sorted())
        #expect(result.password == (other == .changedPassword ? "new" : "old"))
        #expect(result.repeatUpdates == 0)
    }
}
