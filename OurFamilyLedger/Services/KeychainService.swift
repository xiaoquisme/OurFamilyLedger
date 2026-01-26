import Foundation
import Security

/// Keychain 服务错误
enum KeychainError: LocalizedError {
    case duplicateItem
    case itemNotFound
    case unexpectedStatus(OSStatus)
    case dataConversionError

    var errorDescription: String? {
        switch self {
        case .duplicateItem:
            return "该项已存在"
        case .itemNotFound:
            return "未找到该项"
        case .unexpectedStatus(let status):
            return "Keychain 错误: \(status)"
        case .dataConversionError:
            return "数据转换失败"
        }
    }
}

/// Keychain 服务协议
protocol KeychainServiceProtocol {
    func saveAPIKey(_ key: String, for provider: AIProvider) throws
    func getAPIKey(for provider: AIProvider) throws -> String?
    func deleteAPIKey(for provider: AIProvider) throws
    func saveCustomEndpoint(_ endpoint: String) throws
    func getCustomEndpoint() throws -> String?
    func clearAll() throws
}

/// Keychain 服务
final class KeychainService: KeychainServiceProtocol {
    static var shared: KeychainServiceProtocol = KeychainService()

    private let service = "com.ourfamilyledger.app"

    private init() {}

    // MARK: - API Keys

    /// 保存 API Key
    func saveAPIKey(_ key: String, for provider: AIProvider) throws {
        let account = "apikey.\(provider.rawValue)"
        try save(key, for: account)
    }

    /// 获取 API Key
    func getAPIKey(for provider: AIProvider) throws -> String? {
        let account = "apikey.\(provider.rawValue)"
        return try get(for: account)
    }

    /// 删除 API Key
    func deleteAPIKey(for provider: AIProvider) throws {
        let account = "apikey.\(provider.rawValue)"
        try delete(for: account)
    }

    // MARK: - Custom Endpoint

    /// 保存自定义端点
    func saveCustomEndpoint(_ endpoint: String) throws {
        try save(endpoint, for: "custom.endpoint")
    }

    /// 获取自定义端点
    func getCustomEndpoint() throws -> String? {
        try get(for: "custom.endpoint")
    }

    // MARK: - Generic Operations

    private func save(_ value: String, for account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionError
        }

        // 先尝试删除已存在的项
        try? delete(for: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            if status == errSecDuplicateItem {
                throw KeychainError.duplicateItem
            }
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func get(for account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataConversionError
        }

        return value
    }

    private func delete(for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// 清除所有数据
    func clearAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
