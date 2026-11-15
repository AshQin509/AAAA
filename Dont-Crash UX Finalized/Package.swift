// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CodeCoach", platforms: [.macOS(.v13)], products: [.executable(name: "CodeCoach", targets: ["CodeCoach"])], targets: [.target(name: "CodeCoachCore", linkerSettings: [.linkedLibrary("sqlite3")]), .executableTarget(name: "CodeCoach", dependencies: ["CodeCoachCore"], resources: [.process("Resources")]), .testTarget(name: "CodeCoachCoreTests", dependencies: ["CodeCoachCore"])])
