import Foundation
import UIKit
import Vision

/// Apple Vision OCR 服务实现
final class AppleOCRService: OCRServiceProtocol {
    private let recognitionLevel: VNRequestTextRecognitionLevel
    private let recognitionLanguages: [String]
    private let usesLanguageCorrection: Bool

    init(
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        recognitionLanguages: [String] = ["zh-Hans", "zh-Hant", "en-US"],
        usesLanguageCorrection: Bool = true
    ) {
        self.recognitionLevel = recognitionLevel
        self.recognitionLanguages = recognitionLanguages
        self.usesLanguageCorrection = usesLanguageCorrection
    }

    // MARK: - OCRServiceProtocol

    func recognizeText(from image: UIImage) async throws -> OCRResult {
        guard let cgImage = image.cgImage else {
            throw OCRError.imageConversionFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.processingFailed(error))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation],
                      !observations.isEmpty else {
                    continuation.resume(throwing: OCRError.noTextFound)
                    return
                }

                var recognizedTexts: [String] = []
                var boundingBoxes: [CGRect] = []
                var totalConfidence: Double = 0

                for observation in observations {
                    if let topCandidate = observation.topCandidates(1).first {
                        recognizedTexts.append(topCandidate.string)
                        boundingBoxes.append(observation.boundingBox)
                        totalConfidence += Double(topCandidate.confidence)
                    }
                }

                let averageConfidence = totalConfidence / Double(observations.count)
                let fullText = recognizedTexts.joined(separator: "\n")

                let result = OCRResult(
                    text: fullText,
                    confidence: averageConfidence,
                    boundingBoxes: boundingBoxes
                )

                continuation.resume(returning: result)
            }

            request.recognitionLevel = recognitionLevel
            request.recognitionLanguages = recognitionLanguages
            request.usesLanguageCorrection = usesLanguageCorrection

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.processingFailed(error))
            }
        }
    }

    func recognizeText(from images: [UIImage]) async throws -> [OCRResult] {
        var results: [OCRResult] = []

        for image in images {
            let result = try await recognizeText(from: image)
            results.append(result)
        }

        return results
    }
}

// MARK: - Image Preprocessing

extension AppleOCRService {
    /// 预处理图片以提高 OCR 准确率
    func preprocessImage(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else {
            return image
        }

        let context = CIContext()

        // 应用增强滤镜
        var processedImage = ciImage

        // 1. 自动增强
        let autoEnhanceFilters = ciImage.autoAdjustmentFilters()
        for filter in autoEnhanceFilters {
            filter.setValue(processedImage, forKey: kCIInputImageKey)
            if let output = filter.outputImage {
                processedImage = output
            }
        }

        // 2. 锐化
        if let sharpenFilter = CIFilter(name: "CISharpenLuminance") {
            sharpenFilter.setValue(processedImage, forKey: kCIInputImageKey)
            sharpenFilter.setValue(0.4, forKey: kCIInputSharpnessKey)
            if let output = sharpenFilter.outputImage {
                processedImage = output
            }
        }

        // 3. 对比度增强
        if let contrastFilter = CIFilter(name: "CIColorControls") {
            contrastFilter.setValue(processedImage, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.1, forKey: kCIInputContrastKey)
            if let output = contrastFilter.outputImage {
                processedImage = output
            }
        }

        // 转换回 UIImage
        if let cgImage = context.createCGImage(processedImage, from: processedImage.extent) {
            return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
        }

        return image
    }

    /// 检测并裁剪支付区域
    func detectPaymentRegion(in image: UIImage) async throws -> UIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: OCRError.processingFailed(error))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                // 查找包含金额的区域
                var amountRegion: CGRect?
                for observation in observations {
                    if let text = observation.topCandidates(1).first?.string {
                        // 匹配金额模式
                        if text.contains("¥") || text.contains("￥") ||
                           text.range(of: #"\d+\.\d{2}"#, options: .regularExpression) != nil {
                            if amountRegion == nil {
                                amountRegion = observation.boundingBox
                            } else {
                                amountRegion = amountRegion!.union(observation.boundingBox)
                            }
                        }
                    }
                }

                guard let region = amountRegion else {
                    continuation.resume(returning: nil)
                    return
                }

                // 扩展区域以包含周围上下文
                let expandedRegion = region.insetBy(dx: -0.1, dy: -0.2)
                    .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

                // 裁剪图片
                let imageSize = CGSize(
                    width: CGFloat(cgImage.width),
                    height: CGFloat(cgImage.height)
                )

                let cropRect = CGRect(
                    x: expandedRegion.origin.x * imageSize.width,
                    y: (1 - expandedRegion.origin.y - expandedRegion.height) * imageSize.height,
                    width: expandedRegion.width * imageSize.width,
                    height: expandedRegion.height * imageSize.height
                )

                if let croppedCGImage = cgImage.cropping(to: cropRect) {
                    let croppedImage = UIImage(
                        cgImage: croppedCGImage,
                        scale: image.scale,
                        orientation: image.imageOrientation
                    )
                    continuation.resume(returning: croppedImage)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            request.recognitionLevel = .fast
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.processingFailed(error))
            }
        }
    }
}
