import Foundation

/// 提交列表（§4.4 分区四）与提交详情页（§4.7）的可见文案。
public enum CommitCopy {

    // MARK: - §4.7 操作区

    /// Revert 按钮（原型 `SCR.commitDetail` 逐字，含 `↩`）。
    public static let revertAction = "↩ Revert 此提交（跳转网页端）"

    /// 点 Revert 后的提示（PRD §4.7 逐字）。
    ///
    /// ⚠️ GitHub 的公开 API **没有回滚端点**（网页端的 Revert 是服务端内部能力），
    /// 客户端自行实现要逐层构造反向提交、且合并提交存在主线歧义 ⇒ 本期不做
    /// （§9.7.3）。所以这句话不是"没做"，是**明确告知出口在哪**。
    public static let revertToast = "Revert 需在 GitHub 网页端完成"

    /// 他人仓库的页脚（原型逐字）。
    public static let readOnlyFooter = "只读浏览 · 他人仓库提交"

    // MARK: - Diff 卡片

    /// 二进制文件：服务端不给 `patch`（§11.2 的 `Binary files … differ`）。
    public static let binaryDiffNotice = "二进制文件 · 不支持 diff 预览"

    /// 有 `patch` 字段但服务端没给内容（diff 太大被省略）。
    ///
    /// ⚠️ 与上一条**必须分开**：同一句"看不了"会让一个 50 行的文本改动
    /// 被说成"二进制文件"，而用户明明能在网页端看到它的 diff。
    public static let oversizedDiffNotice = "diff 较大，请在 GitHub 网页端查看"

    /// 折叠状态下 diff 卡片的读屏提示（§11.2：可折叠）。
    public static func diffToggleAccessibilityLabel(file: String, isExpanded: Bool) -> String {
        isExpanded ? "收起 \(file) 的改动" : "展开 \(file) 的改动"
    }

    // MARK: - 空态

    /// 提交列表为空。
    ///
    /// ⚠️ 它与"加载中"不是一回事 —— 空仓库（或刚初始化、一次都没提交的仓库）
    /// 在 §4.4 的分区四会落到这里，而一个转圈不动的骨架屏会让用户以为网络卡了。
    public static let emptyTitle = "还没有提交"

    public static let emptyHint = "这个仓库还没有任何提交记录"

    /// 提交详情里 `files` 为空（服务端没下发改动列表）时的说明。
    public static let noFilesNotice = "这个提交没有文件改动"
}
