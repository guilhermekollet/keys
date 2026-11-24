import AppKit
import CryptoKit
import SwiftUI

/// The vault while the app runs: locked, or open with its projects in memory. Every change is
/// sealed and written back to disk shortly after it is made.
@MainActor
final class Vault: ObservableObject {
    static let shared = Vault(
        sample: CommandLine.arguments.contains("--sample") || CommandLine.arguments.contains("--snapshot"),
        directory: directory,
        deviceKey: systemDeviceKey(for: directory)
    )

    enum State: Equatable {
        /// There is no vault on this Mac yet.
        case new
        case locked
        case unlocked
        /// There is a vault, but it can't be opened here; the text says why.
        case unreadable(String)
    }

    @Published private(set) var state: State
    @Published var projects: [Project] = [] {
        didSet {
            // Only edits: opening sets the projects before the state, so it never writes by itself.
            if state == .unlocked, projects != oldValue {
                edited = true
                scheduleSave()
            }
        }
    }
    /// The project open in the main window, and the part of it on screen; the menu bar panel
    /// sets them too, to open an access or a variable where it is.
    @Published var selection: Project.ID?
    @Published var section = ProjectSection.all
    @Published private(set) var isUnlocking = false
    /// When Touch ID last opened the vault; it locks again `Preferences.unlockMinutes` later.
    @Published private(set) var unlockedAt: Date?
    /// Whether the last attempt to unlock failed at the Keychain: the key may well be fine, so
    /// the lock screen offers to try again, never a new vault.
    @Published private(set) var keyAccessFailed = false
    /// The edits a lock couldn't save. They wait in memory sealed like the file, so the vault
    /// still locks, with no key and nothing readable kept, and saving them needs no Touch ID.
    @Published private var unsaved: UnsavedEdits?
    var hasUnsavedEdits: Bool { unsaved != nil }
    /// The last thing that went wrong, shown until the next attempt.
    @Published var problem: String?
    /// The lock screen asks for Touch ID by itself once per launch; after a lock it waits for a click.
    var askedOnLaunch = false
    /// `--sample` (and `--snapshot`) open a made-up vault in memory, for screenshots and UI work.
    /// Nothing is saved and it never locks.
    let isSample: Bool

    private let directory: URL
    private let deviceKey: DeviceKey
    private struct UnsavedEdits {
        let sealed: VaultFile
        /// The file as last saved. They only replace the vault while it is still this.
        let lastSaved: VaultFile
    }

    private var key: SymmetricKey?
    /// The vault as last read from or written to disk.
    private var file: VaultFile?
    private var pendingSave: Task<Void, Never>?
    private var savingAgain: Task<Void, Never>?
    /// Says where edits went when the vault changed before they could be saved. It outlives
    /// `problem`, so unlocking doesn't hide it.
    @Published private(set) var keptAside: String?
    private var filesKeptAside: [String] = []
    /// Whether anything open here still has to be written. Without it nothing is: the file may
    /// hold another copy's newer work.
    private var edited = false
    /// Whether `problem` is a failed save, which the next one that works takes back.
    private var saveFailed = false
    private var backedUp = false
    private let autoLock = AutoLock()

    /// `KEYS_VAULT_DIR` points the app at another folder, to try things without touching your
    /// vault. Its keys are kept apart too (see DeviceKey).
    static var directory: URL {
        if let custom = ProcessInfo.processInfo.environment["KEYS_VAULT_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return defaultDirectory
    }

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Keys")
    }

    private static func systemDeviceKey(for directory: URL) -> DeviceKey {
        DeviceKey(directory: directory, defaultDirectory: defaultDirectory, items: SystemKeychainItems(), enclave: SystemEnclave())
    }

    var fileURL: URL { directory.appendingPathComponent("vault.keys") }
    var backupsURL: URL { directory.appendingPathComponent("Backups") }
    /// How many earlier copies of the vault are kept.
    static let backupCount = 20

