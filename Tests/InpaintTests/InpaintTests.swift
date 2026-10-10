//
//  InpaintTests.swift
//  InpaintTests
//
//  Created by David Sherlock on 2026.
//
//  Everything that decides WHAT is removed and WHERE the model looks is
//  tested with known numbers and no model. The model itself runs only when
//  INPAINT_MODEL points at one, against a synthetic scene whose background
//  is known — so "it filled plausibly" is a measured error, not a glance.
//

import CoreGraphics
import CoreImage
import CoreText
import Foundation
import Testing
@testable import Inpaint

@Suite("Where the model looks")
struct RegionPlannerTests {

    let frame = CGRect(x: 0, y: 0, width: 2000, height: 1200)

    @Test("A speck still gets a window of context")
    func minimumWindow() {
        let window = RegionPlanner.window(around: CGRect(x: 1000, y: 600, width: 20, height: 20), in: frame)
        #expect(window.width == RegionPlanner.minimumSide)
        #expect(window.height == RegionPlanner.minimumSide)
    }

    @Test("The window always covers what is being removed")
    func coversContent() {
        for content in [CGRect(x: 10, y: 10, width: 300, height: 900),
                        CGRect(x: 1900, y: 1100, width: 100, height: 100),
                        CGRect(x: 0, y: 0, width: 2000, height: 1200)] {
            let window = RegionPlanner.window(around: content, in: frame)
            #expect(window.contains(content), "\(content) → \(window)")
            #expect(frame.contains(window))
        }
    }

    @Test("A window near the edge slides inside rather than shrinking")
    func slidesInside() {
        let window = RegionPlanner.window(around: CGRect(x: 1950, y: 1150, width: 40, height: 40), in: frame)
        #expect(window.maxX == frame.maxX)
        #expect(window.maxY == frame.maxY)
        #expect(window.width == RegionPlanner.minimumSide)
    }
}

@Suite("Masks")
struct MaskTests {

    @Test("Rectangles are drawn from the top left")
    func topLeft() throws {
        let mask = try MaskBuilder.mask(size: CGSize(width: 100, height: 80), rects: [CGRect(x: 0, y: 0, width: 10, height: 10)])
        let pixels = MaskBuilder.grayPixels(mask)
        #expect(pixels[0] == 255, "the top-left pixel is marked")
        #expect(pixels[79 * 100] == 0, "the bottom-left one is not")
        #expect(MaskBuilder.contentBounds(of: mask) == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test("Coverage is the marked share")
    func coverage() throws {
        let mask = try MaskBuilder.mask(size: CGSize(width: 200, height: 200), rects: [CGRect(x: 50, y: 50, width: 100, height: 100)])
        #expect(MaskBuilder.coverage(of: mask) == 0.25)
    }

    @Test("A union is white wherever either is")
    func union() throws {
        let size = CGSize(width: 100, height: 100)
        let a = try MaskBuilder.mask(size: size, rects: [CGRect(x: 0, y: 0, width: 50, height: 100)])
        let b = try MaskBuilder.mask(size: size, rects: [CGRect(x: 50, y: 0, width: 50, height: 50)])
        #expect(MaskBuilder.coverage(of: try MaskBuilder.union([a, b], size: size)) == 0.75)
    }

    @Test("Growing widens the bounds by the radius")
    func grow() throws {
        let mask = try MaskBuilder.mask(size: CGSize(width: 200, height: 200), rects: [CGRect(x: 90, y: 90, width: 20, height: 20)])
        let bounds = try #require(MaskBuilder.contentBounds(of: try MaskBuilder.grow(mask, by: 6)))
        #expect(abs(bounds.minX - 84) <= 1)
        #expect(abs(bounds.width - 32) <= 2)
    }

    @Test("Masks of another size are refused")
    func sizeMismatch() throws {
        let small = try MaskBuilder.mask(size: CGSize(width: 10, height: 10), rects: [])
        #expect(throws: InpaintError.self) { try MaskBuilder.union([small], size: CGSize(width: 20, height: 20)) }
    }
}

@Suite("Finding what to erase")
struct FinderTests {

