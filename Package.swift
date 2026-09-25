// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MetalPilot",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "MetalPilotCore", targets: ["MetalPilotCore"]),
        .executable(name: "MetalPilot", targets: ["MetalPilot"]),
        .executable(name: "MetalPilotPrivilegedHelper", targets: ["MetalPilotPrivilegedHelper"])
    ],
    targets: [
        .target(name: "MetalPilotCore"),
        .executableTarget(
            name: "MetalPilot",
            dependencies: ["MetalPilotCore"],
            resources: [.process("Assets.xcassets"), .process("Resources")],
            linkerSettings: [.linkedFramework("ServiceManagement"), .linkedFramework("Security")]
        ),
        .executableTarget(
            name: "MetalPilotPrivilegedHelper",
            dependencies: ["MetalPilotCore"],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(name: "MetalPilotCoreTests", dependencies: ["MetalPilotCore"])
    ]
)
