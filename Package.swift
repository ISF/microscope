// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Microscope",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Microscope", path: "Sources/Microscope")
    ]
)