    init(sample: Bool, directory: URL, deviceKey: DeviceKey) {
        isSample = sample
        self.directory = directory
        self.deviceKey = deviceKey
        if sample {
            state = .unlocked
            unlockedAt = Date()
            projects = SampleVault.projects
            selection = projects.first { !$0.credentials.isEmpty && $0.parentID != nil }?.id
        } else {
            state = FileManager.default.fileExists(atPath: directory.appendingPathComponent("vault.keys").path) ? .locked : .new
        }
    }

    /// A vault in memory that only shows `state`, for drawing the lock screen (see Snapshot).
    init(previewing state: State, accessError: KeychainAccessError? = nil) {
        isSample = true
        directory = Self.directory
        deviceKey = Self.systemDeviceKey(for: Self.directory)
        keyAccessFailed = accessError != nil
        problem = accessError?.localizedDescription
        askedOnLaunch = true
        self.state = state
    }

    // MARK: Locking

    /// Creates the device key and an empty vault for it.
    func create() {
        guard !isSample else { return }
        problem = nil
        do {
            try createVault(with: VaultContents())
        } catch {
            problem = error.localizedDescription
        }
    }

    /// A new device key and a vault for it holding `contents`.
    private func createVault(with contents: VaultContents) throws {
        let file: VaultFile, key: SymmetricKey
        do {
            // Looked at first so no key is made for nothing; `writeNew` is what guarantees it.
            (file, key) = try VaultFile.withFolderLocked(directory) {
                guard !FileManager.default.fileExists(atPath: fileURL.path) else { throw VaultError.vaultExists }
                let newKey = try deviceKey.create()
                let created = try VaultFile.create(Self.encode(contents), for: newKey)
                try created.file.writeNew(to: fileURL)
                return created
            }
        } catch VaultError.vaultExists {
            // It appeared after launch (another copy of the app, a restore): that one is the vault.
            state = .locked
            throw VaultError.vaultExists
        }
        self.file = file
        self.key = key
        backedUp = true
        unlockedAt = Date()
        projects = contents.projects
        edited = false
        state = .unlocked
        startAutoLock()
    }

    // MARK: Backups

    /// Writes a copy of the open vault to `url`, sealed with `password` (see VaultBackup).
    func exportBackup(password: String, to url: URL) async throws {
        guard state == .unlocked else { return }
        let plaintext = try Self.encode(VaultContents(projects: projects))
        // Deriving the key takes about half a second: off the main thread, so the window keeps drawing.
        let backup = try await Task.detached { try VaultBackup.seal(plaintext, password: password) }.value
        try backup.write(to: url)
        Preferences.recordBackup()
    }

    /// Brings in the backup at `url`. Into an open vault it merges (see `VaultContents.merging`).
    /// With no vault here, as on a new Mac, or one this Mac can't open, the backup becomes the
    /// vault, sealed for this Mac's own key; the unreadable vault is kept aside, renamed.
    func importBackup(from url: URL, password: String) async throws -> (added: Int, updated: Int) {
        let backup = try VaultBackup.read(from: url)
        let plaintext = try await Task.detached { try backup.open(password: password) }.value
        let contents = try Self.decode(plaintext)
        switch state {
        case .unlocked:
            let result = VaultContents(projects: projects).merging(contents)
            projects = result.contents.projects
            return (result.added, result.updated)
        case .new, .unreadable:
            guard !isSample else { return (0, 0) }
            if case .unreadable = state {
                setAsideUnreadable()
                guard state == .new else { throw VaultError.damaged }
            }
            problem = nil
            try createVault(with: contents)
            return (contents.projects.count, 0)
        case .locked:
            // The interface asks to unlock first; this is a vault that appeared, or locked, meanwhile.
            throw VaultError.vaultExists
        }
    }

