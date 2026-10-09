import Foundation

/// Issue 侧三屏的可见文案：Issue 详情（PRD §4.9）· 新建 Issue（§4.10）· 标签弹层（§5.2）。
///
/// ## 为什么合在一个类型里
///
/// 三屏是**一条链**：仓库详情 Issues 段 →（＋ 新建 Issue）→ 新建页 →（＋ 标签 / 新建）→ 标签弹层。
/// 标签弹层**只**从新建页进得来（§5.2 没有第二个入口），所以它没有独立的生命周期；
/// 拆成三个类型只会让"改一句词要动三个文件"。
/// （同 `CommitCopy` 的做法 —— 它一个类型覆盖了提交列表、提交详情与 diff 卡片。）
///
/// ## 文案来源的优先级（`AGENTS.md §1`：**原型 > TECH_SPEC > PRD**）
///
/// 绝大多数句子逐字取自原型（`scripts/06-files.js` 的 `SCR.issueDetail`、
/// `scripts/07-issues.js` 的 `SCR.newIssue` / `openLabelSheet`）。
/// 少数几句原型给不出（它的演示数据是硬编码的单 token），按 PRD 的写法补 ——
/// **每一处都在下面逐个注明了**，不要凭印象改。
public enum IssueCopy {

    // MARK: - §4.9 Issue 详情：头部

    /// 开放状态下的说明（原型 `06-files.js:118` 逐字）。
    public static let openNote = "该 Issue 仍然开放"

    /// 已关闭状态下的说明：`已于 {时间}关闭`（PRD §4.9 第 1 条的写法）。
    ///
    /// ⚠️ **原型与 PRD 的间距一致**（原型硬编码 `已于 3 天前关闭`、PRD 写 `已于 {时间}关闭`）
    /// ⇒ 取 `已于` + 空格 + 相对时间 + `关闭`。
    public static func closedNote(relativeTime: String) -> String {
        "已于 \(relativeTime)关闭"
    }

    /// 已关闭但**拿不到关闭时间**时的说明。
    ///
    /// ⚠️ **自拟（规格未给）**：`IssueDetailDTO.closedAt` 是可空的
    /// （官方 schema 里 nullable），而原型与 PRD 都假定它有值。
    /// 这时**不能**退回 `closedNote(relativeTime: "")` —— 那会渲染出 `已于 关闭`，
    /// 读起来像"关闭于某个没显示出来的时间"。只说状态、不编时间。
    public static let closedNoteWithoutTime = "已关闭"

