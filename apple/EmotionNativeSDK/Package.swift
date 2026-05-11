// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "EmotionNativeSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v11)
    ],
    products: [
        .library(
            name: "EmotionNativeSDK",
            targets: ["EmotionNativeSDK"]
        )
    ],
    targets: [
        .target(name: "EmotionNativeSDK"),
        .testTarget(
            name: "EmotionNativeSDKTests",
            dependencies: ["EmotionNativeSDK"],
            resources: [.process("Resources")]
        )
    ]
)
