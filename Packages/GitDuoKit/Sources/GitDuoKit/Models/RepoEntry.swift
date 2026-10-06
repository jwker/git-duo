import Foundation

/// 点开一个仓库后进入哪种界面（PRD §1 的核心心智：可写工作台 / 只读阅览室）。
///
/// ## 为什么要有这个类型，而不是直接返回路由
///
/// 领域层**不得认识路由**（`Route` 属表现层 + 导航层）。这里只回答**产品问题**
/// ——"这个仓库对我可写吗"，由 `RouteView` / 列表页把它翻成 `.repoDetail` 或
/// `.exploreRepoDetail`。这样"可写性怎么判"只有一处、"路由怎么走"只有一处，
/// 两者都能单独测。
public enum RepoEntry: Sendable, Hashable {
    /// 可写工作台：浏览代码、编辑文件、提交、管理分支、处理 Issue 与 PR。
    case writable
    /// 只读阅览室：仅浏览 + Star / Watch / Fork / 收藏，无写操作。
    case readOnly
}

extension Repository {

    /// 进入方式**唯一由 `canWrite` 派生**。
    ///
    /// ⚠️ 全项目**禁止**任何地方再写一次类似 `fullName.hasPrefix("my-git/")` 的判断。
    ///    原型里就是这么写的（`scripts/05-repo.js:13`），但那是**无后端可用的演示简化**：
    ///    真实产品里"自己的仓库"= 用户拥有写权限的**任意**仓库，
    ///    组织仓库、别人邀请你协作的仓库都算（TECH_SPEC §8.1）。
    public var entry: RepoEntry { canWrite ? .writable : .readOnly }
}
