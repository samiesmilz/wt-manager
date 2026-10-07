// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WTManager",
    platforms: [.macOS(.v13)],
    targets: [
        // Shared so the app and the icon generator draw the character with one
        // renderer. Two rasterisers over one set of art is two chances to drift.
        .target(name: "WTManagerKit", path: "Sources/WTManagerKit"),
        .executableTarget(name: "WTManager", dependencies: ["WTManagerKit"], path: "Sources/WTManager"),
        .executableTarget(name: "MakeIcon", dependencies: ["WTManagerKit"], path: "Sources/MakeIcon"),
        .testTarget(name: "WTManagerKitTests", dependencies: ["WTManagerKit"],
                    path: "Tests/WTManagerKitTests"),
    ]
)
