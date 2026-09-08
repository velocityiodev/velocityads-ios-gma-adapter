// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "VelocityAdsGmaAdapter",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "VelocityAdsGmaAdapter",
            targets: ["VelocityAdsGmaAdapter"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/googleads/swift-package-manager-google-mobile-ads",
            .upToNextMajor(from: "13.0.0")
        ),
        .package(
            url: "https://github.com/velocityiodev/velocityads-ios-sdk",
            .upToNextMinor(from: "0.10.0")
        )
    ],
    targets: [
        .target(
            name: "VelocityAdsGmaAdapter",
            dependencies: [
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
                .product(name: "VelocityAdsSDK", package: "velocityads-ios-sdk")
            ]
        ),
        .testTarget(
            name: "VelocityAdsGmaAdapterTests",
            dependencies: [
                "VelocityAdsGmaAdapter",
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
                .product(name: "VelocityAdsSDK", package: "velocityads-ios-sdk")
            ]
        )
    ]
)
