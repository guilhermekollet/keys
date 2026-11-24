import Testing
@testable import Keys

/// Two copies of the app on one vault, on a `FakeMac`.
@Suite("Two copies of the app")
@MainActor
struct StaleSaveTests {
    /// Two copies open on the same vault, which holds "Base".
    private func twoCopies(on mac: FakeMac) async throws -> (a: Vault, b: Vault) {
        try mac.installEarlierVersion(holding: "Base")
        let a = mac.launch(), b = mac.launch()
        await a.unlock()
        await b.unlock()
        return (a, b)
    }

    @Test func lockingWithoutEditsKeepsTheOtherCopysWork() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        let (a, b) = try await twoCopies(on: mac)
        a.addProject()
        a.lock()

        b.lock()
        await b.unlock()
        #expect(b.projects.count == 2)
        b.lock()
    }

    @Test func openingAndLockingDoesNotRewriteTheVault() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Base")
        let bytes = mac.vaultBytes()
        let vault = mac.launch()
        await vault.unlock()
        // Longer than a save waits after an edit.
        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(mac.vaultBytes() == bytes)
        vault.lock()
        #expect(mac.vaultBytes() == bytes)
        #expect(mac.copies().isEmpty)
    }

    @Test func editsOnBothSidesAreBothKept() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        let (a, b) = try await twoCopies(on: mac)
        a.projects[0].name = "From A"
        a.saveNow()
        b.projects[0].name = "From B"
        b.saveNow()

        // The copy that came second locks, saying where its edits went.
        #expect(b.state == .locked)
        #expect(b.projects.isEmpty)
        let aside = try #require(mac.files().first { $0.hasPrefix("vault-unsaved-") })
        #expect(b.problem?.contains(aside) == true)

        let current = mac.launch()
        await current.unlock()
        #expect(current.projects.map(\.name) == ["From A"])
        current.lock()
        a.lock()

        try mac.useAsVault(aside)
        let other = mac.launch()
        await other.unlock()
        #expect(other.projects.map(\.name) == ["From B"])
        other.lock()
    }

    @Test func savingAgainAndAgainIsNotAConflict() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Base")
        let vault = mac.launch()
        await vault.unlock()
        for round in 1...5 {
            vault.projects[0].name = "Edit \(round)"
            #expect(vault.saveNow())
        }
        vault.lock()
        #expect(mac.files() == ["Backups", "vault.keys"])
    }

    @Test func aVaultBehindALinkIsNotAConflict() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Base")
        try mac.keepVaultBehindLink()
        let vault = mac.launch()
        await vault.unlock()
        vault.addProject()
        vault.saveNow()
        vault.addProject()
        vault.saveNow()
        #expect(vault.state == .unlocked)
        vault.lock()
        await vault.unlock()
        #expect(vault.projects.count == 3)
        vault.lock()
    }

    @Test func everyFileKeptAsideIsNamedUntilQuitting() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        let (a, b) = try await twoCopies(on: mac)
        // Twice, within the same second.
        for _ in 1...2 {
            a.addProject()
            a.saveNow()
            b.addProject()
            #expect(b.prepareToQuit())
            await b.unlock()
        }
        let asides = mac.files().filter { $0.hasPrefix("vault-unsaved-") }
        #expect(asides.count == 2)
        for name in asides {
            #expect(b.keptAside?.contains(name) == true)
            #expect(b.problem?.contains(name) == true)
        }
        a.lock()
        b.lock()
    }

    @Test func aConflictWithNowhereToWriteWaitsSealed() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        let (a, b) = try await twoCopies(on: mac)
        a.addProject()
        a.lock()
        let current = mac.vaultBytes()
        b.addProject()
        try mac.setWritable(false)
        b.lock()
        #expect(b.state == .locked)
        #expect(b.hasUnsavedEdits)

        try mac.setWritable(true)
        #expect(b.prepareToQuit())
        #expect(mac.vaultBytes() == current)
        #expect(mac.files().contains { $0.hasPrefix("vault-unsaved-") })
    }

    @Test func aFileThatCannotBeReadIsRetriedAndNotSetAside() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Base")
        let vault = mac.launch()
        await vault.unlock()
        vault.addProject()
        try mac.setVaultReadable(false)
        #expect(!vault.saveNow())
        #expect(vault.state == .unlocked)

        try mac.setVaultReadable(true)
        #expect(vault.saveNow())
        #expect(!mac.files().contains { $0.hasPrefix("vault-unsaved-") })
        vault.lock()
    }

    @Test func aBusyFolderFailsTheSaveWithoutWriting() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Base")
        let vault = mac.launch()
        await vault.unlock()
        vault.addProject()
        let bytes = mac.vaultBytes()
        var saved = true
        try mac.whileFolderIsLocked { saved = vault.saveNow() }
        #expect(!saved)
        #expect(mac.vaultBytes() == bytes)
        #expect(vault.saveNow())
        vault.lock()
    }

    @Test func aVaultThatIsGoneIsWrittenBack() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Base")
        let vault = mac.launch()
        await vault.unlock()
        try mac.removeVault()
        vault.lock()
        await vault.unlock()
        #expect(vault.projects.map(\.name) == ["Base"])
        vault.lock()
    }

    @Test func importingIntoAStaleCopyDoesNotReplaceTheVault() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        let (a, b) = try await twoCopies(on: mac)
        a.addProject()
        a.lock()
        let current = mac.vaultBytes()
        try await mac.importBackup(holding: "Imported", into: b)
        b.lock()
        #expect(mac.vaultBytes() == current)
        #expect(mac.files().contains { $0.hasPrefix("vault-unsaved-") })
    }
}
