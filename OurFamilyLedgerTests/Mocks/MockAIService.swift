import Foundation
import UIKit
@testable import OurFamilyLedger

/// Mock AI Service for testing
final class MockAIService: AIServiceProtocol {
    var parseTransactionResult: [TransactionDraft] = []
    var parseTransactionError: Error?
    var parseTransactionCallCount = 0
    var lastParseText: String?
    var lastParseImage: UIImage?
    var testConnectionResult = true
    var fetchModelsResult: [AIModel] = []

    func parseTransaction(from text: String) async throws -> [TransactionDraft] {
        parseTransactionCallCount += 1
        lastParseText = text
        if let error = parseTransactionError { throw error }
        return parseTransactionResult
    }

    func parseTransaction(from image: UIImage, ocrText: String?) async throws -> [TransactionDraft] {
        parseTransactionCallCount += 1
        lastParseImage = image
        lastParseText = ocrText
        if let error = parseTransactionError { throw error }
        return parseTransactionResult
    }

    func testConnection() async throws -> Bool {
        return testConnectionResult
    }

    func fetchModels() async throws -> [AIModel] {
        return fetchModelsResult
    }

    // MARK: - Test Helpers

    func reset() {
        parseTransactionResult = []
        parseTransactionError = nil
        parseTransactionCallCount = 0
        lastParseText = nil
        lastParseImage = nil
        testConnectionResult = true
        fetchModelsResult = []
    }
}