    /// A pale card with two lines of text: a caption, and a watermark.
    static func card() -> CGImage {
        let width = 1400, height = 600
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        context.setFillColor(CGColor(red: 0.93, green: 0.92, blue: 0.88, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 64, nil)
        for (text, y) in [("Harbour at dawn", 420.0), ("SAMPLE Shutterstock", 120.0)] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.15, alpha: 1)]))
            context.textPosition = CGPoint(x: 120, y: y)
            CTLineDraw(line, context)
        }
        return context.makeImage()!
    }

    @Test("A phrase takes itself and leaves the rest of its line")
    func phrase() async throws {
        let found = try await RegionFinder.text(in: Self.card(), matching: "shutterstock")
        #expect(found.count == 1)
        let region = try #require(found.first)
        #expect(region.text == "Shutterstock")
        // The watermark line sits low on the card; SAMPLE starts at x 120.
        #expect(region.rect.minY > 400)
        #expect(region.rect.minX > 300, "SAMPLE is not taken with it")
    }

    @Test("No phrase takes every line")
    func everything() async throws {
        #expect(try await RegionFinder.text(in: Self.card(), matching: nil).count == 2)
    }

    @Test("Nothing matching is an empty mask, not an unchanged success")
    func nothingMatched() async throws {
        await #expect(throws: InpaintError.emptyMask) {
            _ = try await Eraser.mask(for: [.text(matching: "getty")], in: Self.card())
        }
    }

    @Test("A card has no people")
    func noPeople() async throws {
        #expect(try await RegionFinder.people(in: Self.card()) == nil)
    }

    @Test("Rectangles off the edge are clipped; coverage is reported")
    func clipped() async throws {
        let mask = try await Eraser.mask(for: [.rectangle(CGRect(x: 1300, y: 500, width: 400, height: 400))],
                                         in: Self.card(), growth: 0)
        #expect(mask.regions.first?.rect == CGRect(x: 1300, y: 500, width: 100, height: 100))
        #expect(abs(mask.coverage - 10_000.0 / 840_000.0) < 0.0001)
        #expect(!mask.isLarge)
    }
}

@Suite("The model", .enabled(if: ProcessInfo.processInfo.environment["INPAINT_MODEL"] != nil))
struct ModelTests {

    /// A scene with a known background: a soft gradient under bold diagonal
    /// stripes. A fill that does not carry the stripes on scores badly.
    static func background(width: Int, height: Int) -> CGImage {
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        let gradient = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: CGFloat(width), y: CGFloat(height)),
            "inputColor0": CIColor(red: 0.55, green: 0.7, blue: 0.85), "inputColor1": CIColor(red: 0.85, green: 0.8, blue: 0.6)])!.outputImage!
        let stripes = CIFilter(name: "CIStripesGenerator", parameters: [
            "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 0.45), "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
            "inputWidth": 14])!.outputImage!.transformed(by: CGAffineTransform(rotationAngle: 0.5))
        let ci = CIContext()
        return ci.createCGImage(stripes.composited(over: gradient).cropped(to: extent), from: extent,
                                format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
    }

    /// Mean absolute difference inside a rectangle, after a small blur, out of 255.
    static func error(_ a: CGImage, _ b: CGImage, in rect: CGRect) -> Double {
        let ci = CIContext()
        func blurred(_ image: CGImage) -> CIImage {
            let input = CIImage(cgImage: image)
            return input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 3]).cropped(to: input.extent)
        }
        // Core Image is bottom-left; the rectangle is top-left.
        let flipped = CGRect(x: rect.minX, y: CGFloat(a.height) - rect.maxY, width: rect.width, height: rect.height)
        let average = blurred(a).applyingFilter("CIDifferenceBlendMode", parameters: ["inputBackgroundImage": blurred(b)])
            .applyingFilter("CIAreaAverage", parameters: ["inputExtent": CIVector(cgRect: flipped)])
        var pixel = [Float](repeating: 0, count: 4)
        ci.render(average, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        return Double(pixel[0] + pixel[1] + pixel[2]) / 3 * 255
    }

    @Test("An object is erased back to the background it hid")
    func erasesToTheBackground() async throws {
        let model = try #require(ProcessInfo.processInfo.environment["INPAINT_MODEL"])
        let inpainter = try LaMaInpainter(modelURL: URL(fileURLWithPath: model))
        let clean = Self.background(width: 1600, height: 1000)
        let rect = CGRect(x: 650, y: 350, width: 300, height: 300)

        let context = CGContext(data: nil, width: 1600, height: 1000, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(clean, in: CGRect(x: 0, y: 0, width: 1600, height: 1000))
        context.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: rect.minX + 10, y: 1000 - rect.maxY + 10, width: rect.width - 20, height: rect.height - 20))
        let scene = context.makeImage()!

        let mask = try await Eraser.mask(for: [.rectangle(rect)], in: scene, growth: 0)
        let result = try inpainter.erase(scene, mask: mask.image)

        let before = Self.error(scene, clean, in: rect)
        let after = Self.error(result, clean, in: rect)
        print("ERASE 300px: object \(before) → fill \(after) of 255")
        #expect(after < 12, "measured 9.5 on this scene; a flat average-colour fill scores about 18")
        #expect(Self.error(result, clean, in: CGRect(x: 0, y: 0, width: 400, height: 200)) < 0.5, "outside the mask is untouched")
    }

    @Test("A mask of another size is refused before the model runs")
    func mismatch() throws {
        let model = try #require(ProcessInfo.processInfo.environment["INPAINT_MODEL"])
        let inpainter = try LaMaInpainter(modelURL: URL(fileURLWithPath: model))
        let image = Self.background(width: 100, height: 100)
        let mask = try MaskBuilder.mask(size: CGSize(width: 50, height: 50), rects: [CGRect(x: 0, y: 0, width: 10, height: 10)])
        #expect(throws: InpaintError.self) { try inpainter.erase(image, mask: mask) }
    }
}
