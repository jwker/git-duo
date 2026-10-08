// swift-tools-version: 6.0
import PackageDescription

// GitDuoKit —— **领域层**：领域模型、Mapper、业务判定（可写性 / 分段过滤）、分页状态机、取数仓储。
// 依据：TECH_SPEC §2.1（领域层：Repository · UseCase · Domain Model）与 §2.2 包表。
//
// ## 为什么这一层必须单独成包（决策 #34，2026-10-06）
//
// 因为 **App target 没有测试 target**（`project.yml` 里 `GitDuo` 只有 application），
// 而这一层的逻辑恰恰是最需要被测试钉住的部分：
// 「可写性判定」错了，用户会点进编辑器、改完文件、提交时才发现 403；
// 「分页状态机」错了，会出现重复行、永远 loading、或"加载更多"点了没反应。
// 把这类逻辑放进没有测试的地方，等于让它们的正确性只靠人工点击来保证。
//
// ## 依赖方向
//
// `GitDuoKit → GitHubAPI（网络）+ GitDuoCore（本地基础设施）`，与 §2.1 的三层同向：
// 领域层可以使用数据层，**数据层不得反向引用领域层** ——
// 所以 `GitHubAPI` 里不存在任何 `Repository`（领域模型）类型，只有 `RepositoryDTO`。
//
// ⚠️ 本包**不得** import SwiftUI（§2.1：领域层不得出现 SwiftUI 类型）。
//    需要颜色/字号时由表现层去查 `GitDuoDesign`，本包只出"是什么"，不出"长什么样"。
let package = Package(
    name: "GitDuoKit",
    platforms: [.iOS("27.0"), .macOS("15.0")],
    products: [
        .library(name: "GitDuoKit", targets: ["GitDuoKit"])
    ],
    dependencies: [
        .package(path: "../GitHubAPI"),
        .package(path: "../GitDuoCore")
    ],
    targets: [
        .target(
            name: "GitDuoKit",
            dependencies: [
                .product(name: "GitHubAPI", package: "GitHubAPI"),
                .product(name: "GitDuoCore", package: "GitDuoCore")
            ]
        ),
        .testTarget(
            name: "GitDuoKitTests",
            dependencies: [
                "GitDuoKit",
                .product(name: "GitHubAPI", package: "GitHubAPI"),
                // ⚠️ 测试也会直接 `import GitDuoCore` —— 断言"某处的相对时间走的是
                //    `RelativeTime` 那一套分档"时要用它来对表（切片 7.4：
                //    `IssueComment.timeLabel(now:)` 与 `IssueDetail.bodyTimeLabel(now:)`）。
                //    不声明的话那个 import 编译不过；而改写成断言字面量
                //    会把测试与 `RelativeTime` 的措辞绑死。
                .product(name: "GitDuoCore", package: "GitDuoCore")
            ]
        )
    ]
)
