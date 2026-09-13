// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacDuoTR",
    defaultLocalization: "tr",
    platforms: [.macOS(.v14)],
    targets: [
        // Kapak açısı sensörünü okuyan bağımsız katman.
        .target(
            name: "KapakSensoru",
            path: "Sources/KapakSensoru",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Menü çubuğu uygulamasının kendisi.
        .executableTarget(
            name: "MacDuoTR",
            dependencies: ["KapakSensoru"],
            path: "Sources/MacDuoTR",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Sensörü terminalden test etmek için küçük bir araç.
        .executableTarget(
            name: "sensorkontrol",
            dependencies: ["KapakSensoru"],
            path: "Sources/sensorkontrol",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
