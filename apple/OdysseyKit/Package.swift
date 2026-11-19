// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OdysseyKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "OdysseyKit", targets: ["OdysseyKit"])],
    targets: [
        .target(name: "OdysseyKit"),
        .testTarget(name: "OdysseyKitTests", dependencies: ["OdysseyKit"]),
    ]
)
