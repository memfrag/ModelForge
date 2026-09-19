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
        .library(name: "ModelForgeKit", targets: ["ModelForgeKit"]),
        .executable(name: "modelgen", targets: ["modelgen"])
    ],
    targets: [
        .target(name: "ModelForgeKit"),
        // A thin wrapper over the library, so a schema can be checked and regenerated from
        // a build script or CI without the app.
        .executableTarget(name: "modelgen", dependencies: ["ModelForgeKit"]),
        .testTarget(
            name: "ModelForgeKitTests",
            dependencies: ["ModelForgeKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