    func unlock() async {
        guard state == .locked, !isUnlocking, !isSample else { return }
        isUnlocking = true
        defer { isUnlocking = false }
        problem = keptAside
        keyAccessFailed = false
        saveUnsaved()
        let waiting = unsaved
        // Opening edits over a vault that changed would end up replacing it: they wait instead.
        if let waiting, (try? changedOnDisk(since: waiting.lastSaved)) != false { return }
        do {
            let file = try waiting?.sealed ?? VaultFile.read(from: fileURL)
            // Checked before asking for Touch ID: a vault for another key can't open whatever the person does.
            let handle = try deviceKey.handle(for: file.recipient)
            let unlocked = try await deviceKey.unlock(handle, reason: localized("destrancar o cofre"))
            let key = try file.unwrapKey(with: unlocked)
            let contents = try Self.decode(file.open(with: key))
            self.file = waiting?.lastSaved ?? file
            self.key = key
            backedUp = false
            forgetUnsaved()
            unlockedAt = Date()
            projects = contents.projects
            edited = waiting != nil
            state = .unlocked
            // Edits opened from memory aren't on disk yet.
            if edited { scheduleSave() }
            if let selection, !projects.contains(where: { $0.id == selection }) { self.selection = nil }
            startAutoLock()
        } catch let error as KeychainAccessError {
            keyAccessFailed = true
            problem = error.localizedDescription
        } catch let error as VaultError where error != .newerVersion {
            state = .unreadable(error.localizedDescription)
        } catch where DeviceKey.isCancellation(error) {
            // Dismissing the prompt is not a problem worth reporting.
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Saves, forgets the key and the contents, and locks. What couldn't be saved is kept sealed
    /// (see `unsaved`).
    func lock() {
        guard state == .unlocked, !isSample else { return }
        if !saveNow() {
            // Without even a sealed copy, locking would be deleting: it stays open.
            guard let key, let file,
                  let plaintext = try? Self.encode(VaultContents(projects: projects)),
                  let sealed = try? file.resealing(plaintext, with: key)
            else { return }
            unsaved = UnsavedEdits(sealed: sealed, lastSaved: file)
            keepSavingAgain()
        }
        close()
    }

    /// Forgets the key and the contents, whatever became of them.
    private func close() {
        pendingSave?.cancel()
        pendingSave = nil
        autoLock.stop()
        edited = false
        key = nil
        file = nil
        unlockedAt = nil
        // Locked first, so clearing the projects isn't saved.
        state = .locked
        projects = []
    }

    /// Moves an unreadable vault aside (it is kept, renamed, next to where it was) so a new one
    /// can be created. Its key stays in the Keychain, so renamed back it opens again.
    func setAsideUnreadable() {
        guard saveUnsaved() else { return }
        let stamp = Self.stamp(Date())
        let destination = directory.appendingPathComponent("vault-unreadable-\(stamp).keys")
        do {
            try VaultFile.withFolderLocked(directory) {
                try FileManager.default.moveItem(at: fileURL, to: destination)
            }
            state = .new
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    /// When the vault will lock by itself, read with the current setting so a change applies at once.
    var locksAt: Date? {
        unlockedAt.map { $0.addingTimeInterval(TimeInterval(Preferences.unlockMinutes * 60)) }
    }

    private func startAutoLock() {
        guard !isSample else { return }
        autoLock.start(locksAt: { [weak self] in self?.locksAt }) { [weak self] in self?.lock() }
    }

    // MARK: Saving

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Saves the edits, if there are any; false when they couldn't be. If the vault changed since
    /// this copy read it, they are kept in a file of their own and this copy locks: what it shows
    /// is no longer the vault, and each further save would make another file.
    @discardableResult
    func saveNow() -> Bool {
        pendingSave?.cancel()
        pendingSave = nil
        guard state == .unlocked, !isSample, let key, let file else { return true }
        // With no edits there is only one thing to write: a vault that is no longer there.
        guard edited || !FileManager.default.fileExists(atPath: fileURL.path) else { return true }
        do {
            let updated = try file.resealing(Self.encode(VaultContents(projects: projects)), with: key)
            switch try store(updated, replacing: file) {
            case .saved:
                self.file = updated
                edited = false
                if saveFailed { problem = keptAside }
            case .keptAside:
                problem = keptAside
                close()
            }
            saveFailed = false
            return true
        } catch {
            reportFailedSave(error)
            return false
        }
    }

    private func reportFailedSave(_ error: Error) {
        saveFailed = true
        problem = localized("Não foi possível salvar o cofre: \(error.localizedDescription)")
    }

    /// Writes the edits a lock left waiting; true when none are left.
    @discardableResult
    func saveUnsaved() -> Bool {
        guard let unsaved else { return true }
        do {
            _ = try store(unsaved.sealed, replacing: unsaved.lastSaved)
            forgetUnsaved()
            saveFailed = false
            if !keyAccessFailed { problem = keptAside }
            return true
        } catch {
            reportFailedSave(error)
            return false
        }
    }

    /// Locks and saves, for quitting; false when quitting now would lose edits.
    func prepareToQuit() -> Bool {
        guard !isSample else { return true }
        lock()
        return state != .unlocked && saveUnsaved()
    }

    private enum Stored {
        case saved, keptAside
    }

    /// The only way edits reach the disk: in place of `last` while the vault is still that, and
    /// otherwise in a file of their own beside it.
    private func store(_ sealed: VaultFile, replacing last: VaultFile) throws -> Stored {
        try VaultFile.withFolderLocked(directory) {
            if try !changedOnDisk(since: last) {
                do {
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        backUpOnce(recipient: last.recipient)
                        try sealed.write(to: fileURL)
                    } else {
                        try sealed.writeNew(to: fileURL)
                    }
                    backedUp = true
                    return .saved
                } catch VaultError.vaultExists {
                    // It appeared just now, from something that doesn't take the lock.
                } catch {
                    // Written, and only then failing (setting permissions, say), is still written:
                    // taken for a failure, the next save would see its own file as someone else's.
                    guard (try? VaultFile.read(from: fileURL)) == sealed else { throw error }
                    backedUp = true
                    return .saved
                }
            }
            // The code keeps two copies that get here in the same second apart.
            let name = "vault-unsaved-\(Self.stamp(Date()))-\(UUID().uuidString.prefix(4)).keys"
            try sealed.writeNew(to: directory.appendingPathComponent(name))
            filesKeptAside.append(name)
            let names = filesKeptAside.joined(separator: ", ")
            keptAside = localized("O cofre mudou no disco, então as alterações que não tinham sido salvas ficaram em \(names), na mesma pasta.")
            return .keptAside
        }
    }

    /// Whether the vault is no longer `saved`. A file that can't be read is an error, not a
    /// change: the save is then tried again.
    private func changedOnDisk(since saved: VaultFile) throws -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return false }
        do {
            return try VaultFile.read(from: fileURL) != saved
        } catch VaultError.notAVault {
            return true
        }
    }

    private func keepSavingAgain() {
        savingAgain?.cancel()
        savingAgain = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                // Not under the Touch ID prompt: unlocking is about to open these same edits.
                if !isUnlocking { saveUnsaved() }
            }
        }
    }

    private func forgetUnsaved() {
        unsaved = nil
        savingAgain?.cancel()
        savingAgain = nil
    }

    /// Before the first save after unlocking, the vault as it was is copied to Backups, so a
    /// project deleted by mistake can still be recovered. The copies are encrypted like the vault.
    /// It is tried again until a copy is made or a save replaces what there was to copy. Only
    /// copies of the vault with this `recipient` make room for it: another vault's are all it has.
    private func backUpOnce(recipient: Data) {
        guard !backedUp else { return }
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: backupsURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let copy = backupsURL.appendingPathComponent("vault-\(Self.stamp(Date())).keys")
            if !manager.fileExists(atPath: copy.path) {
                try manager.copyItem(at: fileURL, to: copy)
            }
            backedUp = true
            let copies = try manager.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "keys" && (try? VaultFile.read(from: $0))?.recipient == recipient }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in copies.dropFirst(Self.backupCount) {
                try? manager.removeItem(at: old)
            }
        } catch {
            // A missing backup must not stop the save itself.
        }
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    nonisolated static func encode(_ contents: VaultContents) throws -> Data {
        // Dates stay in the default numeric form: exact to the fraction of a second, and nobody
        // reads this JSON without decrypting it first.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(contents)
    }

    nonisolated static func decode(_ data: Data) throws -> VaultContents {
        do {
            return try JSONDecoder().decode(VaultContents.self, from: data)
        } catch {
            throw VaultError.damaged
        }
    }

    // MARK: Projects

    /// A new project, at the top level or inside `parent`, opened on its context.
    @discardableResult
    func addProject(inside parent: Project.ID? = nil) -> Project.ID {
        var project = Project(name: parent == nil ? localized("Novo projeto") : localized("Novo subprojeto"))
        project.parentID = parent
        projects.append(project)
        selection = project.id
        section = .all
        return project.id
    }

    /// Archives the project with its subprojects, or brings them all back.
    func setArchived(_ id: Project.ID, _ archived: Bool) {
        let now = Date()
        let affected = ProjectTree.descendantIDs(of: id, in: projects).union([id])
        projects = ProjectTree.settingArchived(id, at: archived ? now : nil, in: projects).map { project in
            guard affected.contains(project.id) else { return project }
            var project = project
            project.updatedAt = now
            return project
        }
    }

    /// Deletes an archived project for good, with its subprojects (archived along with it).
    func deleteWithSubprojects(_ id: Project.ID) {
        let gone = ProjectTree.descendantIDs(of: id, in: projects).union([id])
        projects = ProjectTree.removingWithSubprojects(id, from: projects)
        if let selection, gone.contains(selection) { self.selection = nil }
    }

    /// Deletes the project; its subprojects move up one level instead of going with it.
    func deleteProject(_ id: Project.ID) {
        projects = ProjectTree.removing(id, from: projects)
        if selection == id { selection = nil }
    }

    /// Moves an access to another project in a single change, so no save catches it in both or in neither.
    func moveCredential(_ id: Credential.ID, from source: Project.ID, to destination: Project.ID) {
        projects = projects.movingCredential(id, from: source, to: destination, at: Date())
    }

    func project(_ id: Project.ID?) -> Project? {
        projects.first { $0.id == id }
    }

    /// A binding to the project with `id` that also stamps when it was last changed.
    func binding(for id: Project.ID) -> Binding<Project>? {
        guard let current = project(id) else { return nil }
        return Binding(
            get: { [weak self] in self?.project(id) ?? current },
            set: { [weak self] new in
                guard let self, let index = projects.firstIndex(where: { $0.id == id }), projects[index] != new else { return }
                var new = new
                new.updatedAt = Date()
                projects[index] = new
            }
        )
    }
}

