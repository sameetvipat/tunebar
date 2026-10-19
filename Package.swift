// swift-tools-version:5.9
import PackageDescription

// A menu bar app. Build it into Tunebar.app with ./build.sh, which also bundles Resources/.
let package = Package(
    name: "Tunebar",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "Tunebar", path: "Sources/Tunebar")
    ]
)
