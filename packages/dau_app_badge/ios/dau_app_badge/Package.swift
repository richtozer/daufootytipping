// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "dau_app_badge",
  platforms: [
    .iOS("13.0")
  ],
  products: [
    .library(name: "dau-app-badge", targets: ["dau_app_badge"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "dau_app_badge",
      dependencies: []
    )
  ]
)
