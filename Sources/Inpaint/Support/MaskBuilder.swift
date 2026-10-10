//
//  MaskBuilder.swift
//  Inpaint
//
//  Created by David Sherlock on 2026.
//
//  Masks as 8-bit grey `CGImage`s, white = remove, the size of the image
//  they cover. Rectangles arrive in top-left origin pixels and Core Graphics
//  draws from the bottom left; that flip happens here and nowhere else.
//

import CoreGraphics
import CoreImage
import Foundation

/// Builds, combines and measures masks.
public enum MaskBuilder {

    /// A black mask with white rectangles.
    ///
    /// - Parameters:
    ///   - size: The image's size in pixels.
    ///   - rects: What to mark, in top-left origin pixels.
    /// - Returns: The mask.
    /// - Throws: ``InpaintError/renderFailed(_:)``.
    public static func mask(size: CGSize, rects: [CGRect]) throws -> CGImage {
        let context = try grayContext(size)
        context.setFillColor(gray: 1, alpha: 1)
        for rect in rects {
            context.fill(CGRect(x: rect.minX, y: size.height - rect.maxY,
                                width: rect.width, height: rect.height))
        }
        guard let image = context.makeImage() else { throw InpaintError.renderFailed("a mask") }
        return image
    }

    /// Every mask at once: white wherever any of them is.
    ///
    /// - Parameters:
    ///   - masks: Masks of the same size.
    ///   - size: That size.
    /// - Returns: The union.
    /// - Throws: ``InpaintError/maskSizeMismatch(mask:image:)`` and
    ///   ``InpaintError/renderFailed(_:)``.
    public static func union(_ masks: [CGImage], size: CGSize) throws -> CGImage {
        let context = try grayContext(size)
        context.setBlendMode(.lighten)
        for mask in masks {
            guard mask.width == Int(size.width), mask.height == Int(size.height) else {
                throw InpaintError.maskSizeMismatch(mask: CGSize(width: mask.width, height: mask.height), image: size)
            }
            context.draw(mask, in: CGRect(origin: .zero, size: size))
        }
        guard let image = context.makeImage() else { throw InpaintError.renderFailed("a combined mask") }
        return image
    }

    /// Widens every white area by a number of pixels.
    ///
    /// What is being removed always reaches a little past where a detector
    /// draws its edge — a shadow, anti-aliasing, a drop shadow on a
    /// watermark — and a fill that stops at the edge leaves that fringe
    /// behind as an outline.
    ///
    /// - Parameters:
    ///   - mask: The mask.
    ///   - pixels: How far to grow it. Zero returns it unchanged.
    /// - Returns: The grown mask.
    /// - Throws: ``InpaintError/renderFailed(_:)``.
    public static func grow(_ mask: CGImage, by pixels: Int) throws -> CGImage {
        guard pixels > 0 else { return mask }
        let input = CIImage(cgImage: mask)
        let grown = input.clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: ["inputRadius": pixels])
            .cropped(to: input.extent)
        let space = CGColorSpace(name: CGColorSpace.linearGray) ?? CGColorSpaceCreateDeviceGray()
        guard let image = CIContext().createCGImage(grown, from: input.extent, format: .L8, colorSpace: space) else {
            throw InpaintError.renderFailed("a grown mask")
        }
        return image
    }

    /// The fraction of a mask that is marked, from 0 to 1.
    public static func coverage(of mask: CGImage) -> Double {
        let pixels = grayPixels(mask)
        guard !pixels.isEmpty else { return 0 }
        return Double(pixels.lazy.filter { $0 > 127 }.count) / Double(pixels.count)
    }

    /// The bounds of a mask's white, in top-left origin pixels, or nil when
    /// it marks nothing.
    public static func contentBounds(of mask: CGImage) -> CGRect? {
        let pixels = grayPixels(mask)
        let width = mask.width
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for (index, value) in pixels.enumerated() where value > 127 {
            let x = index % width, y = index / width
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    // MARK: - Pixels

    /// A mask's pixels as one byte each, row by row from the top, whatever
    /// format it arrived in.
    static func grayPixels(_ mask: CGImage) -> [UInt8] {
        guard let context = try? grayContext(CGSize(width: mask.width, height: mask.height)) else { return [] }
        context.draw(mask, in: CGRect(x: 0, y: 0, width: mask.width, height: mask.height))
        guard let data = context.data else { return [] }
        let count = context.bytesPerRow * mask.height
        let bytes = data.bindMemory(to: UInt8.self, capacity: count)
        var pixels = [UInt8]()
        pixels.reserveCapacity(mask.width * mask.height)
        for row in 0..<mask.height {
            let start = row * context.bytesPerRow
            pixels.append(contentsOf: UnsafeBufferPointer(start: bytes + start, count: mask.width))
        }
        return pixels
    }

    /// A black 8-bit grey canvas.
    static func grayContext(_ size: CGSize) throws -> CGContext {
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            throw InpaintError.renderFailed("a \(Int(size.width))×\(Int(size.height)) mask")
        }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(origin: .zero, size: size))
        return context
    }
}
