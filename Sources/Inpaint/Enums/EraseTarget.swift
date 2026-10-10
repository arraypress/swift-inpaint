//
//  EraseTarget.swift
//  Inpaint
//
//  Created by David Sherlock on 2026.
//
//  What to remove, said the way a person or an agent would say it — "this
//  box", "the watermark text", "the people" — rather than as a mask someone
//  has to paint. Each becomes white pixels in one mask; the model never sees
//  the difference.
//

import CoreGraphics
import Foundation

/// Something to remove from an image.
public enum EraseTarget: Sendable, Codable, Equatable, Hashable {
    /// A rectangle, in top-left origin pixels — the convention `img crop`
    /// and `img detect` use.
    case rectangle(CGRect)
    /// Text Vision can read. With a phrase, only that phrase wherever it
    /// appears (case-insensitive) — a watermark, a phone number, a name —
    /// and not the rest of its line. Without one, every line of text.
    case text(matching: String?)
    /// Every person Vision can segment, by their outline rather than a box,
    /// so less of the background has to be invented.
    case people
}
