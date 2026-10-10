//
//  PersonBoxes.swift
//  Inpaint
//
//  Created by David Sherlock on 2026.
//
//  The people the body detector is sure of and the outline request missed,
//  as boxes. Pure arithmetic over rectangles, so which bodies become boxes —
//  and how big — is tested without a photograph.
//

import CoreGraphics
import Foundation

/// Body detections that need a box because no outline covers them.
public enum PersonBoxes {

    /// How much a box grows on each side, as a fraction of its size: a body
    /// rectangle hugs the figure, and the shadow and loose hair beside it
    /// would otherwise stay behind as a ghost.
    public static let padding: CGFloat = 0.08

    /// The bodies no outline already covers, with the overlapping detections
    /// of one person — the upper-body and whole-body requests both answer —
    /// merged into one.
    ///
    /// - Parameters:
    ///   - bodies: Every confident body detection, top-left origin pixels.
    ///   - outlines: The bounds of every outline kept.
    /// - Returns: One rectangle per person still to cover.
    public static func unoutlined(_ bodies: [CGRect], outlines: [CGRect]) -> [CGRect] {
        var people: [CGRect] = []
        for body in bodies.sorted(by: { $0.width * $0.height > $1.width * $1.height }) {
            if outlines.contains(where: { overlap(body, $0) > 0.5 }) { continue }
            if let index = people.firstIndex(where: { overlap(body, $0) > 0.5 }) {
                people[index] = people[index].union(body)
            } else {
                people.append(body)
            }
        }
        return people
    }

    /// A box grown by ``padding`` on every side, kept inside the image.
    public static func padded(_ rect: CGRect, in size: CGSize) -> CGRect {
        rect.insetBy(dx: -rect.width * padding, dy: -rect.height * padding)
            .intersection(CGRect(origin: .zero, size: size))
    }

    /// The share of the smaller rectangle that lies inside the other.
    static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let common = a.intersection(b)
        guard !common.isNull else { return 0 }
        let smaller = min(a.width * a.height, b.width * b.height)
        return smaller > 0 ? (common.width * common.height) / smaller : 0
    }
}
