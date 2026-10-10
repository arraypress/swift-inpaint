//
//  LaMaInpainter.swift
//  Inpaint
//
//  Created by David Sherlock on 2026.
//
//  The model, and the one call that runs it. Everything about WHERE it runs
//  is ``RegionPlanner``'s; everything about WHAT it removes is the mask's.
//

import CoreGraphics
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

    /// Loads the model, compiling an `.mlpackage` once and caching it.
    ///
    /// - Parameter modelURL: The `.mlpackage`, `.mlmodel` or `.mlmodelc`.
    /// - Throws: Core ML's error when the file is not a model it can load.
    public init(modelURL: URL) throws {
        let url = try Self.compiledURL(for: modelURL, cacheFolder: "swift-inpaint")
        let config = MLModelConfiguration()
        config.computeUnits = .all
        self.model = try MLModel(contentsOf: url, configuration: config)
    }

    /// Removes what a mask marks from an image and fills it in.
    ///
    /// - Parameters:
    ///   - image: The picture.
    ///   - mask: White where something goes, the picture's size.
    ///   - feather: How many pixels to soften the seam over.
    /// - Returns: The picture, changed only where the mask is.
    /// - Throws: ``InpaintError/maskSizeMismatch(mask:image:)``,
    ///   ``InpaintError/emptyMask``, ``InpaintError/predictionFailed(_:)``
    ///   or ``InpaintError/renderFailed(_:)``.
    public func erase(_ image: CGImage, mask: CGImage, feather: CGFloat = 2) throws -> CGImage {
        let size = CGSize(width: image.width, height: image.height)
        guard mask.width == image.width, mask.height == image.height else {
            throw InpaintError.maskSizeMismatch(mask: CGSize(width: mask.width, height: mask.height), image: size)
        }
        guard MaskBuilder.contentBounds(of: mask) != nil else { throw InpaintError.emptyMask }
        guard let result = inpaint(CIImage(cgImage: image), mask: CIImage(cgImage: mask), feather: feather) else {
            throw InpaintError.predictionFailed("no output for a \(image.width)×\(image.height) image")
        }
        let space = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let rendered = ciContext.createCGImage(result, from: result.extent, format: .RGBA8, colorSpace: space) else {
            throw InpaintError.renderFailed("the filled image")
        }
        return rendered
    }


    /// Compiles once and caches in Caches/ keyed by name + mtime — compiling
    /// the .mlpackage on every init cost seconds of startup per session.
    static func compiledURL(for modelURL: URL, cacheFolder: String) throws -> URL {
        if modelURL.pathExtension == "mlmodelc" { return modelURL }
        let fm = FileManager.default
        let mtime = (try? fm.attributesOfItem(atPath: modelURL.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let dir = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("\(cacheFolder)/CompiledModels", isDirectory: true)
        let dst = dir.appendingPathComponent("\(modelURL.deletingPathExtension().lastPathComponent)-\(Int(mtime)).mlmodelc")
        if fm.fileExists(atPath: dst.path) { return dst }
        let compiled = try MLModel.compileModel(at: modelURL)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? fm.removeItem(at: dst)
        try fm.moveItem(at: compiled, to: dst)
        return dst
    }

    /// Removes the masked region from `image` (mask white = remove) and fills it.
    /// `feather` softens the seam. Returns the full-resolution result.
    ///
    /// The model runs on a SQUARE crop around the mask's content (padded,
    /// clamped to the frame) rather than the squashed whole frame — squeezing a
    /// wide frame anisotropically into 800² smeared the fill's texture, and the
    /// crop also gives the model far more effective resolution in the region
    /// that matters.
    public func inpaint(_ image: CIImage, mask: CIImage, feather: CGFloat = 2) -> CIImage? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        // A generator mask (infinite extent) or one at another size would
        // silently misalign the model resize vs the composite-back.
        guard !mask.extent.isInfinite else { return nil }
        let mask = mask.cropped(to: extent)
        let N = Self.side

        // The window around the mask's content; the rules are RegionPlanner's.
        let content = maskContentBounds(mask) ?? extent
        let region = RegionPlanner.window(around: content, in: extent)

        guard let imageBuffer = pixelBuffer(from: image.cropped(to: region), side: N, format: kCVPixelFormatType_32BGRA),
              let maskBuffer = pixelBuffer(from: mask.cropped(to: region), side: N, format: kCVPixelFormatType_OneComponent8)
        else { return nil }

        guard let out = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "image": imageBuffer, "mask": maskBuffer,
        ])),
              let filledBuffer = out.featureValue(for: "output")?.imageBufferValue
        else { return nil }

        // Upscale the 800² fill back onto the region, then composite it in only
        // where the mask is (feathered) — the rest stays full-res sharp.
        let filled = CIImage(cvPixelBuffer: filledBuffer)
        let sx = region.width / filled.extent.width, sy = region.height / filled.extent.height
        let filledUp = filled
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: region.minX - filled.extent.minX * sx,
                                               y: region.minY - filled.extent.minY * sy))
            .cropped(to: region)
            .composited(over: image)   // full frame with the filled region in place
            .cropped(to: extent)

        let softMask = feather > 0
            ? mask.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: ["inputRadius": feather]).cropped(to: extent)
            : mask
        return filledUp.applyingFilter("CIBlendWithMask", parameters: [
            "inputBackgroundImage": image, "inputMaskImage": softMask,
        ]).cropped(to: extent)
    }

    /// Tight bounds of the mask's white content via a low-res scan.
    private func maskContentBounds(_ mask: CIImage) -> CGRect? {
        let extent = mask.extent
        let side = 128
        var buf = [UInt8](repeating: 0, count: side * side * 4)
        let scaled = mask
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(side) / extent.width, y: CGFloat(side) / extent.height))
        ciContext.render(scaled, toBitmap: &buf, rowBytes: side * 4,
                         bounds: CGRect(x: 0, y: 0, width: side, height: side),
                         format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side where buf[(y * side + x) * 4] > 32 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let fx = extent.width / CGFloat(side), fy = extent.height / CGFloat(side)
        // The scan's y is top-down (rendered bitmap); CI space is bottom-up.
        return CGRect(x: extent.minX + CGFloat(minX) * fx,
                      y: extent.minY + extent.height - CGFloat(maxY + 1) * fy,
                      width: CGFloat(maxX - minX + 1) * fx,
                      height: CGFloat(maxY - minY + 1) * fy)
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