    /// 头部元信息：`#42 · my-git/gitduo · 由 reviewer-a 创建于 昨天`。
    ///
    /// 原型是 `#${n} · my-git/gitduo · 由 reviewer-a 创建于昨天` —— 它那句里的
    /// `昨天` 是**硬编码的单 token**（没有空格也不显眼）。真正的相对时间会是
    /// `2 小时前` 这种多 token 形式，照原型拼会出来 `创建于2 小时前`。
    /// PRD §4.9 写的是 `由 {创建者} 创建于 {时间}`（两侧都有空格）⇒ **取 PRD 的写法**，
    /// 这是原型"给不出"而不是"给得不一致"。
    ///
    /// ⚠️ 作者拿不到时**整段去掉**（同 `IssueRow.metaLabel`）：拼出 `由  创建于 …`
    /// 比少一句更糟。
    public static func metaLabel(
        number: Int,
        fullName: String,
        authorLogin: String?,
        relativeTime: String? = nil
    ) -> String {
        var parts = ["#\(number)", fullName]
        if let authorLogin, !authorLogin.isEmpty {
            if let relativeTime, !relativeTime.isEmpty {
                parts.append("由 \(authorLogin) 创建于 \(relativeTime)")
            } else {
                // 拿不到创建时间就说"由谁创建"，不编一个时间。
                parts.append("由 \(authorLogin) 创建")
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - §4.9：评论输入区

    /// 输入框占位（原型 `06-files.js:137` 逐字）。
    ///
    /// ⚠️ PR 页那一处**不一样**（`写评论…`，没有括号那句 —— 原型逐字如此），
    /// 所以**占位留在各自的页面文案里**；只有两页相同的才上提到 `ConversationCopy`。
    public static let commentPlaceholder = "写评论… (Markdown 支持)"

    // 「发送」按钮的文案**不在这里**：两页逐字相同（原型两处都是 `发送`），
    // 落在 `ConversationCopy.sendAction` —— 与下面那三句同一条理由。

    // MARK: - 提示

    // ⚠️ 「先写点内容再发送」「评论已发送」「发送失败提示条」这三句**不在这里** ——
    //    它们是 Issue 与 PR 两个页面共用的，落在 `ConversationCopy`。
    //    在这里再写一遍的下场是两处会渐渐不一致，而漏掉一处不会报错。

    // MARK: - §4.10 新建 Issue

    /// 导航栏标题（原型 `SCR.newIssue.inline` 逐字）。
    public static let newIssueTitle = "新建 Issue"

    /// 目标仓库说明行（原型 `07-issues.js:14` 逐字）。
    public static func targetRepoLine(fullName: String) -> String {
        "目标仓库 · \(fullName)"
    }

    /// 标题输入框占位（原型逐字）。
    public static let titlePlaceholder = "标题"

    /// 正文输入框占位（原型逐字，含中文省略号 `…`）。
    public static let bodyPlaceholder = "描述（支持 Markdown）…"

    /// 「标签」分区标题（原型逐字）。
    public static let labelsSectionTitle = "标签"

    /// 标签行末尾那个按钮（原型逐字，**全角 `＋`**）。
    public static let addLabelAction = "＋ 标签 / 新建"

    /// §4.10 标签行里点掉一颗胶囊会做什么（**读屏用**）。
    ///
    /// ⚠️ **规格未给**（原型只有视觉）。它与 `SelectedLabelRow.removeHint`
    /// （`双击取消这个标签筛选`）**不是同一句**，所以各写各的：
    /// §4.4 那一处去掉的是**筛选条件**，这里去掉的是**这条 Issue 要带的标签** ——
    /// 一个说的是"不按它筛了"，一个说的是"发出去时别带上它"。
    /// 共用一句会让其中一处说错（而读屏用户听到的是**反的动作**）。
    public static let removeLabelHint = "双击移除这个标签"

    /// 提交按钮（原型逐字）。
    public static let submitAction = "提交 Issue"

    /// 标题为空时用的**占位标题**（PRD §4.10「标题为空时使用占位标题」；原型 `07-issues.js:70` 逐字）。
    ///
    /// ⚠️ 它是**发出去的内容**，不只是界面上的话：GitHub 上那条 Issue 的标题就是它。
    /// 所以它属于领域层（`NewIssueDraft.effectiveTitle`），不能散在视图里。
    public static let placeholderTitle = "新 Issue"

    /// 建成功后的提示：`已创建 Issue #43 · “原型反馈：Issues 不可点开” · 标签 3 个`。
    ///
    /// 原型 `07-issues.js:71` 逐字（含 `“”`），其中 ` · 标签 N 个` **只在有标签时出现**
    /// —— 原型写的是 `${niLabels.length ? ` · 标签 ${niLabels.length} 个` : ''}`。
    /// 无标签时缀一句 `标签 0 个` 是多余的坏消息。
    public static func createdToast(number: Int, title: String, labelCount: Int) -> String {
        var text = "已创建 Issue #\(number) · “\(title)”"
        if labelCount > 0 { text += " · 标签 \(labelCount) 个" }
        return text
    }

    // MARK: - §5.2 标签选择 / 新建弹层

    /// 弹层上段标题：`选择标签 · 5 个`（原型 `07-issues.js:35` 逐字）。
    ///
    /// ⚠️ 那个数是**本地已知的标签条数**（`LabelCatalog` 取回的那批），不是服务端总数 ——
    /// 一页取 100 条、还有下一页时它只是下界（同 `BranchList.hasMore` 的口径）。
    public static func labelSheetTitle(count: Int) -> String {
        "选择标签 · \(count) 个"
    }

    /// 标签库**还没取回来**（或取失败）时的上段标题 —— **不带计数**。
    ///
    /// ⚠️ **规格未给**（自拟）：原型那份标签是静态数组，`REPO_LABELS.length` 永远算得出来，
    /// 所以 §5.2 与原型都只有带计数的那一句。这里必须多一句的理由是
    /// §8.5 末条那条铁律 ——「还没加载出来」与「确实一条都没有」是两件事：
    /// 还没取回来时写成 `选择标签 · 0 个` 等于告诉用户**这个仓库一个标签都没有**。
    ///
    /// ⚠️ 取到之后**成功与失败都用带计数的那一句吗？不是**：失败时手上没有计数，
    /// 继续用本句（失败块自己会说明原因）。
    public static let labelSheetTitlePending = "选择标签"

    /// 弹层下段标题（原型逐字）。
    public static let newLabelSectionTitle = "新建标签"

    /// 新标签名称输入框占位（原型逐字）。
    public static let newLabelPlaceholder = "标签名称，如 performance"

    /// 新建按钮（原型逐字）。
    public static let createLabelAction = "创建并选中"

    /// 弹层底部提示（原型 `07-issues.js:48` 逐字）。
    ///
    /// ⚠️ 它也含一句承诺：`新标签会保存到仓库标签列表，之后所有 Issue 都可直接选用`。
    /// 成立的前提是新建走 `POST /labels`（真的写进仓库），而不是只塞进本地那份选中集合。
    public static let labelSheetHint = "新标签会保存到仓库标签列表，之后所有 Issue 都可直接选用"

    /// 名称为空（PRD §7 逐字）。
    ///
    /// ⚠️ **载体是弹层内的一行，不是提示条**（决策 **#77**，2026-10-09）：
    /// 这一档**不关弹层**（用户还得接着打字），而提示条挂在根容器上、会被弹层整块盖住
    /// ⇒ 它画在「创建并选中」按钮**上方**。所以常量名里**不再带 `Toast`**
    /// —— 名字说"这是提示条"而它在弹层里，下一次读代码的人就会照 `Toast` 去改它。
    /// ⚠️ 同一段里另两句**照旧走提示条**（`duplicateLabelToast` / `labelCreatedToast`）：
    /// 那两档会**关掉弹层**，弹层不在的时候提示条看得见。
    public static let emptyLabelNameHint = "请先填写标签名称"

    /// 名称重复（PRD §7 逐字）。
    public static let duplicateLabelToast = "标签已存在，已为你选中"

    /// 弹层里点一颗**已选中**的标签会做什么（**读屏用**）。
    ///
    /// ⚠️ **规格未给**（§5.2 只有视觉：已选那一行右边一个绿色 `✓`），自拟。
    ///
    /// ⚠️ 它与 `RepoIssuesSectionCopy.cancelFilterHint`（`双击取消这个标签筛选`）
    /// **不是同一句**：那一行只会取消，而弹层里这一行**两向都能走**
    /// （已选 ⇒ 取消 / 未选 ⇒ 选上）⇒ 说"取消"会让读屏用户在**未选**的行上
    /// 听到一个反的动作。所以弹层里只在**已选**的行上挂这一句
    /// （未选的行不挂 hint），而它的措辞刻意只说"取消"、不说"筛选"。
    public static let selectedLabelHint = "已选中，双击取消"

    /// 新建成功（原型 `07-issues.js:67` 逐字，含 `“”`）。
    public static func labelCreatedToast(name: String) -> String {
        "已创建标签 “\(name)”"
    }

    // MARK: - §4.9 操作区（2026-10-09 起做；决策 #79）

    /// 操作区那颗「关闭 Issue」。
    ///
    /// ⚠️ **§5.18 弹层里的确认按钮也用这一串**：同一个动作、同一个词
    /// （PR 那边同理 —— 操作区那颗和弹层里那颗都叫 `合并 Pull Request`）。
    public static let closeAction = "关闭 Issue"

    /// 操作区那颗「重新打开 Issue」。
    ///
    /// ⚠️ **它不弹确认**（与关闭有意不对称）：重开只是把状态还原，没有可损失的东西
    /// （PRD §4.9 操作区末条）。所以这一串**只出现在页面那颗按钮上**。
    public static let reopenAction = "重新打开 Issue"

    /// 操作区**一颗按钮都没有**时的那一行提示（PRD §4.9 操作区表第一行）。
    ///
    /// ## ⚠️ 它与探索 Issues 列表的页脚（`OpenIssueIndicator.footer`）**不是同一句**
    ///
    /// 两句只差一个分隔符（这里 ` · `、那句 `：`），而且都出现在"Issue"这个词旁边 ——
    /// 正因如此更不能合并：**那句说的是"这个列表能做什么"（列表页脚），
    /// 这一句说的是"这一页的操作区为什么没有按钮"（详情页）**。
    /// `PullCopy.readOnlyHint` 的说明早就把这条规矩写下来了（PR 那边也是两句），
    /// 这里只是把同一条规矩搬到 Issue 这一边。
    ///
    /// ⚠️ **原型给不出这一句**：`SCR.issueDetail` 里连操作区都没有（偏差第 **47** 条）。
    /// 取的是**同位置的既有写法** —— 原型在 PR 详情页那一处用的是 ` · ` 分隔
    /// （`08-pr.js:50`），两个列表页脚用的是 `：`（`10-explore-repo.js:126` / `:141`）。
    /// 这一句站在"详情页操作区"那个位置上 ⇒ 跟详情页那一处走。
    public static let readOnlyHint = "他人仓库 · 可评论参与讨论，关闭 Issue 需维护者权限"

    /// §5.18 弹层的标题。
    public static let closeSheetTitle = "关闭这条 Issue？"

    /// §5.18 弹层的说明段（**规格未给**，自拟）。
    ///
    /// ⚠️ 「仍然可以重新打开」不是客套，它是一个**可验证的承诺** ——
    /// 页面上真的有一颗「重新打开 Issue」，而且作者身份本身就够了（决策 #79）。
    /// 把它说出来的用处是让用户**敢按下去**：不说的话，"关闭"这个动作看起来
    /// 与"删除"没什么区别。
    public static let closeSheetHint = "关闭之后仍然可以重新打开，评论都会保留。"

    /// 关闭成功。
    ///
    /// ⚠️ 带编号不是啰嗦：这一页的导航标题就是 `#42`，而"已关闭"三个字单独出现时
    /// 用户没法确认关的是不是他手上这一条（尤其是从列表连着点进来几条时）。
    public static func closedToast(number: Int) -> String { "已关闭 #\(number)" }

    /// 重新打开成功。
    public static func reopenedToast(number: Int) -> String { "已重新打开 #\(number)" }
}
