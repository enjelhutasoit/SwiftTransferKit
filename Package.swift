// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftTransferKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v12),
    ],
    products: [
        .library(name: "TransferDomain", targets: ["TransferDomain"]),
        .library(name: "TransferCore", targets: ["TransferCore"]),
        .library(name: "TransferPersistence", targets: ["TransferPersistence"]),
        .library(name: "TransferNetworking", targets: ["TransferNetworking"]),
        .library(name: "TransferSimulation", targets: ["TransferSimulation"]),
        .library(name: "TransferSecurity", targets: ["TransferSecurity"]),
        .library(name: "TransferObservability", targets: ["TransferObservability"]),

        // Example composition only; not part of the production SDK surface.
        .library(name: "TransferDemoSupport", targets: ["TransferDemoSupport"]),
    ],
    targets: [
        .target(name: "TransferDomain"),
        .target(name: "TransferCore", dependencies: ["TransferDomain"]),
        .target(name: "TransferPersistence", dependencies: ["TransferCore", "TransferDomain"]),
        .target(name: "TransferNetworking", dependencies: ["TransferCore", "TransferDomain"]),
        .target(name: "TransferSimulation", dependencies: ["TransferCore", "TransferDomain"]),
        .target(name: "TransferSecurity", dependencies: ["TransferCore", "TransferDomain"]),
        .target(name: "TransferObservability", dependencies: ["TransferCore"]),
        .target(
            name: "TransferDemoSupport",
            dependencies: [
                "TransferCore",
                "TransferDomain",
                "TransferPersistence",
                "TransferSecurity",
                "TransferSimulation",
            ],
            path: "Examples/BusinessTransferDemo/Infrastructure"
        ),
        .testTarget(
            name: "TransferDomainTests",
            dependencies: ["TransferDomain"]
        ),
        .testTarget(
            name: "TransferCoreTests",
            dependencies: [
                "TransferCore",
                "TransferDomain",
                "TransferPersistence",
                "TransferSimulation",
            ]
        ),
        .testTarget(
            name: "TransferPersistenceTests",
            dependencies: ["TransferPersistence", "TransferCore", "TransferDomain"]
        ),
        .testTarget(
            name: "TransferNetworkingTests",
            dependencies: ["TransferNetworking", "TransferCore", "TransferDomain"]
        ),
        .testTarget(
            name: "TransferSimulationTests",
            dependencies: [
                "TransferSimulation",
                "TransferPersistence",
                "TransferCore",
                "TransferDomain",
            ]
        ),
        .testTarget(
            name: "TransferSecurityTests",
            dependencies: [
                "TransferSecurity",
                "TransferPersistence",
                "TransferCore",
                "TransferDomain",
            ]
        ),
        .testTarget(
            name: "TransferIntegrationTests",
            dependencies: [
                "TransferDemoSupport",
                "TransferCore",
                "TransferDomain",
                "TransferPersistence",
                "TransferSecurity",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
