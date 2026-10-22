// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "DotLocalBridge", platforms: [.macOS(.v14), .iOS(.v17)], products: [
 .library(name: "DotLocalBridge", targets: ["DotLocalBridge"])
], targets: [.target(name: "DotLocalBridge"), .testTarget(name: "DotLocalBridgeTests", dependencies: ["DotLocalBridge"]),
 .executableTarget(name: "RelayConnectionProbe", dependencies: ["DotLocalBridge"], path: "Tools/RelayConnectionProbe")])
