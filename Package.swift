// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "SimpleGraph",
  platforms: [.macOS(.v13), .iOS(.v16)], // enforced by the Jinja library
  products: [
    .library(
      name: "SimpleGraph",
      targets: ["SimpleGraph"]),
    .library(
      name: "CSQLite3",
      targets: ["CSQLite3"])
  ],
  dependencies: [
    .package(url: "https://github.com/johnmai-dev/Jinja.git", from: "1.1.1"),
  ],
  targets: [
    .systemLibrary(
      name: "CSQLite3",
      pkgConfig: "sqlite3"
    ),
    .target(
      name: "CSQLiteShim",
      dependencies: ["CSQLite3"]),
    .target(
      name: "SimpleGraph",
      dependencies: [
        //"CSQLite3",
        "CSQLiteShim",
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
