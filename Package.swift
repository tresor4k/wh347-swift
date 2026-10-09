// swift-tools-version:5.9
// WH-347 certified payroll calculations (Rev. January 2025), published by TableTemplates.
// https://tabletemplates.com/certified-payroll-software/
import PackageDescription

let package = Package(
    name: "WH347",
    products: [
        .library(name: "WH347", targets: ["WH347"])
    ],
    targets: [
        .target(name: "WH347", path: "Sources/WH347"),
        .testTarget(name: "WH347Tests", dependencies: ["WH347"], path: "Tests/WH347Tests")
    ]
)
