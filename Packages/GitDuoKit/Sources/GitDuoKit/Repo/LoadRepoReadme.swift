import Foundation
import GitHubAPI

/// 仓库级 README 的取数 —— **与目录浏览无关**的那一条。
///
/// ## ⚠️ 2026-10-14：它是从 `LoadRepoTree` 里**搬出来**的
///
/// 在那之前 README 是**寄生**在目录取数里的：`LoadRepoTree.fetch` 只在根目录
/// 多问一次 `readme` 端点（与 `contents` 并发）。它跟着目录走，只因为"仓库根"
/// 这个位置顺带有了它 —— 于是**任何想画 README 的页面都必须先有一个目录会话**
/// （`RepoTreeSession`），连带背上分支列表、分支记忆、两段式解析那一整套。
///
/// 现在画它的是两个**首页**（§4.4 自己的仓库 / §4.13 他人仓库），
/// 而两页都已经有头部在手 ⇒ `RepositoryDetail.defaultBranch` 就是权威的 `ref`。
/// 本件因此**不做分支解析、不读分支记忆、不发分支列表请求**：一次请求，一个 `ref`。
///
/// ## ⚠️ 有意如此：README 恒用**默认分支**
///
/// 代码页可能正浏览记忆里的另一条分支（§3.10），而本件恒用默认分支 ——
/// "仓库简介"用默认分支读是自然的，且这样两个首页都不必引入分支记忆那套依赖。
///
/// ⚠️ **代价如实记着**：用户切到 `dev` 之后回到首页，README 仍是 `main` 的。
/// 这不是漏了 —— 要跟着变就得把分支解析（决策 #55 那一整套规则）也搬过来，
/// 而那正是本件存在的理由（让 README 不再依赖那套东西）。
public struct LoadRepoReadme: Sendable {

    private let contents: any RepoContentsDataSource

    public init(contents: any RepoContentsDataSource) {
        self.contents = contents
    }

    /// 取这个仓库的 README（含**已经解析好的块**）。
    ///
    /// - Parameter ref: 用哪条分支 —— 调用方给头部那份 `defaultBranch`
    ///   （见类型说明：本件有意不解析记忆值）。
    ///
    /// - Returns: `nil` = 这个仓库没有 README。⚠️ 它**不是错误** ——
    ///   `readme` 端点的 404 在端点那一层已被翻译成 `nil`
    ///   （§9.5：唯一允许吞 404 的一处），所以这里不必再判。
    ///
    /// - Throws: 其余错误**照常抛**（网络 / 限流 / 鉴权）——
    ///   调用方按**块级失败**处置：一块 README 取不到不该掀翻整个首页。
    public func load(fullName: String, ref: String) async throws -> MarkdownDocument? {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)

        let source = try await contents.readme(owner: owner, repo: repo, ref: ref)

        // ⚠️ 解析（`MarkdownParser`，§11.1）在**这里**做一次，不在视图的 `body` 里
        //    （理由同 `LoadRepoTree`：放进 body 是每次重绘重扫全文，而结果每次都相同）。
        return source.map(MarkdownDocument.init)
    }
}
