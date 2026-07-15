//
//  LaMaInpainter.swift
//  Inpaint
//
//  Created by David Sherlock on 2026.
//

import CoreImage
import CoreML
import Foundation

/// Wraps the LaMa Core ML inpainting model (Apache): an image + a mask of what
/// to remove (white = remove) → a plausibly filled result. The model runs at
/// 800×800; the fill is composited back onto the full-resolution original so
/// only the masked region changes.
public final class LaMaInpainter: @unchecked Sendable {

    static let side = 800
    private let model: MLModel
    private let ciContext = CIContext()

    public init(modelURL: URL) throws {
        let url = modelURL.pathExtension == "mlmodelc" ? modelURL : try MLModel.compileModel(at: modelURL)
        let config = MLModelConfiguration()
        config.computeUnits = .all
        self.model = try MLModel(contentsOf: url, configuration: config)
    }

    /// Removes the masked region from `image` (mask white = remove) and fills it.
    /// `feather` softens the seam. Returns the full-resolution result.
    public func inpaint(_ image: CIImage, mask: CIImage, feather: CGFloat = 2) -> CIImage? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let N = Self.side

        guard let imageBuffer = pixelBuffer(from: image, side: N, format: kCVPixelFormatType_32BGRA),
              let maskBuffer = pixelBuffer(from: mask, side: N, format: kCVPixelFormatType_OneComponent8)
        else { return nil }

        guard let out = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "image": imageBuffer, "mask": maskBuffer,
        ])),
              let filledBuffer = out.featureValue(for: "output")?.imageBufferValue
        else { return nil }

        // Upscale the 800² fill back to the frame, then composite it in only
        // where the mask is (feathered) — the rest stays full-res sharp.
        let filled = CIImage(cvPixelBuffer: filledBuffer)
        let sx = extent.width / filled.extent.width, sy = extent.height / filled.extent.height
        let filledUp = filled
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: extent.minX - filled.extent.minX * sx,
                                               y: extent.minY - filled.extent.minY * sy))
            .cropped(to: extent)

        let softMask = feather > 0
            ? mask.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: ["inputRadius": feather]).cropped(to: extent)
            : mask
        return filledUp.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": image, "inputMaskImage": softMask,
        ]).cropped(to: extent)
    }

    private func pixelBuffer(from image: CIImage, side: Int, format: OSType) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        CVPixelBufferCreate(nil, side, side, format, attrs, &pb)
        guard let buffer = pb else { return nil }
        let sx = CGFloat(side) / image.extent.width, sy = CGFloat(side) / image.extent.height
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        ciContext.render(scaled, to: buffer)
        return buffer
    }
}
