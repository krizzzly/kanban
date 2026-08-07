// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kanban",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "Kanban", targets: ["Kanban"]),
        .library(name: "KanbanCore", targets: ["KanbanCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-cmark", from: "0.8.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "Kanban",
            dependencies: [
                "KanbanCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "Sources/Kanban",
            resources: [.copy("Resources/ClaudeAssets")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "KanbanCore",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            path: "Sources/KanbanCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "KanbanCoreTests",
            dependencies: ["KanbanCore"],
            path: "Tests/KanbanCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
