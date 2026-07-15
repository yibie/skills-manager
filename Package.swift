// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkillsManager",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SkillsManager", targets: ["SkillsManager"]),
        .executable(name: "skm", targets: ["skm"]),
        .library(name: "SkillsKernel", targets: ["SkillsKernel"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.4.0"),
        .package(url: "https://github.com/LiYanan2004/MarkdownView", from: "2.6.1"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
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
        // ── Effective-Agent 检视器内核(独立实现,不依赖 SkillsManager)──
        .target(
            name: "SkillsKernel",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/SkillsKernel"
        ),
        .executableTarget(
            name: "skm",
            dependencies: ["SkillsKernel"],
            path: "Sources/skm"
        ),
        .testTarget(
            name: "SkillsKernelTests",
            dependencies: ["SkillsKernel"],
            path: "Tests/SkillsKernelTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
