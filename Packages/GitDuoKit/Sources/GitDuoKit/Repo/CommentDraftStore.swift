import Foundation

/// 一条**评论草稿**（决策 #59、PRD §4.9 / §4.11）。
///
/// ## 键为什么是「仓库 + 编号」
///
/// 评论的归属对象就是这两样（`owner/name` + `#42`）。用别的形状都会出问题：
///
/// - **只用编号** ⇒ 两个仓库的 `#42` 是两条不同的讨论，草稿会**串到另一个仓库去**
///   （用户在 A 仓库写了一半、去 B 仓库看 `#42`，发现输入框里有别人的半句话）。
/// - **只用仓库** ⇒ 一个仓库里同时在写两个 Issue 的评论时互相覆盖。
///
/// ⚠️ Issue 与 PR **共用同一份编号空间**（GitHub 就是这么设计的：PR 是一种 Issue）
/// ⇒ 键里**不需要**再区分"Issue 还是 PR"，也不会撞车。
public struct CommentDraft: Sendable, Hashable, Codable {

    /// 仓库全名（`owner/name`）。
    public let fullName: String

    /// **仓库内**编号（那个 `#42`）。
    public let number: Int

    /// 草稿正文。
    public let body: String

    /// 保存时刻。用于排查（"这条是三天前写的"），也用于落盘的确定性排序。
    public let savedAt: Date

    public init(fullName: String, number: Int, body: String, savedAt: Date) {
        self.fullName = fullName
        self.number = number
        self.body = body
        self.savedAt = savedAt
    }
}

// MARK: - 落盘编解码

extension CommentDraft {

    /// 落盘用的编码（整份当成一个数组，TECH_SPEC §7.1）。
    ///
    /// ⚠️ 同 `StarSnapshot.encodeList` 的理由：它天然是一个整体（登出时整份清掉、
    /// 读到坏的整份作废），拆成 N 条键反而要处理"清了一半"的中间态。
    public static func encodeList(_ drafts: [CommentDraft]) -> Data? {
        try? JSONEncoder().encode(drafts)
    }

    /// 解码；解不出返回空数组。
    ///
    /// ⚠️ **不抛错、不保留半份**：草稿是**用户还没发布的东西**，
    /// 一份读出半截的草稿比没有草稿更坏 —— 用户会以为是自己写漏了，
    /// 然后在那个基础上继续写并发布出去。整份作废至少是"干净地回到没写过的状态"。
    public static func decodeList(from data: Data) -> [CommentDraft] {
        (try? JSONDecoder().decode([CommentDraft].self, from: data)) ?? []
    }
}

/// 评论草稿的存储（决策 #59）。
///
/// ## 为什么草稿必须**落盘**（而不是只留内存）
///
/// PRD §4.9 的提示条逐字承诺：`⚠ 发送失败：网络不可用。草稿已保留，可重试。`
/// 而"草稿已保留"要成立，就必须**退出页面再进来草稿仍在** ——
/// 只留内存的话，用户返回上一页再点回来，那句承诺当场落空，
/// 而屏幕上看起来一切正常（输入框是空的，像自己没写过）。
///
/// ## ⚠️ 它是**账号绑定数据**：`signOut()` 必须 `clear()`
///
/// 草稿里可能有**还没发布的正文**（一段私事、一个未公开的漏洞描述）。
/// 留在设备上、换个账号登录还能被读出来，是一次真实的泄露。
/// §3.6 的 `signOut()` 第 ③ 步（清账号数据）里必须有它。
///
/// ## ⚠️ 与前三个 store 一样，**落盘实现在 App 组合根**，不在本包
///
/// 本包只定义"该是什么行为"（含一份内存参照实现供测试与预览）。
/// 理由见 `RecentVisitStore` 的类型说明。
///
/// ## ⚠️ 已知缺口，待评审：**没有条数上限**
///
/// 「最近访问」裁到 6 条、「最近搜索」裁到 8 条，本 store **不裁** ——
/// 规格（PRD §4.9 / §4.11、决策 #59）没有给上限，而"加一个数字"就是替用户拍板
/// （同 `BranchMemoryStore` 那条已知缺口的口径）。
///
/// ⚠️ 但这份缺口**比分支记忆那份更值得尽早定**：分支名是几十字节的短串，
/// 而草稿是**用户正文**，可以很长。现状下唯一能自动消掉条目的是
/// "内容变空即删"（见 `save`）与登出时的 `clear()`。
public protocol CommentDraftStore: Sendable {

