// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkillsManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SkillsManager", targets: ["SkillsManager"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.4.0"),
        .package(url: "https://github.com/LiYanan2004/MarkdownView", from: "2.6.1"),
    ],
    targets: [
        .executableTarget(
            name: "SkillsManager",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "MarkdownView", package: "MarkdownView"),
            ],
            path: "SkillsManager",
            exclude: [
                "Assets.xcassets",
                "Info.plist",
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "SkillsManagerTests",
            dependencies: ["SkillsManager"],
            path: "Tests/SkillsManagerTests"
        ),
    ]
)
