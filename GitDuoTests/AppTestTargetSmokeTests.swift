import Foundation
import Testing

@testable import GitDuo

/// **阶段 1 的冒烟测试** —— 唯一目的是证明 T1 的闭环真的通了。
///
/// ⚠️ 它**不**测任何业务逻辑（那是阶段 2 的事）。它在证据链上的位置只有两条：
///
/// 1. `@testable import GitDuo` 能编译且能引用到**内部**类型
///    ⇒ 证明 Debug 的 `ENABLE_TESTABILITY = YES` 对 App target 生效
///    （否则这里根本引不到 `Route`）。
/// 2. `Bundle.main` 是宿主 App
///    ⇒ 证明 `TEST_HOST` 已挂上、测试确实跑在 **App 进程**里
///    （不是被当成一个独立进程；这是 `@testable import` 一个 application 的前提）。
///
/// 计划与背景：`.ai/prompts/T1-app-layer-test-target-plan.md`
///
/// ## ⚠️ 为什么整块标 `@MainActor`（阶段 1 实测得出的硬结论）
///
/// `project.yml` 的项目级设置 `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` 会让
/// **App 层每个类型连同它的一致性（conformance）都变成 MainActor 隔离**。
/// 于是下面这条断言里的 `==`（`Route: Equatable`）在 `#expect` 的**宏展开**
/// 里被当成 nonisolated 上下文使用，直接编译失败：
///
///     main actor-isolated conformance of 'Route' to 'Equatable'
///     cannot be used in nonisolated context
///
/// ⇒ **App 层测试的默认姿势是整块 `@MainActor`**。
/// 阶段 2 要测的 21 个 ViewModel **全部**是 `@MainActor`，同理。
@MainActor
@Suite struct AppTestTargetSmokeTests {

    /// `Route` 是 App target 的**内部**类型（`GitDuo/Navigation/Route.swift`，无 `public`）。
    /// 能引用到它 = `@testable import` 真的生效了。
    @Test func App层内部类型对测试可见() {
        #expect(Route.profile == Route.profile)
    }

    /// 宿主 App 的 bundle id 固定为 `com.gitduo.app`（`project.yml` 的
    /// `PRODUCT_BUNDLE_IDENTIFIER`）。这里若拿到的是测试 bundle 自己的 id，
    /// 说明 `TEST_HOST` 没挂上 —— 而那会让 `@testable import` 的另一半悄悄失效。
    @Test func 测试跑在宿主App进程里() {
        #expect(Bundle.main.bundleIdentifier == "com.gitduo.app")
    }
}
