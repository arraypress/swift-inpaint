//
//  InpaintTests.swift
//  InpaintTests
//

import CoreImage
import Foundation
import Testing
@testable import Inpaint

@Suite("Inpaint")
struct InpaintTests {

    private func env(_ k: String) -> String? { ProcessInfo.processInfo.environment[k] }

    @Test("Remove a masked region and write the result",
          .enabled(if: ProcessInfo.processInfo.environment["INPAINT_RENDER"] != nil))
    func inpaintRender() throws {
        guard let modelPath = env("INPAINT_MODEL") else { print("[skip] set INPAINT_MODEL"); return }
        let inpainter = try LaMaInpainter(modelURL: URL(fileURLWithPath: modelPath))
        let imgPath = env("INPAINT_IMAGE") ?? (NSHomeDirectory() + "/Downloads/depth_frame.png")
        guard let frame = CIImage(contentsOf: URL(fileURLWithPath: imgPath)) else { print("[skip] no image"); return }
        let extent = frame.extent, W = extent.width, H = extent.height

        // Mask (white = remove): a box over the person. Top-left 0.26…0.74 x,
        // 0.16…1.0 y → CoreImage bottom-left rect.
        let black = CIImage(color: .black).cropped(to: extent)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1))
            .cropped(to: CGRect(x: 0.26 * W, y: 0, width: 0.48 * W, height: 0.84 * H))
        let mask = white.composited(over: black).cropped(to: extent)

        let t0 = Date().timeIntervalSinceReferenceDate
        guard let result = inpainter.inpaint(frame, mask: mask) else { Issue.record("no result"); return }
        let ms = (Date().timeIntervalSinceReferenceDate - t0) * 1000
        print("INPAINT \(Int(W))x\(Int(H)) in \(Int(ms))ms")
        #expect(result.extent == extent)

        try CIContext().writePNGRepresentation(of: result,
                                               to: URL(fileURLWithPath: NSHomeDirectory() + "/Downloads/inpaint_swift.png"),
                                               format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        print("WROTE ~/Downloads/inpaint_swift.png")
    }
}
