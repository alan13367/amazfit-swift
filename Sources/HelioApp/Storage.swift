import Foundation
import Security
import HelioCore

struct KeychainStore {
    private static let service = "dev.helio.mac.zepp-session"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "zepp"]
    }

    static func load() throws -> ZeppCredentials? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw StorageError.keychain(status) }
        let decoded = try JSONDecoder().decode(ZeppCredentials.self, from: data)
        return try ZeppCredentials(userID: decoded.userID, token: decoded.token, region: decoded.region)
    }

    static func save(_ credentials: ZeppCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let attributes = [kSecValueData as String: data] as [String: Any]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw StorageError.keychain(added) }
        } else if status != errSecSuccess { throw StorageError.keychain(status) }
    }

    static func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StorageError.keychain(status) }
    }
}

enum StorageError: LocalizedError {
    case keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .keychain(let status): "macOS Keychain could not access the Zepp session, error \(status). No token was written to a plain-text file."
        }
    }
}

actor SnapshotCache {
    private struct Envelope: Codable {
        let userID: String
        let snapshot: CloudSnapshot
    }
    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Helio", isDirectory: true)
    }
    private var file: URL { directory.appendingPathComponent("snapshot.json") }

    func load(for credentials: ZeppCredentials) throws -> CloudSnapshot? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: file))
        guard envelope.userID == credentials.userID, envelope.snapshot.region == credentials.region else { return nil }
        return envelope.snapshot
    }

    func save(_ snapshot: CloudSnapshot, for credentials: ZeppCredentials) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(Envelope(userID: credentials.userID, snapshot: snapshot))
        try data.write(to: file, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        var url = file
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
