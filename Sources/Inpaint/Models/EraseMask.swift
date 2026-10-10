//
//  EraseMask.swift
//  Inpaint
//
//  Created by David Sherlock on 2026.
//
//  A built mask and how it was built: the pixels the model will be told to
//  replace, the regions they came from, and how much of the picture that is
//  — the one number that predicts whether the result will hold up.
//

import CoreGraphics
import Foundation

/// White where something will be removed, black where the image is kept.
public struct EraseMask: @unchecked Sendable {
    /// The mask: one 8-bit grey channel, the image's size, white = remove.
    public let image: CGImage
    /// What it was built from.
    public let regions: [FoundRegion]
    /// The fraction of the image marked, from 0 to 1.
    public let coverage: Double

    /// - Parameters:
    ///   - image: The mask.
    ///   - regions: What it was built from.
    ///   - coverage: The fraction marked.
    public init(image: CGImage, regions: [FoundRegion], coverage: Double) {
        self.image = image
        self.regions = regions
        self.coverage = coverage
    }

    /// Whether the mask covers more than LaMa fills well. See
    /// ``EraseMask/reliableCoverage``.
    public var isLarge: Bool { coverage > Self.reliableCoverage }

    /// The share of an image above which a fill stops being trustworthy.
    ///
    /// MEASURED on a striped, graded scene with a known background, erasing
    /// a centred square of growing size: up to 16% of the frame the fill's
    /// error was about a third of a flat average-colour fill's; at 22% it
    /// had lost most of that lead, and from 31% it was WORSE than the flat
    /// fill — the stripes carried on but a dark ghost sat over the middle.
    /// The line goes between the last good and the first bad reading.
    public static let reliableCoverage = 0.2
}
