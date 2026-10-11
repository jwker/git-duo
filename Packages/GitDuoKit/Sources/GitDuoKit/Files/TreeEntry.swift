import Foundation

/// 文件树的一行（PRD §3.2、TECH_SPEC §9.5）。
///
/// ## ⚠️ 2026-10-11：行副标题（「最近提交信息」）已整条删除
///
/// 它原先是"逐条补一次 `GET …/commits?path={p}&per_page=1`"换来的
/// —— 目录清单接口 `GET /repos/{o}/{r}/contents/{path}` 的返回项里
/// **一个提交字段都没有**（2026-10-07 实测；`git/trees` 同样没有，
/// GitHub 也没有任何批量接口能把它带出来），所以一个 30 项的目录
/// 就是 30 个额外请求（并发 4）。用户认为这点信息不值这个代价 ⇒ **决策 #49 作废**。
///
/// 于是本类型只剩"名字 / 路径 / 种类 / 大小 / SHA"五样，
/// 原型的 `f.msg` 在 App 里**有意不再画**（原型本身按惯例不动）。
public struct TreeEntry: Sendable, Hashable, Identifiable {

    /// 条目名（不含路径）。⚠️ 面包屑与目录行显示的都是它，不是 `path`。
    public let name: String

    /// 仓库内**完整**路径（`docs/guide.md`）—— 进下一级、打开文件都用它。
    ///
    /// 与 `name` 分开存是有意的：只用 `name` 的话，在**子目录里**点一个文件时
    /// 得先知道"现在在哪一层"，而那个信息在导航栈里、不在这一行上；
    /// 结果是"点文件打开的却是根目录里的同名文件"。
    public let path: RepoPath

    public let kind: Kind

    /// 字节数。**目录为 0**（`contents` 对目录不下发 `size`）。
    public let size: Int

    /// 该条目的 blob / tree SHA。⚠️ 编辑器保存时要用它（§9.6 的 `PUT …/contents/{path}`
    /// 以 `sha` 表示"更新"），所以不能因为本页只读就丢掉。
    public let sha: String

    /// `ForEach` 的键 —— 路径在仓库内唯一。
    public var id: String { path.raw }

    public init(
        name: String,
        path: RepoPath,
        kind: Kind,
        size: Int,
        sha: String
    ) {
        self.name = name
        self.path = path
        self.kind = kind
        self.size = size
        self.sha = sha
    }

    public enum Kind: Sendable, Hashable {

        /// 目录 —— 点击进下一级。
        case directory

        /// 普通文件 —— 点击进文件查看页（§4.5）。
        case file

        /// ⚠️ **原型没有这一档**（PRD §3.2 只写 `dir` / `file`），但 `contents` 的
        /// `type` 还会是 `symlink` / `submodule`：
        ///
        /// - `symlink` 的 `content` 是**链接目标那串文本**，不是文件内容 ——
        ///   当普通文件打开会显示出一行 `../foo/bar` 并让用户以为文件内容就是这个；
        /// - `submodule` 的 `size` 是 0、`sha` 是**另一个仓库的提交**，
        ///   点进去请求 contents 只会 404。
        ///
        /// 两者都归到这一档：行**照常显示**（形态与目录/文件一致），
        /// 但不可进入，点按给出一个跳网页端的出口。少列一档的代价是
        /// "这类条目在 App 里点不动、也没有解释"，而那正是原型不覆盖时不该编的东西。
        case unsupported

        /// 能不能点进去（目录进下一级；文件开文件页）。
        public var isNavigable: Bool {
            switch self {
            case .directory, .file: true
            case .unsupported: false
            }
        }
    }
}
