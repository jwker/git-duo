// swift-tools-version: 6.0
import PackageDescription

// GitDuoDesign —— 设计令牌、通用组件、Liquid Glass 封装。
// 依据：TECH_SPEC §2.2、§10.7。职责是把「颜色 / 字号 / 间距 / 圆角 / 玻璃用法」收敛到一处，
// 业务代码不得直接写魔法值或 `.glassEffect`。
//
// 说明：同时声明 macOS 平台**仅为在宿主机上跑 `swift test`**（宿主是 macOS），
// 不代表产品支持 macOS —— 产品形态是纯 iPhone（决策 #2）。
let package = Package(
    name: "GitDuoDesign",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "GitDuoDesign", targets: ["GitDuoDesign"])
    ],
    dependencies: [
        .package(path: "../GitDuoCore")
    ],
    targets: [
        .target(name: "GitDuoDesign", dependencies: ["GitDuoCore"]),
        .testTarget(name: "GitDuoDesignTests", dependencies: ["GitDuoDesign"])
    ]
)
