// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "kanata-gui-mac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "KanataGUI",
            path: "Sources/KanataGUI",
            resources: [.copy("../../Resources")]
        )
    ]
)
