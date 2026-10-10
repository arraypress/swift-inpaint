//
//  RegionPlanner.swift
//  Inpaint
//
//  Created by David Sherlock on 2026.
//
//  Where the model looks. LaMa runs at 800×800; feeding it the whole frame
//  squashes a wide picture anisotropically and spends most of its 800 pixels
//  on parts that are not being changed. So it is given a square-ish window
//  around what is being removed, with enough surrounding picture to copy
//  from. Pure arithmetic, so the rules can be tested without a model.
//

import CoreGraphics
import Foundation

/// Chooses the window the model inpaints.
public enum RegionPlanner {

    /// How much bigger than the removed content the window aims to be. The
    /// margin is the context the model fills from.
    public static let contextFactor: CGFloat = 1.7
    /// The smallest window side, in pixels: a tiny speck still gets enough
    /// surroundings to read the texture from.
    public static let minimumSide: CGFloat = 320

    /// The window around some content, inside a frame.
    ///
    /// Aims for a square `contextFactor` times the content's longer side,
    /// never under `minimumSide`, slid to stay inside the frame — and never
    /// smaller than the content itself: a forced square that could not hold
    /// a tall mask once left part of it unfilled.
    ///
    /// - Parameters:
    ///   - content: The bounds of what is being removed.
    ///   - extent: The whole frame.
    /// - Returns: The window, inside the frame and covering the content.
    public static func window(around content: CGRect, in extent: CGRect) -> CGRect {
        let want = max(max(content.width, content.height) * contextFactor, minimumSide)
        let width = min(max(want, content.width * 1.1), extent.width)
        let height = min(max(want, content.height * 1.1), extent.height)
        var region = CGRect(x: content.midX - width / 2, y: content.midY - height / 2,
                            width: width, height: height)
        if region.minX < extent.minX { region.origin.x = extent.minX }
        if region.minY < extent.minY { region.origin.y = extent.minY }
        if region.maxX > extent.maxX { region.origin.x = extent.maxX - width }
        if region.maxY > extent.maxY { region.origin.y = extent.maxY - height }
        return region.intersection(extent).union(content.intersection(extent))
    }
}
