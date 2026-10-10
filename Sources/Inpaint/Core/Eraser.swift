//
//  Eraser.swift
//  Inpaint
//
//  Created by David Sherlock on 2026.
//
//  The front door: say what to remove, get a mask that shows what was
//  matched, then hand it to the model. Two steps rather than one, so a
//  caller — or an agent — can look at what "the watermark" matched before
//  anything is changed.
//

import CoreGraphics
import Foundation

/// Turns targets into a mask, and a mask into a cleaned image.
///
/// ```swift
/// let inpainter = try LaMaInpainter(modelURL: lama)
/// let mask = try await Eraser.mask(for: [.text(matching: "shutterstock")], in: photo)
/// mask.regions        // where it was found
/// mask.isLarge        // false — under a fifth of the frame
/// let clean = try inpainter.erase(photo, mask: mask.image)
/// ```
public enum Eraser {

    /// How far masks are grown by default, in pixels: enough to take the
    /// anti-aliased fringe and a drop shadow with the thing itself.
    public static let defaultGrowth = 6

    /// Builds the mask for a set of targets.
    ///
    /// - Parameters:
    ///   - targets: What to remove.
    ///   - image: The picture they are in.
    ///   - extraMask: A painted mask to include as well, white = remove.
    ///   - growth: How far to widen the result, in pixels.
    /// - Returns: The mask, what it was made from, and how much it covers.
    /// - Throws: ``InpaintError/emptyMask`` when nothing matched, and the
    ///   errors of the finders.
    public static func mask(for targets: [EraseTarget], in image: CGImage, extraMask: CGImage? = nil,
                            growth: Int = defaultGrowth) async throws -> EraseMask {
        let size = CGSize(width: image.width, height: image.height)
        var rects: [CGRect] = []
        var masks: [CGImage] = []
        var regions: [FoundRegion] = []

        for target in targets {
            switch target {
            case .rectangle(let rect):
                let kept = rect.intersection(CGRect(origin: .zero, size: size))
                guard !kept.isNull, !kept.isEmpty else { continue }
                rects.append(kept)
                regions.append(FoundRegion(kind: .rectangle, rect: kept))
            case .text(let phrase):
                let found = try await RegionFinder.text(in: image, matching: phrase)
                rects += found.map(\.rect)
                regions += found
            case .people:
                guard let people = try await RegionFinder.people(in: image) else { continue }
                masks.append(people.mask)
                regions += people.regions
            }
        }
        if let extraMask {
            masks.append(extraMask)
            if let bounds = MaskBuilder.contentBounds(of: extraMask) {
                regions.append(FoundRegion(kind: .mask, rect: bounds))
            }
        }
        guard !regions.isEmpty else { throw InpaintError.emptyMask }

        let combined = try MaskBuilder.union([try MaskBuilder.mask(size: size, rects: rects)] + masks, size: size)
        let grown = try MaskBuilder.grow(combined, by: growth)
        return EraseMask(image: grown, regions: regions, coverage: MaskBuilder.coverage(of: grown))
    }
}
