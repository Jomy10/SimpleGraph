// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SimpleGraph",
  platforms: [.macOS(.v13), .iOS(.v16)],
  products: [
    .library(
      name: "SimpleGraph",
      targets: ["SimpleGraph"]),
  ],
  dependencies: [
    .package(url: "https://github.com/stephencelis/CSQLite", from: "0.0.3"),
    .package(url: "https://github.com/johnmai-dev/Jinja.git", from: "1.1.1"),
  ],
  targets: [
    .target(
      name: "SimpleGraph",
      dependencies: [
        .product(name: "CSQLite", package: "CSQLite", condition: .when(platforms: [.android, .linux, .openbsd, .wasi, .custom("Windows")])),
        .product(name: "Jinja", package: "Jinja"),
      ],
      exclude: ["simple-graph/README.md", "simple-graph/.gitignore", "simple-graph/LICENSE"],
      resources: [
        .embedInCode("simple-graph/sql")
      ]
    ),
    .testTarget(
      name: "SimpleGraphTests",
      dependencies: ["SimpleGraph"]
    ),
  ]
)
