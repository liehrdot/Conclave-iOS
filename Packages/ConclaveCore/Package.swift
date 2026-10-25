// swift-tools-version: 6.2
// ConclaveCore: everything the app does that needs no screen (server calls, the outbox, the rules
// for the phone's operations). No UI here, so its tests also run on Linux in CI.
import PackageDescription

let package = Package(
    name: "ConclaveCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "ConclaveCore", targets: ["ConclaveCore"])],
    targets: [
        .target(name: "ConclaveCore"),
        .testTarget(name: "ConclaveCoreTests", dependencies: ["ConclaveCore"]),
    ]
)
