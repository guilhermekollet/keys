import Testing
@testable import Keys

/// The ways a vault could lose what it holds. Like the device key's tests, all on a `FakeMac`.
@Suite("Vault data loss")
@MainActor
struct VaultLossTests {
    // MARK: A save that fails

    @Test func lockingKeepsEditsThatCouldNotBeSaved() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        let vault = mac.launch()
        vault.create()
        vault.addProject()
        try mac.setWritable(false)

        vault.lock()
        #expect(vault.state == .locked)
        #expect(vault.projects.isEmpty)

        await vault.unlock()
        #expect(vault.projects.count == 1)
        try mac.setWritable(true)
        vault.lock()
    }

    @Test func waitingEditsReachTheDiskWithoutUnlocking() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        let vault = mac.launch()
        vault.create()
        vault.addProject()
        try mac.setWritable(false)
        vault.lock()
        #expect(vault.hasUnsavedEdits)
        #expect(!vault.prepareToQuit())

        try mac.setWritable(true)
        #expect(vault.prepareToQuit())
        #expect(!vault.hasUnsavedEdits)
        #expect(vault.problem == nil)
        let again = mac.launch()
        await again.unlock()
        #expect(again.projects.count == 1)
        again.lock()
    }

    @Test func quittingSavesTheOpenVault() async {
        let mac = FakeMac()
        defer { mac.dispose() }
        let vault = mac.launch()
        vault.create()
        vault.addProject()
        #expect(vault.prepareToQuit())
        let again = mac.launch()
        await again.unlock()
        #expect(again.projects.count == 1)
        again.lock()
    }

    @Test func quittingIsHeldBackWhileTheOpenVaultCannotBeSaved() throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        let vault = mac.launch()
        vault.create()
        vault.addProject()
        try mac.setWritable(false)
        #expect(!vault.prepareToQuit())
        #expect(vault.state == .locked)
        #expect(vault.projects.isEmpty)
    }

    @Test func deletingTheLastProjectIsKeptToo() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Old")
        let vault = mac.launch()
        await vault.unlock()
        let id = try #require(vault.projects.first?.id)
        vault.deleteProject(id)
        try mac.setWritable(false)
        vault.lock()
        await vault.unlock()
        #expect(vault.projects.isEmpty)

        // Failing again doesn't look like someone else changed the file.
        vault.lock()
        try mac.setWritable(true)
        #expect(vault.prepareToQuit())
        #expect(mac.files() == ["Backups", "vault.keys"])
        let again = mac.launch()
        await again.unlock()
        #expect(again.projects.isEmpty)
        again.lock()
    }

    @Test func theCopyFromBeforeTheSessionIsStillTaken() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Old")
        let vault = mac.launch()
        await vault.unlock()
        vault.addProject()
        try mac.setWritable(false)
        vault.lock()
        try mac.setWritable(true)
        #expect(vault.prepareToQuit())

        let copy = try #require(mac.copies().first)
        try mac.useCopyAsVault(copy)
        let before = mac.launch()
        await before.unlock()
        #expect(before.projects.map(\.name) == ["Old"])
        before.lock()
    }

    @Test func waitingEditsNeverReplaceAVaultThatChanged() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        let vault = mac.launch()
        vault.create()
        vault.addProject()
        try mac.setWritable(false)
        vault.lock()
        try mac.setWritable(true)
        try mac.changeVaultOnDisk()
        let changed = mac.vaultBytes()

        #expect(vault.prepareToQuit())
        #expect(mac.vaultBytes() == changed)
        #expect(vault.problem != nil)
        let aside = try #require(mac.files().first { $0.hasPrefix("vault-unsaved-") })
        try mac.useAsVault(aside)
        let again = mac.launch()
        await again.unlock()
        #expect(again.projects.count == 1)
        again.lock()
    }

    @Test func waitingEditsDoNotOpenOverAVaultThatChanged() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        let vault = mac.launch()
        vault.create()
        vault.addProject()
        try mac.setWritable(false)
        vault.lock()
        // Changed, and still nowhere to put the edits.
        try mac.setWritable(true)
        try mac.changeVaultOnDisk()
        try mac.setWritable(false)

        await vault.unlock()
        #expect(vault.state == .locked)
        #expect(vault.hasUnsavedEdits)
    }

    @Test func aSaveThatWorksTakesBackTheWarning() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        let vault = mac.launch()
        vault.create()
        vault.addProject()
        try mac.setWritable(false)
        vault.saveNow()
        #expect(vault.problem != nil)
        try mac.setWritable(true)
        vault.saveNow()
        #expect(vault.problem == nil)
        vault.lock()
    }

    // MARK: Creating

    @Test func onlyOneOfRacingWritesMakesTheFile() throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        let vault = mac.launch()
        vault.create()
        vault.lock()
        let result = try mac.racesWithoutOneWinner(rounds: 200)
        #expect(result.bad == 0)
        #expect(result.permissions == [0o600])
        #expect(!mac.files().contains { $0.hasSuffix(".tmp") })
    }

    @Test func importingAgainAfterTheRefusalDoesNotClaimSuccess() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        let late = mac.launch()
        let first = mac.launch()
        first.create()
        first.lock()
        for _ in 1...2 {
            await #expect(throws: VaultError.vaultExists) {
                try await mac.importBackup(holding: "Other", into: late)
            }
        }
    }

    @Test(arguments: [false, true])
    func creatingNeverOverwritesAVaultThatAppeared(fromBackup: Bool) async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        let late = mac.launch()
        let first = mac.launch()
        first.create()
        first.addProject()
        first.lock()

        if fromBackup {
            try? await mac.importBackup(holding: "Other", into: late)
        } else {
            late.create()
        }
        #expect(late.state == .locked)
        #expect(mac.keychain.added.count == 1)
        await first.unlock()
        #expect(first.projects.count == 1)
        first.lock()
    }

    // MARK: Automatic copies

    @Test func pruningCountsOnlyTheCurrentVaultsCopies() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Old")
        try mac.addCopies(Vault.backupCount, year: 2020)
        mac.replaceOriginalKey()

        let vault = mac.launch()
        await vault.unlock()
        vault.setAsideUnreadable()
        vault.create()
        vault.lock()
        try mac.addCopies(Vault.backupCount, year: 2021)
        await vault.unlock()
        vault.lock()

        let copies = mac.copies()
        #expect(copies.filter { $0.hasPrefix("vault-2020") }.count == Vault.backupCount)
        #expect(copies.count == 2 * Vault.backupCount)
        #expect(!copies.contains("vault-20210101-120000.keys"))
    }
}
