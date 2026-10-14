// swift-tools-version:5.9
import PackageDescription

// The speech logic: Foundation only, so it's tested on any machine (swift test).
var targets: [Target] = [
    .target(name: "CountdownCore"),
    .testTarget(name: "CountdownCoreTests", dependencies: ["CountdownCore"]),
]
var dependencies: [Package.Dependency] = []
#if os(macOS)
// The menubar app: AppKit, so only on the Mac. FluidAudio runs the open-source speech models
// (Kokoro's voices, Parakeet's listening) on this Mac; it needs Swift 6 to build.
dependencies.append(.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"))
targets.append(.executableTarget(name: "CountdownOverlay", dependencies: [
    "CountdownCore",
    .product(name: "FluidAudio", package: "FluidAudio"),
]))
#endif

let package = Package(name: "CountdownOverlay", platforms: [.macOS(.v14)], dependencies: dependencies, targets: targets)
