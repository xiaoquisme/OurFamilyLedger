import XCTest
@testable import OurFamilyLedger

/// Tests for KeychainService using MockKeychainService
final class KeychainServiceTests: XCTestCase {

    var sut: MockKeychainService!

    override func setUp() {
        super.setUp()
        sut = MockKeychainService()
    }

    override func tearDown() {
        sut.reset()
        sut = nil
        super.tearDown()
    }

    // MARK: - Save API Key Tests

    func testSaveAPIKey_storesKeyForProvider() throws {
        // Given
        let apiKey = "test-api-key-123"
        let provider = AIProvider.openai

        // When
        try sut.saveAPIKey(apiKey, for: provider)

        // Then
        XCTAssertEqual(sut.storedAPIKeys[provider], apiKey)
        XCTAssertEqual(sut.saveAPIKeyCallCount, 1)
    }

    func testSaveAPIKey_overwritesExistingKey() throws {
        // Given
        let oldKey = "old-key"
        let newKey = "new-key"
        let provider = AIProvider.openai
        try sut.saveAPIKey(oldKey, for: provider)

        // When
        try sut.saveAPIKey(newKey, for: provider)

        // Then
        XCTAssertEqual(sut.storedAPIKeys[provider], newKey)
        XCTAssertEqual(sut.saveAPIKeyCallCount, 2)
    }

    func testSaveAPIKey_storesMultipleProviders() throws {
        // Given
        let openaiKey = "openai-key"
        let claudeKey = "claude-key"

        // When
        try sut.saveAPIKey(openaiKey, for: .openai)
        try sut.saveAPIKey(claudeKey, for: .claude)

        // Then
        XCTAssertEqual(sut.storedAPIKeys[.openai], openaiKey)
        XCTAssertEqual(sut.storedAPIKeys[.claude], claudeKey)
        XCTAssertEqual(sut.storedAPIKeys.count, 2)
    }

    func testSaveAPIKey_throwsError_whenConfigured() {
        // Given
        sut.shouldThrowError = KeychainError.unexpectedStatus(-1)

        // When/Then
        XCTAssertThrowsError(try sut.saveAPIKey("key", for: .openai)) { error in
            XCTAssertTrue(error is KeychainError)
        }
    }

    // MARK: - Get API Key Tests

    func testGetAPIKey_returnsStoredKey() throws {
        // Given
        let apiKey = "stored-key"
        sut.storedAPIKeys[.openai] = apiKey

        // When
        let result = try sut.getAPIKey(for: .openai)

        // Then
        XCTAssertEqual(result, apiKey)
        XCTAssertEqual(sut.getAPIKeyCallCount, 1)
    }

    func testGetAPIKey_returnsNil_whenNoKeyStored() throws {
        // When
        let result = try sut.getAPIKey(for: .openai)

        // Then
        XCTAssertNil(result)
    }

    func testGetAPIKey_returnsCorrectKeyForProvider() throws {
        // Given
        sut.storedAPIKeys[.openai] = "openai-key"
        sut.storedAPIKeys[.claude] = "claude-key"

        // When
        let openaiResult = try sut.getAPIKey(for: .openai)
        let claudeResult = try sut.getAPIKey(for: .claude)

        // Then
        XCTAssertEqual(openaiResult, "openai-key")
        XCTAssertEqual(claudeResult, "claude-key")
    }

    func testGetAPIKey_throwsError_whenConfigured() {
        // Given
        sut.shouldThrowError = KeychainError.dataConversionError

        // When/Then
        XCTAssertThrowsError(try sut.getAPIKey(for: .openai))
    }

    // MARK: - Delete API Key Tests

    func testDeleteAPIKey_removesKey() throws {
        // Given
        sut.storedAPIKeys[.openai] = "key-to-delete"

        // When
        try sut.deleteAPIKey(for: .openai)

        // Then
        XCTAssertNil(sut.storedAPIKeys[.openai])
        XCTAssertEqual(sut.deleteAPIKeyCallCount, 1)
    }

    func testDeleteAPIKey_doesNotAffectOtherProviders() throws {
        // Given
        sut.storedAPIKeys[.openai] = "openai-key"
        sut.storedAPIKeys[.claude] = "claude-key"

        // When
        try sut.deleteAPIKey(for: .openai)

        // Then
        XCTAssertNil(sut.storedAPIKeys[.openai])
        XCTAssertEqual(sut.storedAPIKeys[.claude], "claude-key")
    }

