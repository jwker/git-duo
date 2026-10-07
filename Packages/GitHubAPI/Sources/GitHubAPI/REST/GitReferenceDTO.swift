import Foundation

/// 创建 / 删除分支用到的 Git 引用 —— `POST /repos/{owner}/{repo}/git/refs`（TECH_SPEC §9.7.1）。
///
/// ## ⚠️ 删除分支**没有**返回体
///
/// `DELETE /git/refs/heads/{branch}` 成功时是 **204 No Content**（空 body），
/// 所以那一步的返回值是 `Void`，不是本类型。本类型只描述**创建**的响应。
///
/// ## 请求体形状与它不同（别照抄）
///
/// 请求体是 `{"ref": "refs/heads/feature", "sha": "…"}` —— **没有** `object` 这一层；
/// 响应却把 sha 包进 `object`。本包用 `JSONSerialization` 手写请求体
/// （见 `GitHubRepoBranchEndpoint`），所以这个不对称不会表现为"编码失败"，
/// 但它是这个端点最容易写错的地方。
public struct GitReferenceDTO: Sendable, Equatable, Decodable {

    /// 完整引用名（`refs/heads/feature/x`），**不是**分支名。
    ///
    /// ⚠️ 注意带 `refs/heads/` 前缀：把它直接当分支名用（拿去请求 contents 的 `ref=`）
    /// 会被服务端当成一个不存在的引用而 404。
    public let ref: String

    /// 引用指向的对象。
    public let object: Reference

    public struct Reference: Sendable, Equatable, Decodable {

        public let sha: String

        /// `commit` / `tag` / `tree` / `blob`。本切片只创建分支 ⇒ 恒为 `commit`。
        public let type: String?

        public init(sha: String, type: String? = nil) {
            self.sha = sha
            self.type = type
        }
    }

    public init(ref: String, object: Reference) {
        self.ref = ref
        self.object = object
    }

    /// 从 `refs/heads/feature/x` 取回 `feature/x`。
    ///
    /// 拼错前缀的后果是"新建完分支后跳过去却 404"，所以剥前缀这件事有**一个实现**、
    /// 且有测试；不要在调用点各写一遍 `dropFirst("refs/heads/".count)`。
    public var shortName: String? {
        let prefix = "refs/heads/"
        guard ref.hasPrefix(prefix) else { return nil }
        return String(ref.dropFirst(prefix.count))
    }

    // ⚠️ `node_id` / `url` 有意不收（没有任何界面要用）。
}

/// 合并分支的结果 —— `POST /repos/{owner}/{repo}/merges`（TECH_SPEC §9.7.1、决策 #52）。
///
/// ## ⚠️ 这个端点有**三种**结局，其中两种都是"成功"
///
/// | HTTP | 含义 | 本包的表现 |
/// |---|---|---|
/// | **201** | 合并成功 | `.merged(MergeResultDTO)` |
/// | **204** | **没有东西可合**（`head` 已经合进 `base` 了） | `.nothingToMerge` |
/// | 409 | 冲突 | 抛 `GitHubError`（引导用户去网页端） |
///
/// 把 204 当成失败是本端点最容易犯的错：它**不是**错误 —— 用户想要的结果
/// （两边一致）本来就成立。显示成"合并失败"会让用户去重复点，而每次都是 204。
/// 也正因为如此，本端点的返回类型是 `MergeOutcome` 而不是 `MergeResultDTO`。
public struct MergeResultDTO: Sendable, Equatable, Decodable {

    /// 合并产生的提交 SHA。
    public let sha: String

    /// 服务端恒为 `true`（201 才走这条路径）。
    public let merged: Bool

    /// 服务端的话术，例如 `Merge made by the 'recursive' strategy.`
    ///
    /// ⚠️ **不进界面**：它是英文、且是服务端内部策略的措辞。
    /// 合并成功后的提示文案走 `BranchCopy`（领域层的可测文案），不用这个字段。
    /// 保留它是为了日志与测试能看出"服务端到底做了什么"。
    public let message: String?

    public init(sha: String, merged: Bool, message: String? = nil) {
        self.sha = sha
        self.merged = merged
        self.message = message
    }
}

/// 合并的三种结局（见 `MergeResultDTO` 的说明）。
public enum MergeOutcome: Sendable, Equatable {

    /// 201 —— 真的合了，并产生了这个提交。
    case merged(MergeResultDTO)

    /// 204 —— **没有东西可合**。这不是失败：`head` 已经合进 `base` 了。
    ///
    /// 之所以不把它折成 `nil`：`nil` 在调用方读起来像"没有结果 / 出错了"，
    /// 而这里的语义是**确凿的正面答案**，要给出"两边已经一致"的提示。
    case nothingToMerge
}
