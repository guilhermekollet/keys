// Test helpers that need Foundation or CryptoKit live here, in a file that does not import
// Testing: with only the Command Line Tools installed (no Xcode), importing Testing next to
// Foundation fails because the `_Testing_Foundation` overlay is missing. Test files import just
// Testing and Keys and talk to these helpers through plain values.
import AppKit
import CryptoKit
import Foundation
import LocalAuthentication
import Security
@testable import Keys

// MARK: Vault file

/// Ways to break a vault file, to check that each one is caught.
enum Tampering: String, CaseIterable {
    case none
    case contentsByte
    case wrappedKeyByte
    case ephemeralFromAnotherVault
    case contentsFromAnotherVault
    case otherDeviceKey
    case newerVersion
    case otherFormat
}

/// Creates a vault for a software device key, tampers with it and tries to open it: "opened"
/// with the original text, or the error it fails with.
func openVault(after tampering: Tampering) -> String {
    let deviceKey = P256.KeyAgreement.PrivateKey()
    let secret = Data("SUPABASE_SERVICE_ROLE_KEY=abc".utf8)
    do {
        var (file, _) = try VaultFile.create(secret, for: deviceKey)
        let (other, _) = try VaultFile.create(secret, for: deviceKey)
        var opener: AgreementKey = deviceKey
        switch tampering {
        case .none: break
        case .contentsByte: file.contents[file.contents.count - 20] ^= 1
        case .wrappedKeyByte: file.wrappedKey[14] ^= 1
        case .ephemeralFromAnotherVault: file.ephemeral = other.ephemeral
        case .contentsFromAnotherVault: file.contents = other.contents
        case .otherDeviceKey: opener = P256.KeyAgreement.PrivateKey()
        case .newerVersion: file.version = VaultFile.currentVersion + 1
        case .otherFormat: file.format = "something-else"
        }
        let key = try file.unwrapKey(with: opener)
        let opened = try file.open(with: key)
        return opened == secret ? "opened" : "wrong contents"
    } catch let error as VaultError {
        return "\(error)"
    } catch {
        return "unexpected: \(error)"
    }
}

/// Saving again keeps the wrapped key and changes only the contents, which then open with the
/// same device key.
func resealingKeepsTheKey() -> Bool {
    let deviceKey = P256.KeyAgreement.PrivateKey()
    guard let (file, key) = try? VaultFile.create(Data("first".utf8), for: deviceKey),
          let saved = try? file.resealing(Data("second".utf8), with: key),
          let reopened = try? saved.unwrapKey(with: deviceKey),
          let contents = try? saved.open(with: reopened)
    else { return false }
    return saved.wrappedKey == file.wrappedKey && saved.contents != file.contents && contents == Data("second".utf8)
}

/// Two seals of the same contents differ (fresh nonces), so the file reveals nothing about edits.
func sealsDiffer() -> Bool {
    let deviceKey = P256.KeyAgreement.PrivateKey()
    guard let (file, key) = try? VaultFile.create(Data("same".utf8), for: deviceKey),
          let first = try? file.resealing(Data("same".utf8), with: key),
          let second = try? file.resealing(Data("same".utf8), with: key)
    else { return false }
    return first.contents != second.contents
}

