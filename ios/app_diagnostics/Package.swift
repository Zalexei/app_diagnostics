// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "app_diagnostics",
  platforms: [
    .iOS("13.0")
  ],
  products: [
    .library(name: "app-diagnostics", targets: ["app_diagnostics"])
  ],
  dependencies: [],
  targets: [
    .target(
      name: "app_diagnostics",
      dependencies: [],
      resources: [
        .process("PrivacyInfo.xcprivacy")
      ]
    )
  ]
)
