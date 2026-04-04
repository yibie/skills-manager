// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkillsManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SkillsManager", targets: ["SkillsManager"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "SkillsManager",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "SkillsManager"
        ),
    ]
)
