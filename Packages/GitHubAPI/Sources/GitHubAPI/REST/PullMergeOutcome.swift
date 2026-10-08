import Foundation

/// 合并 PR 的三种方式 —— `PUT /repos/{owner}/{repo}/pulls/{n}/merge` 的 `merge_method`
/// （PRD §5.3、TECH_SPEC §9.9）。
///
/// ## 为什么这个可以枚举化，而 `state` 不行
///
/// `IssueDTO.state` 保留 `String` 是因为那是个**仍在演进**的取值集合（GitHub 后来又加了
/// `state_reason`）—— 枚举化会让"某天多一个取值"表现为整页解码失败。
/// 合并方式不是那种东西：官方 API 固定就这三种（`merge` / `squash` / `rebase`），
/// 而且**是请求参数、不是响应字段** —— 写成枚举的价值在于调用方拼不出错的值。
///
/// ## ⚠️ 界面文案**不在这里**
///
/// 「Merge commit」「保留全部分支提交历史」这些是**产品文案**（PRD §5.3 逐字给了），
/// 按"文案要提为可测领域数据"的规矩落在 `GitDuoKit` 的 `PullMergeCopy`。
/// 本类型只负责 API 词汇。
public enum PullMergeMethod: String, Sendable, Hashable, CaseIterable {

    /// 产生一个合并提交，保留全部分支提交历史。
    case merge

    /// 压成一个提交（历史更干净）。
    case squash

    /// 线性历史，不含合并节点。
    case rebase
}

/// 合并 PR 的结果体 —— **200** 时的响应。
///
/// ## 为什么不复用分支合并的 `MergeResultDTO`
///
/// 两个端点的响应长得很像（都是 `sha` / `merged` / `message`），但**可空性不同**：
/// 分支合并的 201 路径上 `sha` 必然存在（`MergeResultDTO.sha` 是 `String`），
/// 而 PR 合并的 200 有可能带 `merged: false`（见 `PullMergeOutcome` 的说明）——
/// 那时 `sha` 可能缺席。共用一个类型会让"sha 有没有"成为一件要靠调用点记着的事。
public struct PullMergeResultDTO: Sendable, Equatable, Decodable {

    /// 合并产生的提交 SHA。**可以是 `null`**（`merged: false` 时可能不给）。
    public let sha: String?

    /// 服务端说这次到底合没合。
    ///
    /// ⚠️ **不能因为 HTTP 是 200 就当成成功** —— 见 `PullMergeOutcome` 对"200 + `merged:false`"
    /// 那一档的处理。这是本端点与分支合并端点最不一样的地方。
    public let merged: Bool

    /// 服务端的话术。⚠️ **不进界面**（英文 + 内部措辞），理由同 `MergeResultDTO.message`。
    public let message: String?

    public init(sha: String? = nil, merged: Bool, message: String? = nil) {
        self.sha = sha
        self.merged = merged
        self.message = message
    }
}

/// 合并 PR 的结局 —— `PUT /repos/{owner}/{repo}/pulls/{n}/merge`（TECH_SPEC §9.9）。
///
/// ## 三档，且**必须分开说**
///
/// §9.9 明写"三种都要分开说，**不能**折成一句『合并失败』"：
///
/// | HTTP | 含义 | 本包的表现 |
/// |---|---|---|
/// | **200** 且 `merged == true` | 真的合了 | `.merged(PullMergeResultDTO)` |
/// | **405** | **这个 PR 不能被合并**（已经合过了 / 是 draft / 有冲突） | `.notMergeable` |
/// | 409 | 冲突（服务端另有话术） | 抛 `GitHubError`（引导去网页端） |
/// | 403 / 404 | 没权限 / 不存在（GitHub 把两者混同） | 抛 `GitHubError` |
///
/// ## ⚠️ 为什么多了一条"200 且 `merged == false` ⇒ `.notMergeable`"
///
/// 原文档只列了 405 那一档，但 200 的响应体里带着 `merged` 这个布尔值 ——
/// 它**有可能是 `false`**（服务端用它表达"请求收到了，但没合"）。
/// 只看 HTTP 状态码就把这种情况报成"已合并"，是**对着屏幕说假话**：
/// 界面会立刻把状态置成"已合并"、把讨论锁上，而仓库里其实什么都没发生。
/// ⇒ 判据取**响应体里的 `merged`**，与 405 合并成同一档（对用户是同一句话）。
///
/// ⚠️ 这也正是 `PullMergeOutcome` 存在的理由：返回类型必须是"结局"而不是"结果体"，
/// 否则调用方迟早会写成"拿到了 `PullMergeResultDTO` 就算成功"。
public enum PullMergeOutcome: Sendable, Equatable {

    /// 真的合了。
    case merged(PullMergeResultDTO)

    /// **这个 PR 不能被合并**。
    ///
    /// 三种成因（已合并过 / draft / 有冲突）在服务端是同一档，
    /// 这里**不细分** —— 客户端分不出来（`mergeable` 那个字段可能已过期，故不取，见 `PullDetailDTO`），
    /// 编一个成因就是猜。界面按 §5.3 的提示引导去网页端。
    case notMergeable
}
