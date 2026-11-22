import CryptoKit
import CryptoTokenKit
import Foundation
import LocalAuthentication
import Security

/// The key that ties a vault to this Mac: a P256 key created inside the Secure Enclave, which
/// never leaves it. Using it takes Touch ID or the Mac's password. The Keychain keeps only the
/// key's handle, which the Secure Enclave encrypted and which is useless on any other Mac.
///
/// That handle is the only way into the vault and its automatic copies, so it is only ever added:
/// each key has an item of its own, and nothing here replaces or deletes one. A vault set aside
/// still finds its key when it is put back.
struct DeviceKey {
    static let defaultService = "com.guilhermekollet.keys"
    /// Where vaults in another folder keep their keys (see `Vault.directory`). One service for
    /// all of them rather than one per path, so such a folder can be moved or renamed.
    static let customFolderService = "com.guilhermekollet.keys.custom-folder"
    /// The single item earlier versions kept. Vaults in the default folder made by them still
    /// open with it; it is read, never written.
    static let originalAccount = "device-key"

    static var isAvailable: Bool { SecureEnclave.isAvailable }

    private let keychain: Keychain
    private let enclave: KeyEnclave
    private let isDefaultFolder: Bool

    /// The keys of the vault in `directory`. The Keychain and the Secure Enclave have no default
    /// here, so a test can't reach the real ones by leaving them out.
    init(directory: URL, defaultDirectory: URL, items: KeychainItems, enclave: KeyEnclave) {
        // However it is spelled, the default folder holds the real vault and needs its keys.
        let folder = directory.resolvingSymlinksInPath().path
        isDefaultFolder = folder.caseInsensitiveCompare(defaultDirectory.resolvingSymlinksInPath().path) == .orderedSame
        keychain = Keychain(service: isDefaultFolder ? Self.defaultService : Self.customFolderService, items: items)
        self.enclave = enclave
    }

    /// The Keychain account of the key with this public half (X9.63).
    static func account(for publicKey: Data) -> String {
        let digest = SHA256.hash(data: publicKey).map { String(format: "%02x", $0) }.joined()
        return "\(originalAccount).\(digest)"
    }

    /// A new device key, saved next to any other. Creating it doesn't ask for Touch ID: only
    /// using its private half does.
    func create() throws -> AgreementKey {
        let (handle, key) = try enclave.makeKey()
        try keychain.add(handle, account: Self.account(for: key.publicKey.x963Representation))
        return key
    }

    /// The handle of the key a vault was sealed for, by its public half (X9.63). It doesn't ask
    /// for Touch ID. Throws `missingDeviceKey` only when there is no such item: one that is
    /// there and can't be read is a `KeychainAccessError`.
    func handle(for recipient: Data) throws -> Data {
        var saved = try keychain.load(account: Self.account(for: recipient))
        if saved == nil, isDefaultFolder {
            saved = try keychain.load(account: Self.originalAccount)
        }
        guard let saved else { throw VaultError.missingDeviceKey }
        guard try enclave.publicKey(of: saved) == recipient else { throw VaultError.otherDeviceKey }
        return saved
    }

    /// The key behind `handle`, once the person confirms with Touch ID or the Mac's password.
    func unlock(_ handle: Data, reason: String) async throws -> AgreementKey {
        try await enclave.unlock(handle, reason: reason)
    }

    /// Whether `error` only means the person dismissed the Touch ID prompt.
    static func isCancellation(_ error: Error) -> Bool {
        guard let error = error as? LAError else { return false }
        return [.userCancel, .appCancel, .systemCancel].contains(error.code)
    }
}

// MARK: Secure Enclave

/// What makes and uses device keys: the Secure Enclave in the app, software keys in the tests.
protocol KeyEnclave {
    func makeKey() throws -> (handle: Data, key: AgreementKey)
    func publicKey(of handle: Data) throws -> Data
    func unlock(_ handle: Data, reason: String) async throws -> AgreementKey
}

struct SystemEnclave: KeyEnclave {
    func makeKey() throws -> (handle: Data, key: AgreementKey) {
        guard SecureEnclave.isAvailable else { throw VaultError.noSecureEnclave }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .userPresence], &error
        ) else {
            throw error!.takeRetainedValue() as Error
        }
        let key = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
        return (key.dataRepresentation, key)
    }

    func publicKey(of handle: Data) throws -> Data {
        do {
            return try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: handle).publicKey.x963Representation
        } catch let error as TKError where error.code == .corruptedData || error.code == .badParameter {
            // Only these say the handle itself is no good. Anything else may pass, and is retried.
            throw VaultError.unusableDeviceKey
        }
    }

    /// The authentication context comes along with the key, so the Secure Enclave doesn't ask
    /// again when the vault key is unwrapped.
    func unlock(_ handle: Data, reason: String) async throws -> AgreementKey {
        let context = LAContext()
        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        return try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: handle, authenticationContext: context)
    }
}

// MARK: Keychain

/// The two Keychain calls Keys makes, replaced in the tests. There is deliberately no way to
/// update or delete an item.
protocol KeychainItems {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: Any?)
    func add(_ item: [String: Any]) -> OSStatus
}

struct SystemKeychainItems: KeychainItems {
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: Any?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }

    func add(_ item: [String: Any]) -> OSStatus {
        SecItemAdd(item as CFDictionary, nil)
    }
}

/// The Keychain didn't let Keys read a key. It says nothing about the key being lost, so it is
/// not a `VaultError`: those can lead to starting a new vault, and this is only to be retried.
struct KeychainAccessError: LocalizedError, Equatable {
    let status: OSStatus

    var errorDescription: String? {
        let reason = SecCopyErrorMessageString(status, nil) as String? ?? String(status)
        return localized("O Chaves não conseguiu ler a chave do cofre no Keychain. Nada foi apagado: desbloqueie o Keychain ou permita o acesso e tente de novo. (\(reason))")
    }
}

/// The handles under one service in the user's login Keychain.
private struct Keychain {
    let service: String
    let items: KeychainItems

    private func item(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// The item's data, or nil when there is no item.
    func load(account: String) throws -> Data? {
        // Looked up by its attributes first, which takes no permission: only that can say an item
        // is missing. Whatever goes wrong reading the data of one that is there is a failed access.
        var query = item(account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnAttributes as String] = true
        let found = items.copyMatching(query).status
        if found == errSecItemNotFound { return nil }
        guard found == errSecSuccess else { throw KeychainAccessError(status: found) }

        query[kSecReturnAttributes as String] = nil
        query[kSecReturnData as String] = true
        let (status, result) = items.copyMatching(query)
        guard status == errSecSuccess else { throw KeychainAccessError(status: status) }
        guard let data = result as? Data else { throw KeychainAccessError(status: errSecDecode) }
        return data
    }

    func add(_ data: Data, account: String) throws {
        var entry = item(account)
        entry[kSecValueData as String] = data
        entry[kSecAttrLabel as String] = "Keys"
        entry[kSecAttrDescription as String] = "Keys vault key (Secure Enclave)"
        let status = items.add(entry)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
