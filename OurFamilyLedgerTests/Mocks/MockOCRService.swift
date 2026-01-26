import Foundation
import UIKit
@testable import OurFamilyLedger

/// Mock OCR Service for testing
final class MockOCRService: OCRServiceProtocol {
    var recognizeTextResult = OCRResult(text: "")
    var recognizeTextError: Error?
    var recognizeTextCallCount = 0
    var lastImage: UIImage?

    func recognizeText(from image: UIImage) async throws -> OCRResult {
        recognizeTextCallCount += 1
        lastImage = image
        if let error = recognizeTextError { throw error }
        return recognizeTextResult
    }

    func recognizeText(from images: [UIImage]) async throws -> [OCRResult] {
        var results: [OCRResult] = []
        for image in images {
            let result = try await recognizeText(from: image)
            results.append(result)
        }
        return results
    }

    // MARK: - Test Helpers

    func reset() {
        recognizeTextResult = OCRResult(text: "")
        recognizeTextError = nil
        recognizeTextCallCount = 0
        lastImage = nil
    }

    func setResult(text: String, confidence: Double = 1.0) {
        recognizeTextResult = OCRResult(text: text, confidence: confidence)
    }
}