/// Writes a vault to a temporary folder and reads it back: whether it is the same, and the file's
/// permissions in octal ("600").
func vaultOnDisk() -> (sameAfterReading: Bool, permissions: String, plaintextVisible: Bool) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("keys-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("vault.keys")
    do {
        let (file, _) = try VaultFile.create(try Vault.encode(VaultContents(projects: SampleVault.projects)), for: P256.KeyAgreement.PrivateKey())
        try file.write(to: url)
        let read = try VaultFile.read(from: url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = String((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0, radix: 8)
        let raw = try String(contentsOf: url, encoding: .utf8)
        return (read == file, permissions, raw.contains("Loja Aurora") || raw.contains("sample-password"))
    } catch {
        return (false, "", true)
    }
}

/// A file that isn't JSON at all is reported as not being a vault.
func readingGarbage() -> String {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("keys-garbage-\(UUID().uuidString).keys")
    defer { try? FileManager.default.removeItem(at: url) }
    try? Data("not a vault".utf8).write(to: url)
    do {
        _ = try VaultFile.read(from: url)
        return "read"
    } catch {
        return "\(error)"
    }
}

// MARK: Contents

/// The sample vault survives encoding and decoding unchanged, dates included.
func sampleRoundTrips() -> Bool {
    let projects = SampleVault.projects
    guard let data = try? Vault.encode(VaultContents(projects: projects)),
          let decoded = try? Vault.decode(data)
    else { return false }
    return decoded.projects == projects
}

/// Decodes `json` as vault contents and describes the first project: name, status, symbol and
/// how many environments and accesses it has.
func firstProjectDecoded(from json: String) -> String {
    guard let contents = try? Vault.decode(Data(json.utf8)) else { return "failed" }
    guard let project = contents.projects.first else { return "no projects" }
    return "\(project.name)|\(project.isArchived ? "archived" : "active")|\(project.symbol)|\(project.environments.count)|\(project.credentials.count)"
}

// MARK: Environment variables

/// Merges `file` into a set holding `existing`, and returns the counts and the result as
/// "KEY=value" lines, with "(secret)" after secret ones.
func merge(_ file: String, into existing: [(String, String)]) -> (added: Int, updated: Int, lines: [String]) {
    var environment = EnvironmentSet(name: "development", variables: existing.map { Variable(key: $0.0, value: $0.1) })
    let result = environment.merge(DotEnv.parse(file))
    let lines = environment.variables.map { "\($0.key)=\($0.value)\($0.isSecret ? " (secret)" : "")" }
    return (result.added, result.updated, lines)
}

// MARK: Search

/// The titles (access names and variable keys) the menu bar search finds in the sample vault.
func quickMatchTitles(_ query: String) -> [String] {
    Search.quickMatches(in: SampleVault.projects, query: query).map { match in
        switch match.item {
        case .credential(let credential): credential.displayTitle
        case .variable(let variable, let environment): "\(variable.key)@\(environment)"
        }
    }
}

/// The sample projects whose name matches `query` in the sidebar search.
func projectsMatching(_ query: String) -> [String] {
    SampleVault.projects.filter { $0.matches(query) }.map(\.name)
}

// MARK: Translations

private let sources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/Keys")

/// The interface's translation table for `language` ("en", "es"), read from the sources.
func translationTable(_ language: String) -> [String: String] {
    let url = sources.appendingPathComponent("Resources/\(language).lproj/Localizable.strings")
    return NSDictionary(contentsOf: url) as? [String: String] ?? [:]
}

/// The format specifiers in `text`, in order (`%@`, `%lld`, `%%`): a translation must keep its key's.
func formatSpecifiers(_ text: String) -> [String] {
    let pattern = try! NSRegularExpression(pattern: "%(%|@|l{0,2}[dfu])")
    return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        .map { String(text[Range($0.range, in: text)!]) }
}

/// The key of every `localized("…")` in Sources/Keys, the way `String.LocalizationValue` builds
/// it, except that interpolations become `%@` whatever their type (the source doesn't say).
func localizedKeysInSources() -> [String] {
    let files = (try? FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)) ?? []
    var keys: [String] = []
    for file in files where file.pathExtension == "swift" {
        let text = Array((try? String(contentsOf: file, encoding: .utf8)) ?? "")
        let opening = Array("localized(\"")
        var index = 0
        while index + opening.count <= text.count {
            guard Array(text[index..<index + opening.count]) == opening else {
                index += 1
                continue
            }
            index += opening.count
            var key = ""
            while text[index] != "\"" {
                if text[index] == "\\", text[index + 1] == "(" {
                    // Skips the interpolated expression, which may have parentheses of its own.
                    var depth = 1
                    index += 2
                    while depth > 0 {
                        if text[index] == "(" { depth += 1 }
                        if text[index] == ")" { depth -= 1 }
                        index += 1
                    }
                    key += "%@"
                } else if text[index] == "\\" {
                    key += String(text[index...index + 1])
                    index += 2
                } else {
                    key += text[index] == "%" ? "%%" : String(text[index])
                    index += 1
                }
            }
            keys.append(key)
        }
    }
    return keys
}

/// `key` with every specifier but `%%` written as `%@`, to compare with `localizedKeysInSources`.
func normalizedKey(_ key: String) -> String {
    key.replacingOccurrences(of: "%l{0,2}[dfu]", with: "%@", options: .regularExpression)
}

// MARK: Menu bar and locking

/// The titles the menu bar lists inside the sample project called `projectName`, as in
/// `quickMatchTitles`.
func projectItemTitles(_ projectName: String, query: String) -> [String] {
    let projects = SampleVault.projects
    guard let project = projects.first(where: { $0.name == projectName }) else { return ["no such project"] }
    return Search.items(in: project, among: projects, query: query).map { match in
        switch match.item {
        case .credential(let credential): credential.displayTitle
        case .variable(let variable, let environment): "\(variable.key)@\(environment)"
        }
    }
}

/// Whether the vault locks `minutesSinceUnlock` after Touch ID, with an unlock that lasts
/// `unlockMinutes`, the Mac idle for `idleMinutes` and the idle lock set to `idleLock` minutes.
func locks(minutesSinceUnlock: Double, unlockMinutes: Int, idleMinutes: Double = 0, idleLock: Int = 0) -> Bool {
    let unlockedAt = Date(timeIntervalSinceReferenceDate: 0)
    return AutoLock.shouldLock(
        now: unlockedAt.addingTimeInterval(minutesSinceUnlock * 60),
        locksAt: unlockedAt.addingTimeInterval(TimeInterval(unlockMinutes * 60)),
        idleSeconds: idleMinutes * 60,
        idleMinutes: idleLock
    )
}

// MARK: Projects inside projects

/// A small tree, by name: "Grupo" holds "Loja" and "API", "Loja" holds "Checkout", and "Site"
/// stands alone. `loop` also makes "A" and "B" each other's parent.
private func tree(loop: Bool = false) -> [Project] {
    var group = Project(name: "Grupo")
    var shop = Project(name: "Loja")
    var api = Project(name: "API")
    var checkout = Project(name: "Checkout")
    let site = Project(name: "Site")
    shop.parentID = group.id
    api.parentID = group.id
    checkout.parentID = shop.id
    group.parentID = nil
    var projects = [checkout, site, api, shop, group]
    if loop {
        var a = Project(name: "A")
        var b = Project(name: "B")
        a.parentID = b.id
        b.parentID = a.id
        projects += [a, b]
    }
    return projects
}

private func names(_ projects: [Project]) -> [String] { projects.map(\.name) }

/// The names directly inside `name` ("" for the top level).
func childrenNames(of name: String, loop: Bool = false) -> [String] {
    let projects = tree(loop: loop)
    let parent = projects.first { $0.name == name }?.id
    return names(ProjectTree.children(of: name.isEmpty ? nil : parent, in: projects))
}

/// The path shown above `name`, and the places it could be moved to.
func treeFacts(_ name: String) -> (path: String, parents: [String]) {
    let projects = tree()
    let project = projects.first { $0.name == name }!
    return (ProjectTree.path(of: project, in: projects), names(ProjectTree.possibleParents(for: project.id, in: projects)))
}

/// After deleting `name`, each remaining project with the name of its parent ("-" at the top).
func parentsAfterDeleting(_ name: String) -> [String] {
    let projects = tree()
    let id = projects.first { $0.name == name }!.id
    let remaining = ProjectTree.removing(id, from: projects)
    return remaining.map { project in "\(project.name)<\(remaining.first { $0.id == project.parentID }?.name ?? "-")" }.sorted()
}

/// Decodes a project saved before subprojects existed: whether it comes back at the top level.
func oldProjectHasNoParent() -> Bool {
    guard let contents = try? Vault.decode(Data(#"{"projects":[{"name":"Old"}]}"#.utf8)) else { return false }
    return contents.projects.first?.parentID == nil
}

// MARK: Moving accesses

private func minute(_ value: Int) -> Date { Date(timeIntervalSinceReferenceDate: Double(value) * 60) }

/// The tree above, unchanged since minute 0, with two accesses in "Loja": "Banco" and "Painel".
private func treeWithAccesses() -> [Project] {
    tree().map { project in
        var project = project
        project.updatedAt = minute(0)
        if project.name == "Loja" {
            project.credentials = [
                Credential(kind: .database, title: "Banco", url: "postgres://db", username: "admin", password: "old", notes: "note", symbol: "star", updatedAt: minute(0)),
                Credential(title: "Painel", updatedAt: minute(0)),
            ]
        }
        return project
    }
}

extension [Project] {
    fileprivate func at(_ name: String) -> Int { firstIndex { $0.name == name }! }

    fileprivate func moving(_ title: String, to destination: String, minute value: Int) -> [Project] {
        let source = first { $0.credentials.contains { $0.title == title } }!
        let id = source.credentials.first { $0.title == title }!.id
        return movingCredential(id, from: source.id, to: self[at(destination)].id, at: minute(value))
    }

    /// Every access as "Project/Title", sorted.
    fileprivate var places: [String] {
        flatMap { project in project.credentials.map { "\(project.name)/\($0.title)" } }.sorted()
    }
}

/// Moves "Banco" from "Loja" to `destination`.
func movingAccess(to destination: String) -> (places: [String], intact: Bool, stamped: [String]) {
    let before = treeWithAccesses()
    let after = before.moving("Banco", to: destination, minute: 10)
    var expected = before[before.at("Loja")].credentials[0]
    expected.movedAt = minute(10)
    let intact = after.flatMap(\.credentials).contains(expected)
    return (after.places, intact, after.filter { $0.updatedAt == minute(10) }.map(\.name).sorted())
}

/// Moves that can't happen: to the same project, an archived one, one that's gone, or of an access that's gone.
func impossibleMovesChangeNothing() -> [Bool] {
    var projects = treeWithAccesses()
    projects[projects.at("Site")].archivedAt = minute(1)
    let shop = projects[projects.at("Loja")]
    let id = shop.credentials[0].id
    let attempts = [
        (id, shop.id), (id, projects[projects.at("Site")].id), (id, UUID()), (UUID(), projects[projects.at("API")].id),
    ]
    return attempts.map { projects.movingCredential($0.0, from: shop.id, to: $0.1, at: minute(10)) == projects }
}

/// The paths offered to an access in `source`, with `archived` out of use.
func accessDestinations(from source: String, archived: String) -> [String] {
    var projects = treeWithAccesses()
    projects[projects.at(archived)].archivedAt = minute(1)
    return projects.credentialDestinations(from: projects[projects.at(source)].id).map(\.path)
}

/// A move survives saving and opening the vault again.
func moveSurvivesSaving() -> Bool {
    let contents = VaultContents(projects: treeWithAccesses().moving("Banco", to: "Checkout", minute: 10))
    guard let data = try? Vault.encode(contents) else { return false }
    return (try? Vault.decode(data)) == contents
}

/// What happened on the other Mac since the two vaults were the same.
enum OtherMac: CaseIterable {
    case nothing, editedSource, editedDestination, changedPassword, movedLater
}

/// "Banco" moves from "Loja" to "API" here at minute 10, and the vaults are merged, either the
/// other Mac's into this one or (`reversed`) this one's into it.
func mergingAfterMove(_ other: OtherMac, reversed: Bool) -> (places: [String], password: String, repeatUpdates: Int) {
    let base = treeWithAccesses()
    let here = base.moving("Banco", to: "API", minute: 10)
    var there = base
    let shop = there.at("Loja"), api = there.at("API")
    switch other {
    case .nothing: break
    case .editedSource:
        there[shop].summary = "edited"
        there[shop].updatedAt = minute(20)
    case .editedDestination:
        there[api].summary = "edited"
        there[api].updatedAt = minute(20)
    case .changedPassword:
        there[shop].credentials[0].password = "new"
        there[shop].credentials[0].updatedAt = minute(5)
        there[shop].updatedAt = minute(5)
    case .movedLater:
        there = there.moving("Banco", to: "Site", minute: 20)
    }
    let (mine, theirs) = reversed ? (there, here) : (here, there)
    let merged = VaultContents(projects: mine).merging(VaultContents(projects: theirs)).contents
    let password = merged.projects.flatMap(\.credentials).first { $0.title == "Banco" }?.password ?? "lost"
    return (merged.projects.places, password, merged.merging(VaultContents(projects: theirs)).updated)
}

// MARK: The app's name by language

/// The interface language a Mac set to `preferences` gets.
func interfaceLanguage(for preferences: [String]) -> String {
    Interface.pickLanguage(from: ["en", "es", "pt-BR"], preferring: preferences)
}

/// The app's name on a Mac set to `preferences`, read from the app's own tables.
func appName(onMacIn preferences: [String]) -> String {
    let language = interfaceLanguage(for: preferences)
    guard let table = Interface.table(for: language) else {
        return "no table for \(language)"
    }
    return String(localized: "Chaves", bundle: table)
}

/// The name Finder, the Dock and the app menu show in `language`.
func finderName(in language: String) -> String {
    let url = sources.appendingPathComponent("Resources/\(language).lproj/InfoPlist.strings")
    let table = NSDictionary(contentsOf: url) as? [String: String] ?? [:]
    return [table["CFBundleName"], table["CFBundleDisplayName"]].map { $0 ?? "-" }.joined(separator: "/")
}

// MARK: Backups

/// Ways to break a backup, to check that each one is refused.
enum BackupTampering: String, CaseIterable {
    case none, sealedByte, fewerIterations, otherSalt, otherDate, otherFormat, newerVersion
}

/// Seals a sample with `password` (few rounds, so the test is fast), tampers with it and opens it
/// with `attempt`: "opened" with the same contents, or the error.
func openBackup(sealedWith password: String, openedWith attempt: String, after tampering: BackupTampering = .none) -> String {
    let secret = Data("PIX_WEBHOOK_SECRET=abc".utf8)
    do {
        var backup = try VaultBackup.seal(secret, password: password, iterations: 2_000)
        switch tampering {
        case .none: break
        case .sealedByte: backup.sealed[backup.sealed.count - 5] ^= 1
        case .fewerIterations: backup.iterations = 1_000
        case .otherSalt: backup.salt[0] ^= 1
        case .otherDate: backup.createdAt = backup.createdAt.addingTimeInterval(60)
        case .otherFormat: backup.format = "something-else"
        case .newerVersion: backup.version = VaultBackup.currentVersion + 1
        }
        return try backup.open(password: attempt) == secret ? "opened" : "wrong contents"
    } catch let error as BackupError {
        return "\(error)"
    } catch {
        return "unexpected: \(error)"
    }
}

/// Writes a backup of the sample vault and reads it back: the same projects, the file's permissions,
/// and whether any name or secret can be read in it.
func backupOnDisk() -> (sameProjects: Bool, permissions: String, plaintextVisible: Bool) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("keys-backup-\(UUID().uuidString).keys-backup")
    defer { try? FileManager.default.removeItem(at: url) }
    let projects = SampleVault.projects
    do {
        try VaultBackup.seal(try Vault.encode(VaultContents(projects: projects)), password: "correct horse battery", iterations: 2_000).write(to: url)
        let read = try VaultBackup.read(from: url)
        let contents = try Vault.decode(try read.open(password: "correct horse battery"))
        let permissions = String((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0, radix: 8)
        let raw = try String(contentsOf: url, encoding: .utf8)
        return (contents.projects == projects, permissions, raw.contains("Loja Aurora") || raw.contains("sample-password"))
    } catch {
        return (false, "", true)
    }
}

/// Merges `backup` into `current` (projects as name and minutes since a fixed date, same id when
/// the name is the same) and returns the counts and the names with their minutes.
func merge(backup: [(String, Int)], into current: [(String, Int)]) -> (added: Int, updated: Int, result: [String]) {
    var ids: [String: UUID] = [:]
    func project(_ entry: (String, Int)) -> Project {
        let id = ids[entry.0] ?? UUID()
        ids[entry.0] = id
        return Project(id: id, name: entry.0, updatedAt: Date(timeIntervalSinceReferenceDate: Double(entry.1) * 60))
    }
    let mine = VaultContents(projects: current.map(project))
    let theirs = VaultContents(projects: backup.map(project))
    let merged = mine.merging(theirs)
    let result = merged.contents.projects.map { "\($0.name)@\(Int($0.updatedAt.timeIntervalSinceReferenceDate / 60))" }
    return (merged.added, merged.updated, result)
}

/// The file name offered when saving a backup made on 2 November 2026.
func suggestedBackupName() -> String {
    var components = DateComponents()
    components.year = 2026
    components.month = 11
    components.day = 2
    components.hour = 12
    return VaultBackup.suggestedFileName(on: Calendar.current.date(from: components)!)
}

// MARK: Archiving

/// Archives (or brings back, with `archived` false) the project called `name` in the tree above,
/// and returns which projects end up archived, and the two sidebar lists' top rows.
func archiving(_ name: String, archived: Bool = true, startingArchived: [String] = []) -> (archived: [String], activeRoots: [String], archivedRoots: [String]) {
    var projects = treeForArchiving()
    let date = Date(timeIntervalSinceReferenceDate: 0)
    for index in projects.indices where startingArchived.contains(projects[index].name) {
        projects[index].archivedAt = date
    }
    let id = projects.first { $0.name == name }!.id
    let result = ProjectTree.settingArchived(id, at: archived ? date : nil, in: projects)
    return (
        result.filter(\.isArchived).map(\.name).sorted(),
        ProjectTree.roots(archived: false, in: result).map(\.name),
        ProjectTree.roots(archived: true, in: result).map(\.name)
    )
}

/// "Grupo" holds "Loja" and "API", "Loja" holds "Checkout", and "Site" stands alone.
private func treeForArchiving() -> [Project] {
    let group = Project(name: "Grupo")
    var shop = Project(name: "Loja")
    var api = Project(name: "API")
    var checkout = Project(name: "Checkout")
    let site = Project(name: "Site")
    shop.parentID = group.id
    api.parentID = group.id
    checkout.parentID = shop.id
    return [group, shop, api, checkout, site]
}

/// The quick search's titles when the sample's "Loja Aurora" is archived: archived results last.
func quickMatchTitlesWithShopArchived(_ query: String) -> [String] {
    var projects = SampleVault.projects
    for index in projects.indices where projects[index].name == "Loja Aurora" {
        projects[index].archivedAt = Date()
    }
    return Search.quickMatches(in: projects, query: query).map { match in
        switch match.item {
        case .credential(let credential): credential.displayTitle
        case .variable(let variable, let environment): "\(variable.key)@\(environment)"
        }
    }
}

/// The color the first project in `json` decodes with.
func firstProjectTint(from json: String) -> String {
    (try? Vault.decode(Data(json.utf8)))?.projects.first?.tint.rawValue ?? "failed"
}

/// The first project's icon style after reading `json` as a vault, or "failed".
func firstProjectIconStyle(from json: String) -> String {
    (try? Vault.decode(Data(json.utf8)))?.projects.first?.iconStyle.rawValue ?? "failed"
}

/// The icon style a project keeps after a trip through the vault file.
func iconStyleAfterSaving(_ style: Project.IconStyle) -> String {
    var project = Project(name: "Styled")
    project.iconStyle = style
    guard let data = try? Vault.encode(VaultContents(projects: [project])) else { return "failed" }
    return (try? Vault.decode(data))?.projects.first?.iconStyle.rawValue ?? "failed"
}

/// Whether every symbol offered for a project exists on this Mac, and how many there are.
func projectSymbolsExist() -> (count: Int, missing: [String]) {
    (Project.symbols.count, Project.symbols.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil })
}

/// Whether every icon offered for an access exists on this Mac, and how many there are.
func credentialSymbolsExist() -> (count: Int, missing: [String]) {
    (Credential.symbols.count, Credential.symbols.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil })
}

/// The icon an access of `kind` shows after a trip through the vault file, with `picked` chosen
/// for it, or with the "symbol" key taken out, as in vaults from before accesses had icons.
func credentialIcon(kind: Credential.Kind, picked: String?, fromOldVault: Bool = false) -> String {
    var project = Project(name: "Icons")
    project.credentials = [Credential(kind: kind, title: "Panel", symbol: picked)]
    guard var data = try? Vault.encode(VaultContents(projects: [project])) else { return "failed" }
    if fromOldVault {
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var projects = json["projects"] as? [[String: Any]],
              var credentials = projects[0]["credentials"] as? [[String: Any]]
        else { return "failed" }
        credentials[0].removeValue(forKey: "symbol")
        projects[0]["credentials"] = credentials
        json["projects"] = projects
        guard let stripped = try? JSONSerialization.data(withJSONObject: json) else { return "failed" }
        data = stripped
    }
    return (try? Vault.decode(data))?.projects.first?.credentials.first?.displaySymbol ?? "failed"
}

/// The names left after deleting `name`, and everything inside it, for good.
func remainingAfterDeletingForGood(_ name: String) -> [String] {
    let projects = treeForArchiving()
    let id = projects.first { $0.name == name }!.id
    return ProjectTree.removingWithSubprojects(id, from: projects).map(\.name).sorted()
}

// MARK: The project's list

/// What the project list's search keeps of the sample's "Loja Aurora": access titles, variable
/// keys (with their environment) and link titles.
func projectListMatches(_ query: String) -> [String] {
    guard let shop = SampleVault.projects.first(where: { $0.name == "Loja Aurora" }) else { return ["no shop"] }
    let credentials = shop.credentials.filter { $0.matches(query) }.map(\.displayTitle)
    let variables = shop.environments.flatMap { environment in
        environment.variables.filter { $0.matches(query) }.map { "\($0.key)@\(environment.name)" }
    }
    let links = shop.links.filter { $0.matches(query) }.map(\.title)
    return credentials + variables + links
}

// MARK: Appearance

/// The appearance Settings show when the defaults hold `value` for it.
func storedAppearance(_ value: String?) -> Preferences.Appearance {
    let defaults = UserDefaults.standard
    let previous = defaults.object(forKey: Preferences.appearanceKey)
    defer { defaults.set(previous, forKey: Preferences.appearanceKey) }
    defaults.set(value, forKey: Preferences.appearanceKey)
    return Preferences.appearance
}

// MARK: Exported .env files

/// Exports `text` as a .env file, into a new file or over one readable by everyone, and returns
/// its permissions and contents afterwards.
func exportedDotEnv(_ text: String, overExisting: Bool) -> (permissions: String, contents: String) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("keys-env-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    do {
        if overExisting {
            try Data("OLD=value-that-is-much-longer-than-the-new-one\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        }
        try DotEnv.write(text, to: url)
        let permissions = String((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0, radix: 8)
        return (permissions, try String(contentsOf: url, encoding: .utf8))
    } catch {
        return ("failed: \(error)", "")
    }
}

/// Whether exporting refuses to write through a symbolic link, leaving its target untouched.
func exportRefusesSymlink() -> (refused: Bool, targetUntouched: Bool) {
    let manager = FileManager.default
    let target = manager.temporaryDirectory.appendingPathComponent("keys-target-\(UUID().uuidString)")
    let link = manager.temporaryDirectory.appendingPathComponent("keys-link-\(UUID().uuidString)")
    defer {
        try? manager.removeItem(at: link)
        try? manager.removeItem(at: target)
    }
    do {
        try Data("KEEP=1\n".utf8).write(to: target)
        try manager.createSymbolicLink(at: link, withDestinationURL: target)
    } catch {
        return (false, false)
    }
    let refused = (try? DotEnv.write("SECRET=1\n", to: link)) == nil
    let untouched = (try? String(contentsOf: target, encoding: .utf8)) == "KEEP=1\n"
    return (refused, untouched)
}

// MARK: Device keys

/// Ways the Keychain can refuse an item that is there.
enum KeychainFailure: CaseIterable {
    case locked, denied, cancelled, noAccess, unreadableData

    var status: OSStatus {
        switch self {
        case .locked: errSecInteractionNotAllowed
        case .denied: errSecAuthFailed
        case .cancelled: errSecUserCanceled
        case .noAccess: errSecMissingEntitlement
        // Found by its attributes, then not found when its data is asked for.
        case .unreadableData: errSecItemNotFound
        }
    }
}

/// A Keychain in memory. Like the real one it refuses a second item with the same service and
/// account, and it notes every item it was asked about.
final class FakeKeychain: KeychainItems {
    private(set) var items: [String: Data] = [:]
    private(set) var asked: [String] = []
    private(set) var added: [String] = []
    /// What looking an item up fails with, data or not.
    var lookupFailure: KeychainFailure?
    /// What reading an item's data fails with, once it was found.
    var readFailure: KeychainFailure?
    var refusesNewItems = false

    private func name(_ query: [String: Any]) -> String {
        let service = query[kSecAttrService as String] as? String ?? "*"
        let account = query[kSecAttrAccount as String] as? String ?? "*"
        return "\(service)/\(account)"
    }

    func put(_ data: Data, service: String, account: String) {
        items["\(service)/\(account)"] = data
    }

    func take(_ name: String) -> Data? { items.removeValue(forKey: name) }

    func putBack(_ data: Data?, as name: String) { items[name] = data }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: Any?) {
        let name = name(query)
        asked.append(name)
        if let lookupFailure { return (lookupFailure.status, nil) }
        guard let data = items[name] else { return (errSecItemNotFound, nil) }
        guard query[kSecReturnData as String] != nil else { return (errSecSuccess, [String: Any]()) }
        if let readFailure { return (readFailure.status, nil) }
        return (errSecSuccess, data)
    }

    func add(_ item: [String: Any]) -> OSStatus {
        let name = name(item)
        if refusesNewItems { return errSecInteractionNotAllowed }
        guard items[name] == nil, let data = item[kSecValueData as String] as? Data else { return errSecDuplicateItem }
        items[name] = data
        added.append(name)
        return errSecSuccess
    }
}

/// Software keys standing in for the Secure Enclave's: no Touch ID, nothing stored.
final class FakeEnclave: KeyEnclave {
    enum Failure { case badHandle, busy, cancelled }
    var failure: Failure?

    func makeKey() throws -> (handle: Data, key: AgreementKey) {
        let key = P256.KeyAgreement.PrivateKey()
        return (key.rawRepresentation, key)
    }

    func publicKey(of handle: Data) throws -> Data {
        if failure == .badHandle { throw VaultError.unusableDeviceKey }
        if failure == .busy { throw NSError(domain: "KeysTests", code: 1) }
        return try P256.KeyAgreement.PrivateKey(rawRepresentation: handle).publicKey.x963Representation
    }

    func unlock(_ handle: Data, reason: String) async throws -> AgreementKey {
        if failure == .cancelled { throw LAError(.userCancel) }
        return try P256.KeyAgreement.PrivateKey(rawRepresentation: handle)
    }
}

/// A Mac made up for a test: its Keychain, its Secure Enclave and vault folders in a temporary
/// place. Nothing in it reaches the real Keychain or the real vault.
@MainActor
final class FakeMac {
    enum Folder: String {
        case standard = "Keys"
        case standardInOtherCase = "KEYS"
        case standardThroughLink = "Link"
        case custom = "keys-dev"
        case otherCustom = "keys-dev-2"
    }

    let keychain = FakeKeychain()
    let enclave = FakeEnclave()
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("keys-mac-\(UUID().uuidString)")

    func url(_ folder: Folder) -> URL { root.appendingPathComponent(folder.rawValue) }

    /// The app launched on `folder`.
    func launch(_ folder: Folder = .standard) -> Vault {
        let deviceKey = DeviceKey(directory: url(folder), defaultDirectory: url(.standard), items: keychain, enclave: enclave)
        return Vault(sample: false, directory: url(folder), deviceKey: deviceKey)
    }

    /// A vault as earlier versions left it: one item, service "com.guilhermekollet.keys" and
    /// account "device-key", written out here so a change to the app's constants fails the tests.
    func installEarlierVersion(holding name: String) throws {
        let key = P256.KeyAgreement.PrivateKey()
        keychain.put(key.rawRepresentation, service: "com.guilhermekollet.keys", account: "device-key")
        let contents = try Vault.encode(VaultContents(projects: [Project(name: name)]))
        try VaultFile.create(contents, for: key).file.write(to: url(.standard).appendingPathComponent("vault.keys"))
    }

    func replaceOriginalKey() {
        keychain.put(P256.KeyAgreement.PrivateKey().rawRepresentation, service: "com.guilhermekollet.keys", account: "device-key")
    }

    func importBackup(holding name: String, into vault: Vault) async throws {
        let file = root.appendingPathComponent("\(UUID().uuidString).keys-backup")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let contents = try Vault.encode(VaultContents(projects: [Project(name: name)]))
        try VaultBackup.seal(contents, password: "correct horse battery", iterations: 2_000).write(to: file)
        _ = try await vault.importBackup(from: file, password: "correct horse battery")
    }

    func linkToStandardFolder() throws {
        try FileManager.default.createSymbolicLink(at: url(.standardThroughLink), withDestinationURL: url(.standard))
    }

    func move(_ folder: Folder, to other: Folder) throws {
        try FileManager.default.moveItem(at: url(folder), to: url(other))
    }

    func files(in folder: Folder = .standard) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url(folder).path)) ?? []).sorted()
    }

    /// Renames the vault set aside back to vault.keys, replacing the one made after it.
    func putBackVaultSetAside() throws {
        let aside = files().first { $0.hasPrefix("vault-unreadable-") } ?? "no vault set aside"
        let current = url(.standard).appendingPathComponent("vault.keys")
        if FileManager.default.fileExists(atPath: current.path) { try FileManager.default.removeItem(at: current) }
        try FileManager.default.moveItem(at: url(.standard).appendingPathComponent(aside), to: current)
    }

    /// While false, nothing can be written in the default folder, as on a full or read-only disk.
    func setWritable(_ writable: Bool) throws {
        try FileManager.default.setAttributes([.posixPermissions: writable ? 0o700 : 0o500], ofItemAtPath: url(.standard).path)
    }

    /// `count` automatic copies of the vault as it is now, from days of `year`, oldest first.
    func addCopies(_ count: Int, year: Int) throws {
        let folder = url(.standard).appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for day in 1...count {
            let copy = folder.appendingPathComponent(String(format: "vault-%04d01%02d-120000.keys", year, day))
            try FileManager.default.copyItem(at: url(.standard).appendingPathComponent("vault.keys"), to: copy)
        }
    }

    /// Another copy of the app, or a restore, puts a different vault file in place.
    func changeVaultOnDisk() throws {
        let key = P256.KeyAgreement.PrivateKey()
        try VaultFile.create(Data("other".utf8), for: key).file.write(to: url(.standard).appendingPathComponent("vault.keys"))
    }

    func vaultBytes() -> [UInt8] {
        [UInt8]((try? Data(contentsOf: url(.standard).appendingPathComponent("vault.keys"))) ?? Data())
    }

    /// Opens `name` in the default folder as the vault, the way the README says to.
    func useAsVault(_ name: String) throws {
        let current = url(.standard).appendingPathComponent("vault.keys")
        if FileManager.default.fileExists(atPath: current.path) { try FileManager.default.removeItem(at: current) }
        try FileManager.default.moveItem(at: url(.standard).appendingPathComponent(name), to: current)
    }

    func useCopyAsVault(_ name: String) throws {
        try useAsVault("Backups/\(name)")
    }

    /// How many of `rounds` races to write the same new vault file had other than one winner,
    /// and the permissions the files ended with.
    func racesWithoutOneWinner(rounds: Int) throws -> (bad: Int, permissions: Set<Int>) {
        let file = try VaultFile.create(Data("new".utf8), for: P256.KeyAgreement.PrivateKey()).file
        var bad = 0
        var permissions = Set<Int>()
        for round in 0..<rounds {
            let target = url(.standard).appendingPathComponent("race-\(round).keys")
            let lock = NSLock()
            var winners = 0
            DispatchQueue.concurrentPerform(iterations: 8) { _ in
                guard (try? file.writeNew(to: target)) != nil else { return }
                lock.lock()
                winners += 1
                lock.unlock()
            }
            if winners != 1 { bad += 1 }
            let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
            permissions.insert((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0)
        }
        return (bad, permissions)
    }

    func setVaultReadable(_ readable: Bool) throws {
        try FileManager.default.setAttributes([.posixPermissions: readable ? 0o600 : 0], ofItemAtPath: url(.standard).appendingPathComponent("vault.keys").path)
    }

    func removeVault() throws {
        try FileManager.default.removeItem(at: url(.standard).appendingPathComponent("vault.keys"))
    }

    /// Makes vault.keys a link to the vault kept in another folder, as a synced vault can be.
    func keepVaultBehindLink() throws {
        try FileManager.default.createDirectory(at: url(.custom), withIntermediateDirectories: true)
        let link = url(.standard).appendingPathComponent("vault.keys")
        let target = url(.custom).appendingPathComponent("vault.keys")
        try FileManager.default.moveItem(at: link, to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    }

    /// Runs `body` while something else holds the default folder's lock.
    func whileFolderIsLocked(_ body: () -> Void) throws {
        try VaultFile.withFolderLocked(url(.standard), body)
    }

    func copies() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url(.standard).appendingPathComponent("Backups").path)) ?? []).sorted()
    }

    func dispose() {
        try? setWritable(true)
        try? FileManager.default.removeItem(at: root)
    }
}

