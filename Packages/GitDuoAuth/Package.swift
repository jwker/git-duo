// swift-tools-version: 6.0
import PackageDescription

// GitDuoAuth —— 认证**编排**（领域服务）。
// 依据：TECH_SPEC §2.2 / §3.1 / §3.2 / §3.6；决策 #30。
//
// 为什么必须单独成包（而不是塞进 GitHubAPI、GitDuoCore 或 App）：
// - 编排要**同时**用两边的零件：换令牌/刷新/撤销只有 `GitHubAPI` 有，
//   凭据落盘只有 `GitDuoCore` 有；
// - 而这两个包按架构铁律（§2.2「依赖方向单向」）**互不依赖**——它们各自独立可测。
//   所以同时看见两边的那段逻辑，只能待在两者**之上**，正如 App 层一直以来的位置；
//   区别是本包不碰任何 UI，于是能跟着 `make test` 跑**秒级**单测，不必等模拟器。
//
// 代价（已知并接受）：包拓扑 4 → 5，须同步 TECH_SPEC §2.2 模块表与 AGENTS.md §3 包边界；
// App 层只剩 `ASWebAuthenticationSession` 的胶水（系统 API，无逻辑可测）。
let package = Package(
    name: "GitDuoAuth",
    platforms: [.iOS("27.0"), .macOS("15.0")],
    products: [
        .library(name: "GitDuoAuth", targets: ["GitDuoAuth"])
    ],
    dependencies: [
        .package(path: "../GitHubAPI"),
        .package(path: "../GitDuoCore")
    ],
    targets: [
        .target(
            name: "GitDuoAuth",
            dependencies: [
                .product(name: "GitHubAPI", package: "GitHubAPI"),
                .product(name: "GitDuoCore", package: "GitDuoCore")
            ]
        ),
        .testTarget(
            name: "GitDuoAuthTests",
            dependencies: [
                "GitDuoAuth",
                .product(name: "GitDuoCore", package: "GitDuoCore")
            ]
        )
    ]
)
