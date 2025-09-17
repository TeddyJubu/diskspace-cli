// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DiskSpaceSwiftUI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DiskSpaceSwiftUI", targets: ["DiskSpaceSwiftUI"]) 
    ],
    targets: [
        .executableTarget(
            name: "DiskSpaceSwiftUI",
            path: "Sources",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"]) // allow @main App in SPM
            ]
        ),
        .testTarget(
            name: "DiskSpaceSwiftUITests",
            dependencies: ["DiskSpaceSwiftUI"],
            path: "Tests/DiskSpaceSwiftUITests"
        )
    ]
)