    /// 读一条草稿；没有则 `nil`。
    func draft(fullName: String, number: Int) async -> CommentDraft?

    /// 存一条草稿。
    ///
    /// ⚠️ **正文为空（或只有空白）⇒ 删除该条**，而不是存一条空草稿：
    /// 用户把输入框删干净、然后离开页面，是很常见的动作 ——
    /// 那不是一个"空草稿"，那是"不写了"。存下来的话，下次进来会看到一个空输入框
    /// （与没有草稿长得一样），却在磁盘上留着一条**他以为自己已经放弃的内容**的痕迹。
    func save(fullName: String, number: Int, body: String, at date: Date) async

    /// 删掉一条草稿（**发送成功后**必须调用）。
    ///
    /// ⚠️ 发送成功却不清草稿的下场：用户下次进这个 Issue，输入框里赫然是
    /// **上一次已经发出去的那段话** —— 他很可能就此又发一遍。
    func discard(fullName: String, number: Int) async

    /// 清空全部（登出、以及"清账号数据"那一步）。
    func clear() async
}

/// 内存实现 —— 单测与预览用；App 层用落盘实现。
public actor InMemoryCommentDraftStore: CommentDraftStore {

    /// 键用 `fullName` + 编号的字符串形态（`owner/name#42`）——
    /// 仓库全名里不可能出现 `#`（GitHub 的仓库名字符集不含它），所以拼起来不会有歧义。
    private var storage: [String: CommentDraft]

    public init(seed: [CommentDraft] = []) {
        var initial: [String: CommentDraft] = [:]
        for draft in seed {
            initial[Self.key(fullName: draft.fullName, number: draft.number)] = draft
        }
        self.storage = initial
    }

    public func draft(fullName: String, number: Int) async -> CommentDraft? {
        storage[Self.key(fullName: fullName, number: number)]
    }

    public func save(fullName: String, number: Int, body: String, at date: Date) async {
        let key = Self.key(fullName: fullName, number: number)
        // 同 `PostIssueComment.canSend`：只有空白视为空。
        guard PostIssueComment.canSend(body) else {
            storage[key] = nil
            return
        }
        storage[key] = CommentDraft(fullName: fullName, number: number, body: body, savedAt: date)
    }

    public func discard(fullName: String, number: Int) async {
        storage[Self.key(fullName: fullName, number: number)] = nil
    }

    public func clear() async {
        storage = [:]
    }

    /// 全部草稿，**按（仓库全名，编号）升序**。
    ///
    /// 落盘实现要用它把整份草稿写出去（协议上没有"列出全部"，
    /// 因为领域层不需要这个能力 —— 但"存一份东西"需要一个确定的顺序）。
    ///
    /// ⚠️ 排序不是洁癖：`Dictionary` 的迭代顺序**每次运行都可能不同**，
    /// 直接写出去会让"同一份草稿两次落盘得到两个不同字节序列"
    /// （同 `InMemoryStarSnapshotStore.allSnapshots` 的说明）。
    public func allDrafts() async -> [CommentDraft] {
        storage.values.sorted {
            $0.fullName == $1.fullName ? $0.number < $1.number : $0.fullName < $1.fullName
        }
    }

    private static func key(fullName: String, number: Int) -> String {
        "\(fullName)#\(number)"
    }
}
