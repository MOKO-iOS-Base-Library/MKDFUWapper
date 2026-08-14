// swift-tools-version: 6.3
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
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/nordicsemi/IOS-nRF-Connect-Device-Manager.git",
            branch: "main"
        )
    ],
    targets: [
        .target(
            name: "MKDFUWapper",
            dependencies: [
                .product(name: "iOSMcuManagerLibrary", package: "IOS-nRF-Connect-Device-Manager")
            ],
            path: "Sources/MKDFUWapper",
            swiftSettings: [
                // Swift 5 语言模式，关闭严格并发检查
                // 第三方库 iOSMcuManagerLibrary 本身是 Swift 5.10，不兼容 Swift 6 严格并发
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
