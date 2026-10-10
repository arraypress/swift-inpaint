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

    /// Every person in the image, as one mask: by their outlines where Vision
    /// can draw one, by a padded box where it can only say a body is there.
    ///
    /// Two requests, because neither is enough alone. MEASURED:
    ///
    /// - The outline request, alone, found a "person" covering 15% of a card
    ///   bearing nothing but two lines of text (observation confidence 1.0,
    ///   which is not a per-person score). So an outline is kept only where
    ///   the body detector — which does give a real confidence — agrees.
    /// - On thirteen Wikimedia Commons photographs, the outline request drew
    ///   NOTHING for three with people in them, one a man filling a third of
    ///   the frame on a bench; the body detector found him at 0.70. So a body
    ///   with no outline is erased as a box, which costs more invented
    ///   background but leaves no one behind.
    /// - The body detector's default looks for upper bodies only; one seated
    ///   reader scored 0.21 that way and 0.41 asked for whole bodies. Both are
    ///   asked, and the higher answer counts.
    ///
    /// - Parameter image: The image to read.
    /// - Returns: The mask at the image's size and one region per person,
    ///   or nil when there is nobody.
    /// - Throws: ``InpaintError/analysisFailed(_:)`` and
    ///   ``InpaintError/renderFailed(_:)``.
    public static func people(in image: CGImage) async throws -> (mask: CGImage, regions: [FoundRegion])? {
        let size = CGSize(width: image.width, height: image.height)
        let observation: InstanceMaskObservation?
        var bodies: [CGRect] = []
        do {
            observation = try await GeneratePersonInstanceMaskRequest().perform(on: image)
            var whole = DetectHumanRectanglesRequest()
            whole.upperBodyOnly = false
            for request in [DetectHumanRectanglesRequest(), whole] {
                bodies += try await request.perform(on: image)
                    .filter { $0.confidence >= minimumPersonConfidence }
                    .map { $0.boundingBox.toImageCoordinates(size, origin: .upperLeft) }
            }
        } catch {
            throw InpaintError.analysisFailed(error.localizedDescription)
        }
        guard !bodies.isEmpty else { return nil }

        var masks: [CGImage] = []
        var regions: [FoundRegion] = []
        var outlines: [CGRect] = []
        for instance in observation?.allInstances ?? IndexSet() {
            let buffer: CVPixelBuffer
            do {
                buffer = try observation!.generateMask(for: IndexSet(integer: instance))
            } catch {
                throw InpaintError.analysisFailed(error.localizedDescription)
            }
            let mask = try scaled(buffer, to: size)
            guard let bounds = MaskBuilder.contentBounds(of: mask),
                  bodies.contains(where: { $0.intersects(bounds) }) else { continue }
            masks.append(mask)
            outlines.append(bounds)
            regions.append(FoundRegion(kind: .person, rect: bounds))
        }

        let boxes = PersonBoxes.unoutlined(bodies, outlines: outlines)
            .map { PersonBoxes.padded($0, in: size) }
        if !boxes.isEmpty {
            masks.append(try MaskBuilder.mask(size: size, rects: boxes))
            regions += boxes.map { FoundRegion(kind: .person, rect: $0) }
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
