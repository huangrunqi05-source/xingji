// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "XingjiKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "XingjiCore", targets: ["XingjiCore"]), .library(name: "XingjiData", targets: ["XingjiData"])],
    targets: [
        .target(name: "XingjiCore"),
        .target(name: "XingjiData", dependencies: ["XingjiCore"]),
        .executableTarget(name: "XingjiVerify", dependencies: ["XingjiCore", "XingjiData"], path: "Verification"),
        .testTarget(name: "XingjiCoreTests", dependencies: ["XingjiCore"]),
        .testTarget(name: "XingjiDataTests", dependencies: ["XingjiData", "XingjiCore"])
    ]
)
