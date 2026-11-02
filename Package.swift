// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "LocalLab", platforms: [.macOS(.v14)], products: [.executable(name: "LocalLab", targets: ["LocalLab"])], targets: [.executableTarget(name: "LocalLab")], swiftLanguageModes: [.v5])
