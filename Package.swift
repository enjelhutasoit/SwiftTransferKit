// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftTransferKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "TransferDomain", targets: ["TransferDomain"]),
    ],
    targets: [
        .target(name: "TransferDomain"),
        .testTarget(
            name: "TransferDomainTests",
            dependencies: ["TransferDomain"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
