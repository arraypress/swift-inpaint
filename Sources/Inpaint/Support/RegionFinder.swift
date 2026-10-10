//
//  RegionFinder.swift
//  Inpaint
//
//  Created by David Sherlock on 2026.
//
//  The Vision requests that turn "the watermark" or "the people" into
//  pixels. Vision reports in a unit square from the LOWER left; everything
//  this library hands back is top-left origin pixels, converted here.
//

import CoreGraphics
import CoreImage
import Foundation
import Vision

/// Finds text and people to erase.
public enum RegionFinder {

    /// The words to remove.
    ///
    /// With a phrase, only the phrase itself is boxed, wherever it occurs —
    /// not the line it sits on, so "© Shutterstock" in a caption takes the
    /// mark and leaves the caption. Without one, every line of text.
    ///
    /// - Parameters:
    ///   - image: The image to read.
    ///   - phrase: What to look for, case-insensitive, or nil for all text.
    /// - Returns: One region per occurrence or line, possibly none.
    /// - Throws: ``InpaintError/analysisFailed(_:)``.
    public static func text(in image: CGImage, matching phrase: String?) async throws -> [FoundRegion] {
        let size = CGSize(width: image.width, height: image.height)
        let observations: [RecognizedTextObservation]
        do {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            observations = try await request.perform(on: image)
        } catch {
            throw InpaintError.analysisFailed(error.localizedDescription)
        }

        var found: [FoundRegion] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let line = candidate.string
            guard let phrase, !phrase.isEmpty else {
                found.append(FoundRegion(kind: .text,
                                         rect: observation.boundingBox.toImageCoordinates(size, origin: .upperLeft),
                                         text: line))
                continue
            }
            var searchStart = line.startIndex
            while let range = line.range(of: phrase, options: .caseInsensitive, range: searchStart..<line.endIndex) {
                if let box = candidate.boundingBox(for: range) {
                    found.append(FoundRegion(kind: .text,
                                             rect: box.boundingBox.toImageCoordinates(size, origin: .upperLeft),
                                             text: String(line[range])))
                }
                searchStart = range.upperBound
            }
        }
        return found
    }

    /// The confidence a body detection needs before a person outline in the
    /// same place is believed. ImageForge measured true people at 0.55–0.74
    /// with this detector and floors it at 0.3.
    public static let minimumPersonConfidence: Float = 0.3

    /// Every person in the image, as one mask by their outlines.
    ///
    /// An outline is kept only where the body detector also finds a person.
    /// MEASURED: the instance-mask request, run alone on a card bearing
    /// nothing but two lines of text, returned a "person" covering 15% of
    /// it with an observation confidence of 1.0 — that number is not a
    /// per-person score — and erasing it would have taken the caption.
    /// The body detector reports a real confidence, so it is the witness.
    ///
    /// - Parameter image: The image to read.
    /// - Returns: The mask at the image's size and one region per person,
    ///   or nil when there is nobody.
    /// - Throws: ``InpaintError/analysisFailed(_:)`` and
    ///   ``InpaintError/renderFailed(_:)``.
    public static func people(in image: CGImage) async throws -> (mask: CGImage, regions: [FoundRegion])? {
        let observation: InstanceMaskObservation?
        do {
            observation = try await GeneratePersonInstanceMaskRequest().perform(on: image)
        } catch {
            throw InpaintError.analysisFailed(error.localizedDescription)
        }
        guard let observation, !observation.allInstances.isEmpty else { return nil }

        let size = CGSize(width: image.width, height: image.height)
        let bodies: [CGRect]
        do {
            bodies = try await DetectHumanRectanglesRequest().perform(on: image)
                .filter { $0.confidence >= minimumPersonConfidence }
                .map { $0.boundingBox.toImageCoordinates(size, origin: .upperLeft) }
        } catch {
            throw InpaintError.analysisFailed(error.localizedDescription)
        }
        guard !bodies.isEmpty else { return nil }

        var masks: [CGImage] = []
        var regions: [FoundRegion] = []
        for instance in observation.allInstances {
            let buffer: CVPixelBuffer
            do {
                buffer = try observation.generateMask(for: IndexSet(integer: instance))
            } catch {
                throw InpaintError.analysisFailed(error.localizedDescription)
            }
            let mask = try scaled(buffer, to: size)
            guard let bounds = MaskBuilder.contentBounds(of: mask),
                  bodies.contains(where: { $0.intersects(bounds) }) else { continue }
            masks.append(mask)
            regions.append(FoundRegion(kind: .person, rect: bounds))
        }
        guard !masks.isEmpty else { return nil }
        return (try MaskBuilder.union(masks, size: size), regions)
    }

    /// A Vision mask, which comes back at the model's own resolution, drawn
    /// up to the image's size as 8-bit grey.
    static func scaled(_ buffer: CVPixelBuffer, to size: CGSize) throws -> CGImage {
        let mask = CIImage(cvPixelBuffer: buffer)
        let scaled = mask.transformed(by: CGAffineTransform(scaleX: size.width / mask.extent.width,
                                                            y: size.height / mask.extent.height))
        let space = CGColorSpace(name: CGColorSpace.linearGray) ?? CGColorSpaceCreateDeviceGray()
        guard let image = CIContext().createCGImage(scaled, from: CGRect(origin: .zero, size: size),
                                                    format: .L8, colorSpace: space) else {
            throw InpaintError.renderFailed("a person mask")
        }
        return image
    }
}
