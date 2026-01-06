import Foundation
import UIKit

/// OCR 服务错误
enum OCRError: LocalizedError {
    case noTextFound
    case processingFailed(Error)
    case imageConversionFailed

    var errorDescription: String? {
        switch self {
        case .noTextFound:
            return "未能识别到文字"
        case .processingFailed(let error):
            return "OCR 处理失败: \(error.localizedDescription)"
        case .imageConversionFailed:
            return "图片转换失败"
        }
    }
}

/// OCR 识别结果
struct OCRResult {
    let text: String
    let confidence: Double
    let boundingBoxes: [CGRect]

    init(text: String, confidence: Double = 1.0, boundingBoxes: [CGRect] = []) {
        self.text = text
        self.confidence = confidence
        self.boundingBoxes = boundingBoxes
    }
}

/// OCR 服务协议
protocol OCRServiceProtocol {
    /// 识别图片中的文字
    func recognizeText(from image: UIImage) async throws -> OCRResult

    /// 识别多张图片
    func recognizeText(from images: [UIImage]) async throws -> [OCRResult]
}

/// OCR 模式
enum OCRMode: String, CaseIterable {
    case local = "local"
    case remote = "remote"

    var displayName: String {
        switch self {
        case .local: return "本地 OCR"
        case .remote: return "第三方识图"
        }
    }

    var description: String {
        switch self {
        case .local: return "使用 Apple Vision，隐私友好"
        case .remote: return "图片发送到 AI 服务识别"
        }
    }
}
