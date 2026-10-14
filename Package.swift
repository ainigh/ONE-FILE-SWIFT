// swift-tools-version:5.9
import PackageDescription

// MPMCore: the session engine, the plan, requests, the announcements and the assistant, Foundation
// only, so it's tested on any machine (swift test). Ported from docs/js, which is the spec.
var targets: [Target] = [
    .target(name: "MPMCore"),
    .testTarget(name: "MPMCoreTests", dependencies: ["MPMCore"]),
]
var dependencies: [Package.Dependency] = []
#if os(macOS)
// The menubar app: SwiftUI in AppKit windows, so only on the Mac. FluidAudio runs the open-source
// speech models (Kokoro's voices, Parakeet's listening) on this Mac; it needs Swift 6 to build.
dependencies.append(.package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.5"))
targets.append(.executableTarget(name: "MachinePromptsMan", dependencies: [
    "MPMCore",
    .product(name: "FluidAudio", package: "FluidAudio"),
]))
#endif

let package = Package(name: "MachinePromptsMan", platforms: [.macOS(.v14)], dependencies: dependencies, targets: targets)
