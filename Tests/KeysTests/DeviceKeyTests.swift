import Testing
@testable import Keys

private let original = "com.guilhermekollet.keys/device-key"

/// Everything here runs on a `FakeMac`: never the real Keychain, Secure Enclave or vault folder.
@Suite("Device key")
@MainActor
struct DeviceKeyTests {
    // MARK: Existing installs

    @Test func aVaultFromAnEarlierVersionOpensWithItsItem() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Real")
        let items = mac.keychain.items

        let vault = mac.launch()
        await vault.unlock()
        #expect(vault.state == .unlocked)
        #expect(vault.projects.map(\.name) == ["Real"])

        // Saving needs no migration either.
        vault.addProject()
        vault.lock()
        let again = mac.launch()
        await again.unlock()
        #expect(again.projects.count == 2)
        again.lock()
        #expect(mac.keychain.items == items)
    }

    @Test func aLinkToTheDefaultFolderIsStillTheDefault() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Real")
        try mac.linkToStandardFolder()

        let vault = mac.launch(.standardThroughLink)
        await vault.unlock()
        #expect(vault.state == .unlocked)
        vault.lock()
    }

    @Test func theDefaultFolderInAnotherCaseIsStillTheDefault() {
        let mac = FakeMac()
        defer { mac.dispose() }
        // Before the folder exists there is no name on disk to take the case from.
        let vault = mac.launch(.standardInOtherCase)
        vault.create()
        vault.lock()
        #expect(mac.keychain.added.count == 1)
        #expect(mac.keychain.added.allSatisfy { $0.hasPrefix("com.guilhermekollet.keys/") })
    }

    // MARK: Custom folders

    @Test(arguments: [false, true])
    func aCustomFolderNeverTouchesTheDefaultItems(fromBackup: Bool) async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Real")
        let key = mac.keychain.items[original]

        let custom = mac.launch(.custom)
        if fromBackup {
            try await mac.importBackup(holding: "Trial", into: custom)
        } else {
            custom.create()
        }
        #expect(custom.state == .unlocked)
        custom.lock()
        await custom.unlock()
        #expect(custom.state == .unlocked)
        custom.lock()

        #expect(mac.keychain.items[original] == key)
        let touched = mac.keychain.asked + mac.keychain.added
        #expect(touched.allSatisfy { $0.hasPrefix("com.guilhermekollet.keys.custom-folder/device-key.") })

        let real = mac.launch()
        await real.unlock()
        #expect(real.projects.map(\.name) == ["Real"])
        real.lock()
    }

    @Test func aCustomFolderWithoutItsKeyDoesNotBorrowTheDefaultOne() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Real")
        try mac.move(.standard, to: .custom)

        let vault = mac.launch(.custom)
        await vault.unlock()
        #expect(vault.state == .unreadable(VaultError.missingDeviceKey.localizedDescription))
        // Its own key is all it looks for: no single item, in either service.
        #expect(mac.keychain.asked.allSatisfy { $0.hasPrefix("com.guilhermekollet.keys.custom-folder/device-key.") })
    }

    @Test func aCustomFolderCanBeMoved() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        let vault = mac.launch(.custom)
        vault.create()
        vault.lock()
        try mac.move(.custom, to: .otherCustom)

        let moved = mac.launch(.otherCustom)
        await moved.unlock()
        #expect(moved.state == .unlocked)
        moved.lock()
    }

    @Test func twoCustomFoldersKeepAKeyEach() async {
        let mac = FakeMac()
        defer { mac.dispose() }
        for folder in [FakeMac.Folder.custom, .otherCustom] {
            let vault = mac.launch(folder)
            vault.create()
            vault.lock()
        }
        #expect(mac.keychain.items.count == 2)
        for folder in [FakeMac.Folder.custom, .otherCustom] {
            let vault = mac.launch(folder)
            await vault.unlock()
            #expect(vault.state == .unlocked)
            vault.lock()
        }
    }

    // MARK: Failed access

    @Test(arguments: KeychainFailure.allCases, [false, true])
    func aFailedReadOffersRetryAndNotANewVault(failure: KeychainFailure, earlierVersion: Bool) async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        if earlierVersion {
            try mac.installEarlierVersion(holding: "Real")
        } else {
            let vault = mac.launch()
            vault.create()
            vault.lock()
        }
        let items = mac.keychain.items
        mac.keychain.readFailure = failure

        let vault = mac.launch()
        await vault.unlock()
        #expect(vault.state == .locked)
        #expect(vault.keyAccessFailed)
        #expect(vault.problem != nil)
        #expect(mac.files() == ["vault.keys"])

        // Trying again, once access is back, is all it takes.
        mac.keychain.readFailure = nil
        await vault.unlock()
        #expect(vault.state == .unlocked)
        #expect(!vault.keyAccessFailed)
        #expect(vault.problem == nil)
        vault.lock()
        #expect(mac.keychain.items == items)
    }

    @Test(arguments: [KeychainFailure.locked, .denied, .cancelled, .noAccess])
    func aFailedLookupIsNotAMissingItem(failure: KeychainFailure) async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Real")
        mac.keychain.lookupFailure = failure

        let vault = mac.launch()
        await vault.unlock()
        #expect(vault.state == .locked)
        #expect(vault.keyAccessFailed)
    }

    @Test func anItemThatIsNotThereIsMissing() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Real")
        _ = mac.keychain.take(original)

        let vault = mac.launch()
        await vault.unlock()
        #expect(vault.state == .unreadable(VaultError.missingDeviceKey.localizedDescription))
        #expect(!vault.keyAccessFailed)
    }

    @Test func anotherKeyIsRecognized() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Real")
        mac.replaceOriginalKey()

        let vault = mac.launch()
        await vault.unlock()
        #expect(vault.state == .unreadable(VaultError.otherDeviceKey.localizedDescription))
    }

    @Test func onlyABadHandleMakesTheVaultUnreadable() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Real")

        let vault = mac.launch()
        mac.enclave.failure = .busy
        await vault.unlock()
        #expect(vault.state == .locked)
        #expect(vault.problem != nil)

        mac.enclave.failure = .cancelled
        await vault.unlock()
        #expect(vault.state == .locked)
        #expect(vault.problem == nil)

        mac.enclave.failure = .badHandle
        await vault.unlock()
        #expect(vault.state == .unreadable(VaultError.unusableDeviceKey.localizedDescription))
    }

    // MARK: Creating

    @Test(arguments: [false, true])
    func replacingAnUnreadableVaultKeepsItsKey(fromBackup: Bool) async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        try mac.installEarlierVersion(holding: "Real")
        let key = mac.keychain.items[original]

        // A handle the Secure Enclave refuses for now, though it is still good.
        mac.enclave.failure = .badHandle
        let vault = mac.launch()
        await vault.unlock()
        if fromBackup {
            try await mac.importBackup(holding: "New", into: vault)
        } else {
            vault.setAsideUnreadable()
            vault.create()
        }
        #expect(vault.state == .unlocked)
        vault.lock()
        #expect(mac.keychain.items[original] == key)
        #expect(mac.keychain.items.count == 2)

        // The new vault opens, and so does the one set aside once it is put back.
        mac.enclave.failure = nil
        await vault.unlock()
        #expect(vault.state == .unlocked)
        vault.lock()
        try mac.putBackVaultSetAside()
        let restored = mac.launch()
        await restored.unlock()
        #expect(restored.projects.map(\.name) == ["Real"])
        restored.lock()
    }

    @Test func aVaultSetAsideOpensOnceItsKeyIsRecovered() async throws {
        let mac = FakeMac()
        defer { mac.dispose() }
        let first = mac.launch()
        first.create()
        first.addProject()
        first.lock()
        let name = try #require(mac.keychain.added.first)
        let lost = mac.keychain.take(name)

        await first.unlock()
        first.setAsideUnreadable()
        first.create()
        first.lock()

        mac.keychain.putBack(lost, as: name)
        try mac.putBackVaultSetAside()
        let restored = mac.launch()
        await restored.unlock()
        #expect(restored.projects.count == 1)
        restored.lock()
    }

    @Test func creatingWithoutAVaultFileKeepsTheKeyThatIsThere() async {
        let mac = FakeMac()
        defer { mac.dispose() }
        // The vault file is gone (moved, or not restored yet), and the Keychain won't be read.
        mac.replaceOriginalKey()
        let key = mac.keychain.items[original]
        mac.keychain.readFailure = .denied

        let vault = mac.launch()
        vault.create()
        #expect(vault.state == .unlocked)
        #expect(mac.keychain.items[original] == key)
        vault.lock()
    }

    @Test func aKeyThatCannotBeSavedMakesNoVault() {
        let mac = FakeMac()
        defer { mac.dispose() }
        mac.replaceOriginalKey()
        let items = mac.keychain.items
        mac.keychain.refusesNewItems = true

        let vault = mac.launch()
        vault.create()
        #expect(vault.state == .new)
        #expect(vault.problem != nil)
        #expect(mac.files().isEmpty)
        #expect(mac.keychain.items == items)
    }
}
