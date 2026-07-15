// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Inpaint",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        // On-device object/logo/watermark removal via LaMa (Apache) — give it
        // an image + a mask of what to remove, get a plausibly filled result.
        .library(name: "Inpaint", targets: ["Inpaint"]),
    ],
    targets: [
        .target(name: "Inpaint"),
        .testTarget(name: "InpaintTests", dependencies: ["Inpaint"]),
    ]
)