// MARK: The last backup's date

/// What `Preferences.lastBackup` reads after the date is stored as `stored` ("date", "seconds"
/// or "none"), in throwaway defaults, as seconds since 2001 (nil when it finds none).
func lastBackupSeconds(storedAs stored: String) -> Double? {
    let suite = "keys.tests.last-backup.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else { return nil }
    defer { defaults.removePersistentDomain(forName: suite) }
    let when = Date(timeIntervalSinceReferenceDate: 800_000_000)
    switch stored {
    case "date": defaults.set(when, forKey: Preferences.lastBackupKey)
    case "seconds": Preferences.recordBackup(at: when, in: defaults)
    default: break
    }
    return Preferences.lastBackup(in: defaults)?.timeIntervalSinceReferenceDate
}

/// Today at `hour` o'clock, in the Mac's calendar, for the start page's greeting.
func dateAt(hour: Int) -> Date {
    Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
}

// MARK: Recovery codes

/// An access's codes after a trip through the vault file, as "code:used" or "code:unused".
func recoveryCodesAfterSaving() -> [String] {
    var credential = Credential(title: "Mail")
    credential.recoveryCodes = [RecoveryCode(code: "aaaa1-bbbb2", usedAt: Date()), RecoveryCode(code: "cccc3-dddd4")]
    var project = Project(name: "Codes")
    project.credentials = [credential]
    guard let data = try? Vault.encode(VaultContents(projects: [project])),
          let read = try? Vault.decode(data).projects.first?.credentials.first else { return ["failed"] }
    return read.recoveryCodes.map { "\($0.code):\($0.isUsed ? "used" : "unused")" }
}

/// The codes of an access saved before accesses had any.
func recoveryCodesFromOldVault() -> [String] {
    let json = #"{"projects":[{"name":"Old","credentials":[{"title":"Mail","password":"x"}]}]}"#
    return (try? Vault.decode(Data(json.utf8)))?.projects.first?.credentials.first?.recoveryCodes.map(\.code) ?? ["failed"]
}
