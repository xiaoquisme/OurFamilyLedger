import Foundation
@testable import OurFamilyLedger

/// Mock Keychain Service for testing
final class MockKeychainService: KeychainServiceProtocol {
    var storedAPIKeys: [AIProvider: String] = [:]
    var storedCustomEndpoint: String?
    var saveAPIKeyCallCount = 0
    var getAPIKeyCallCount = 0
    var deleteAPIKeyCallCount = 0
    var shouldThrowError: Error?

    func saveAPIKey(_ key: String, for provider: AIProvider) throws {
        if let error = shouldThrowError { throw error }
        saveAPIKeyCallCount += 1
        storedAPIKeys[provider] = key
    }

    func getAPIKey(for provider: AIProvider) throws -> String? {
        if let error = shouldThrowError { throw error }
        getAPIKeyCallCount += 1
        return storedAPIKeys[provider]
    }

    func deleteAPIKey(for provider: AIProvider) throws {
        if let error = shouldThrowError { throw error }
        deleteAPIKeyCallCount += 1
        storedAPIKeys.removeValue(forKey: provider)
    }

    func saveCustomEndpoint(_ endpoint: String) throws {
        if let error = shouldThrowError { throw error }
        storedCustomEndpoint = endpoint
    }

    func getCustomEndpoint() throws -> String? {
        if let error = shouldThrowError { throw error }
        return storedCustomEndpoint
    }

    func clearAll() throws {
        if let error = shouldThrowError { throw error }
        storedAPIKeys.removeAll()
        storedCustomEndpoint = nil
    }

    // MARK: - Test Helpers

    func reset() {
        storedAPIKeys.removeAll()
        storedCustomEndpoint = nil
        saveAPIKeyCallCount = 0
        getAPIKeyCallCount = 0
        deleteAPIKeyCallCount = 0
        shouldThrowError = nil
    }
}
