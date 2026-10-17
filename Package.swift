// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HangLater",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HangLater", targets: ["HangLater"]),
        .executable(name: "HangLaterChecks", targets: ["HangLaterChecks"]),
        .executable(name: "QizhiAgentChecks", targets: ["QizhiAgentChecks"])
    ],
    targets: [
        .target(name: "HangLaterCore"),
        .executableTarget(name: "HangLater", dependencies: ["HangLaterCore"],
                          exclude: ["Resources"]),
        .executableTarget(name: "HangLaterChecks", dependencies: ["HangLaterCore"], path: "Tests/HangLaterCoreTests"),
        .executableTarget(name: "QizhiAgentChecks", dependencies: ["HangLaterCore"], path: "Tests/QizhiAgentTests")
    ],
    swiftLanguageModes: [.v5]
)
