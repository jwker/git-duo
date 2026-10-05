// swift-tools-version: 6.0
import PackageDescription

// GitHubAPI —— REST / GraphQL 客户端、DTO、分页、ETag 缓存、限流、错误模型、OAuth 授权流程。
// 依据：TECH_SPEC §2.2。硬约束：只依赖 Foundation / CryptoKit，**零第三方依赖**（决策 #12）。
let package = Package(
    name: "GitHubAPI",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "GitHubAPI", targets: ["GitHubAPI"])
    ],
    targets: [
        .target(name: "GitHubAPI"),
        .testTarget(name: "GitHubAPITests", dependencies: ["GitHubAPI"])
    ]
)