    func testDeleteAPIKey_throwsError_whenConfigured() {
        // Given
        sut.shouldThrowError = KeychainError.itemNotFound

        // When/Then
        XCTAssertThrowsError(try sut.deleteAPIKey(for: .openai))
    }

    // MARK: - Custom Endpoint Tests

    func testSaveCustomEndpoint_storesEndpoint() throws {
        // Given
        let endpoint = "https://custom.api.com/v1"

        // When
        try sut.saveCustomEndpoint(endpoint)

        // Then
        XCTAssertEqual(sut.storedCustomEndpoint, endpoint)
    }

    func testGetCustomEndpoint_returnsStoredEndpoint() throws {
        // Given
        let endpoint = "https://custom.api.com/v1"
        sut.storedCustomEndpoint = endpoint

        // When
        let result = try sut.getCustomEndpoint()

        // Then
        XCTAssertEqual(result, endpoint)
    }

    func testGetCustomEndpoint_returnsNil_whenNoEndpointStored() throws {
        // When
        let result = try sut.getCustomEndpoint()

        // Then
        XCTAssertNil(result)
    }

    // MARK: - Clear All Tests

    func testClearAll_removesAllData() throws {
        // Given
        sut.storedAPIKeys[.openai] = "openai-key"
        sut.storedAPIKeys[.claude] = "claude-key"
        sut.storedCustomEndpoint = "https://custom.api.com"

        // When
        try sut.clearAll()

        // Then
        XCTAssertTrue(sut.storedAPIKeys.isEmpty)
        XCTAssertNil(sut.storedCustomEndpoint)
    }

    func testClearAll_throwsError_whenConfigured() {
        // Given
        sut.shouldThrowError = KeychainError.unexpectedStatus(-1)

        // When/Then
        XCTAssertThrowsError(try sut.clearAll())
    }

    // MARK: - Round Trip Tests

    func testRoundTrip_saveAndRetrieve() throws {
        // Given
        let apiKey = "round-trip-key"
        let provider = AIProvider.openai

        // When
        try sut.saveAPIKey(apiKey, for: provider)
        let retrieved = try sut.getAPIKey(for: provider)

        // Then
        XCTAssertEqual(retrieved, apiKey)
    }

    func testRoundTrip_saveDeleteRetrieve() throws {
        // Given
        let apiKey = "temporary-key"
        let provider = AIProvider.openai

        // When
        try sut.saveAPIKey(apiKey, for: provider)
        try sut.deleteAPIKey(for: provider)
        let retrieved = try sut.getAPIKey(for: provider)

        // Then
        XCTAssertNil(retrieved)
    }

    // MARK: - Reset Tests

    func testReset_clearsAllState() throws {
        // Given
        try sut.saveAPIKey("key", for: .openai)
        try sut.saveCustomEndpoint("endpoint")
        _ = try sut.getAPIKey(for: .openai)
        try sut.deleteAPIKey(for: .openai)

        // When
        sut.reset()

        // Then
        XCTAssertTrue(sut.storedAPIKeys.isEmpty)
        XCTAssertNil(sut.storedCustomEndpoint)
        XCTAssertEqual(sut.saveAPIKeyCallCount, 0)
        XCTAssertEqual(sut.getAPIKeyCallCount, 0)
        XCTAssertEqual(sut.deleteAPIKeyCallCount, 0)
        XCTAssertNil(sut.shouldThrowError)
    }
}

// MARK: - KeychainError Tests

final class KeychainErrorTests: XCTestCase {

    func testDuplicateItem_errorDescription() {
        let error = KeychainError.duplicateItem
        XCTAssertEqual(error.errorDescription, "该项已存在")
    }

    func testItemNotFound_errorDescription() {
        let error = KeychainError.itemNotFound
        XCTAssertEqual(error.errorDescription, "未找到该项")
    }

    func testUnexpectedStatus_errorDescription() {
        let error = KeychainError.unexpectedStatus(-25300)
        XCTAssertEqual(error.errorDescription, "Keychain 错误: -25300")
    }

    func testDataConversionError_errorDescription() {
        let error = KeychainError.dataConversionError
        XCTAssertEqual(error.errorDescription, "数据转换失败")
    }
}
