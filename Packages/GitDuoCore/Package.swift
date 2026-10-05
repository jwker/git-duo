// swift-tools-version: 6.0
import PackageDescription

// GitDuoCore —— Keychain、本地持久化、Markdown 渲染、unidiff 解析、语法高亮、格式化、日期。
// 依据：TECH_SPEC §2.2。硬约束：**无任何依赖**（含 UI），可独立跑单测。
let package = Package(
    name: "GitDuoCore",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "GitDuoCore", targets: ["GitDuoCore"])
    ],
    targets: [
        .target(name: "GitDuoCore"),
        .testTarget(name: "GitDuoCoreTests", dependencies: ["GitDuoCore"])
    ]
)
