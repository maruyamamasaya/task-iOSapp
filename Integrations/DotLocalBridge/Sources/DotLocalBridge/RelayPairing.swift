import Foundation
import Security

public enum RelayPairingError: Error, LocalizedError {
    case invalid, keychain, staging
    public var errorDescription: String? {
        switch self {
        case .invalid: "Mac 接続情報を確認できません。"
        case .keychain: "この端末の Keychain を利用できません。端末のロック状態を確認してください。"
        case .staging: "接続情報の安全な保存・受渡しを完了できません。"
        }
    }
}

public struct RelayPairing: Codable, Sendable {
    public let version: Int
    public let endpoint: URL
    public let bridgeID: String
    public let certificateSHA256: String
    private let bearer: String
    public let deviceLabel: String
    public func validate() throws {
        guard version == 1, bridgeID.range(of: "^[a-zA-Z0-9-]{1,80}$", options: .regularExpression) != nil,
              !deviceLabel.isEmpty, bearer.count >= 32 else { throw RelayPairingError.invalid }
        _ = try HTTPSBridgeTransport(base: endpoint, certificateSHA256: certificateSHA256, bearer: bearer)
    }
    public func transport() throws -> HTTPSBridgeTransport {
        try validate()
        return try HTTPSBridgeTransport(base: endpoint, certificateSHA256: certificateSHA256, bearer: bearer)
    }
}

@MainActor public struct KeychainRelayPairing {
    private let service = "com.example.CalendarTaskApp.DotLocalRelay.pairing"
    public init() {}
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "paired-mac", kSecAttrSynchronizable as String: false]
    }
    public func load() throws -> RelayPairing? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = try? JSONDecoder().decode(RelayPairing.self, from: data) else { throw RelayPairingError.keychain }
        try value.validate(); return value
    }
    public func save(_ value: RelayPairing) throws {
        try value.validate()
        let data = try JSONEncoder().encode(value)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            let item = query.merging(attributes) { _, new in new }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw RelayPairingError.keychain }
        } else if result != errSecSuccess { throw RelayPairingError.keychain }
    }
    public func remove() throws {
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw RelayPairingError.keychain }
    }
}

public enum RelayPairingInbox {
    public static var directory: URL { URL.applicationSupportDirectory.appending(path: "DotLocalRelay") }
    public static var file: URL { directory.appending(path: "pairing-inbox.json") }
    public static func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        #endif
        var url = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
    public static func read() throws -> RelayPairing? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path)
        #endif
        var protected = file
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try protected.setResourceValues(values)
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        let data = try handle.read(upToCount: 16_385) ?? Data()
        guard data.count <= 16_384, let value = try? JSONDecoder().decode(RelayPairing.self, from: data) else { throw RelayPairingError.invalid }
        try value.validate(); return value
    }
    @MainActor public static func confirmIntoKeychain() throws {
        guard let value = try read() else { throw RelayPairingError.staging }
        try KeychainRelayPairing().save(value)
        // Read back Keychain before deleting the protected one-time transfer file.
        guard try KeychainRelayPairing().load()?.bridgeID == value.bridgeID else { throw RelayPairingError.keychain }
        do { try FileManager.default.removeItem(at: file) } catch { throw RelayPairingError.staging }
    }
}
