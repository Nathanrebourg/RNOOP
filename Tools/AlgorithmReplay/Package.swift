// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "AlgorithmReplay", platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../../Packages/StrandAnalytics"), .package(path: "../../Packages/WhoopProtocol")],
    targets: [.executableTarget(name: "AlgorithmReplay", dependencies: ["StrandAnalytics", "WhoopProtocol"])])