/// Locks the vault when its unlock runs out, after a while without using the Mac (if the person
/// asked for that), and when the Mac sleeps or its screen locks.
@MainActor
final class AutoLock {
    private var timer: Timer?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    /// Whether to lock `now`: the unlock ran out at `locksAt`, or the Mac has been idle for
    /// `idleSeconds`, longer than `idleMinutes` (0 never locks for being idle).
    nonisolated static func shouldLock(now: Date, locksAt: Date?, idleSeconds: Double, idleMinutes: Int) -> Bool {
        if let locksAt, now >= locksAt { return true }
        return idleMinutes > 0 && idleSeconds >= Double(idleMinutes * 60)
    }

    func start(locksAt: @escaping @MainActor @Sendable () -> Date?, lock: @escaping @MainActor @Sendable () -> Void) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            Task { @MainActor in
                // Seconds since the last keyboard, mouse or trackpad event anywhere on the Mac.
                let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
                if Self.shouldLock(now: Date(), locksAt: locksAt(), idleSeconds: idle, idleMinutes: Preferences.lockMinutes) { lock() }
            }
        }
        let onSleep: @Sendable (Notification) -> Void = { _ in
            Task { @MainActor in
                if Preferences.lockOnSleep { lock() }
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main, using: onSleep)))
        }
        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main, using: onSleep)))
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers = []
    }
}
