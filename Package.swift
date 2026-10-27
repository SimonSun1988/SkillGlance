// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SkillsUsage", defaultLocalization: "en", platforms: [.macOS(.v14)],
  products: [
    .executable(name: "SkillsUsage", targets: ["SkillsUsageApp"]),
    .executable(name: "skills-usage-scan", targets: ["SkillsUsageScan"]),
  ],
  targets: [
    .systemLibrary(name: "CSQLite"), .target(name: "SkillsUsageCore", dependencies: ["CSQLite"]),
    .executableTarget(
      name: "SkillsUsageApp", dependencies: ["SkillsUsageCore"], resources: [.process("Resources")]),
    .executableTarget(name: "SkillsUsageScan", dependencies: ["SkillsUsageCore"]),
    .testTarget(name: "SkillsUsageCoreTests", dependencies: ["SkillsUsageCore"]),
    .testTarget(name: "SkillsUsageAppTests", dependencies: ["SkillsUsageApp"]),
  ])
