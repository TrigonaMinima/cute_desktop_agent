// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesktopAgent",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Foundation-only pure logic: math, target picking, AgentState, state machine.
        // No AppKit import — fully unit-testable headless.
        .target(
            name: "AgentCore"
        ),
        .testTarget(
            name: "AgentCoreTests",
            dependencies: ["AgentCore"]
        ),

        // Phase 0/1 throwaway spike: proves the overlay window behaviors (float over
        // fullscreen, click-through + hover toggle, no activation stealing, display
        // link) before any behavior/render/state code is built. See native/README.md.
        .executableTarget(
            name: "Spike"
        ),

        // The AppKit shell: overlay window, status item, display link, perception,
        // avatar rendering. Imports AgentCore for state + behavior.
        .executableTarget(
            name: "AgentApp",
            dependencies: ["AgentCore"]
        ),
    ]
)
