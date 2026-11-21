// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MKDFUWapper",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "MKDFUWapper",
            targets: ["MKDFUWapper"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/NordicSemiconductor/IOS-nRF-Connect-Device-Manager.git", from: "1.14.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
    ],
    targets: [
        .target(
            name: "MKDFUWapper",
            dependencies: [
                .product(name: "iOSMcuManagerLibrary", package: "IOS-nRF-Connect-Device-Manager"),
                "ZIPFoundation",
            ],
            path: "Sources/MKDFUWapper"
        )
    ]
)
