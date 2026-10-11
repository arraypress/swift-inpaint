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

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
