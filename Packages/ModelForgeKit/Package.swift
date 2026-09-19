// swift-tools-version: 6.2

import PackageDescription

// The compiler for the ModelForge DSL. Deliberately dependency-free and free of any
// UI, AppKit or SwiftUI: the app links it, `swift test` exercises it, and a future
// `modelgen` CLI can be added as an executable target without dragging anything along.
//
// The pipeline is:
//
//   sources -> Lexer -> Parser -> AST -> SemanticAnalyzer -> IR -> Swift/Kotlin emitters
//
let package = Package(
    name: "ModelForgeKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ModelForgeKit", targets: ["ModelForgeKit"])
    ],
    targets: [
        .target(name: "ModelForgeKit"),
        .testTarget(
            name: "ModelForgeKitTests",
            dependencies: ["ModelForgeKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
