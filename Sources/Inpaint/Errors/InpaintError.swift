//
//  InpaintError.swift
//  Inpaint
//
//  Created by David Sherlock on 2026.
//
//  Failures a caller can act on, each naming what was wrong.
//

import Foundation

/// Why something could not be erased.
public enum InpaintError: Error, LocalizedError, Sendable, Equatable {
    /// The model file could not be compiled or loaded.
    case modelUnavailable(String)
    /// The model ran and returned nothing usable.
    case predictionFailed(String)
    /// The mask is not the size of the image it is meant to cover.
    case maskSizeMismatch(mask: CGSize, image: CGSize)
    /// The mask marks nothing to remove — nothing matched, or it is all black.
    case emptyMask
    /// A Vision request behind a target failed.
    case analysisFailed(String)
    /// Core Image or Core Graphics could not produce the result.
    case renderFailed(String)

    /// A lowercase phrase that reads inside a sentence, for a CLI or a log.
    public var errorDescription: String? {
        switch self {
        case .modelUnavailable(let why): return "the inpainting model could not be loaded: \(why)"
        case .predictionFailed(let why): return "the inpainting model failed: \(why)"
        case .maskSizeMismatch(let mask, let image):
            return "the mask is \(Int(mask.width))×\(Int(mask.height)) but the image is \(Int(image.width))×\(Int(image.height))"
        case .emptyMask: return "nothing to erase — the mask marks no pixels"
        case .analysisFailed(let why): return "could not find what to erase: \(why)"
        case .renderFailed(let step): return "could not render \(step)"
        }
    }
}
