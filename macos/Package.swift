// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "OneInstallMac", platforms: [.macOS(.v14)],
  products: [.executable(name: "1nstall", targets: ["OneInstall"])],
  targets: [
    .target(name: "OneInstallCore", resources: [.process("Resources")]),
    .executableTarget(name: "OneInstall", dependencies: ["OneInstallCore"]),
    .executableTarget(name: "OneInstallAdmin", dependencies: ["OneInstallCore"]),
    .executableTarget(
      name: "OneInstallChecks", dependencies: ["OneInstallCore"], path: "Tests/OneInstallCoreTests"),
  ], swiftLanguageModes: [.v5]
)
