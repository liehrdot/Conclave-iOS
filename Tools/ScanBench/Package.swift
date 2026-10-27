// swift-tools-version: 6.2
// ScanBench: how well the card scanner finds cards, measured on random cards from Scryfall. Each card's picture is
// put into a made-up camera photo (a little turned, blurred, darker or lighter), read with Apple's Vision like the
// app's "Take Photo", and looked up with ConclaveCore's reader against the real Scryfall. Mac only (Vision); run by
// the "Scanner benchmark" workflow.
import PackageDescription

let package = Package(
    name: "ScanBench",
    platforms: [.macOS(.v26)],
    dependencies: [.package(path: "../../Packages/ConclaveCore")],
    targets: [
        .executableTarget(name: "ScanBench", dependencies: [.product(name: "ConclaveCore", package: "ConclaveCore")]),
    ]
)
