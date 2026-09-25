// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacGameToolbox",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "MacGameToolboxCore", targets: ["MacGameToolboxCore"]),
        .executable(name: "MacGameToolbox", targets: ["MacGameToolbox"]),
        .executable(name: "MetalPilotPrivilegedHelper", targets: ["MetalPilotPrivilegedHelper"])
    ],
    targets: [
        .target(name: "MacGameToolboxCore"),
        .executableTarget(
            name: "MacGameToolbox",
            dependencies: ["MacGameToolboxCore"],
            resources: [.process("Assets.xcassets"), .process("Resources")],
            linkerSettings: [.linkedFramework("ServiceManagement"), .linkedFramework("Security")]
        ),
        .executableTarget(
            name: "MetalPilotPrivilegedHelper",
            dependencies: ["MacGameToolboxCore"],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .testTarget(name: "MacGameToolboxCoreTests", dependencies: ["MacGameToolboxCore"])
    ]
)
