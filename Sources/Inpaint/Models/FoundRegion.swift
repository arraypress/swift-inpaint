//
//  FoundRegion.swift
//  Inpaint
//
//  Created by David Sherlock on 2026.
//
//  One thing a mask was built from, so a caller can see what was matched
//  before trusting what was erased — "Shutterstock" at the bottom right, not
//  "Shutterstock" and the caption above it.
//

import CoreGraphics
import Foundation

/// A region marked for removal, and why.
public struct FoundRegion: Sendable, Codable, Equatable, Hashable {
    /// What kind of target produced it.
    public enum Kind: String, Sendable, Codable, Hashable {
        case rectangle, text, person, mask
    }

    /// What produced it.
    public let kind: Kind
    /// Its bounds, in top-left origin pixels.
    public let rect: CGRect
    /// The words, for a text region.
    public let text: String?

    /// - Parameters:
    ///   - kind: What produced it.
    ///   - rect: Its bounds in top-left origin pixels.
    ///   - text: The words, for a text region.
    public init(kind: Kind, rect: CGRect, text: String? = nil) {
        self.kind = kind
        self.rect = rect
        self.text = text
    }
}
