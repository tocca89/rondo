// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Rondo",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Rondo",
            path: "Sources/Rondo",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Vision"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
