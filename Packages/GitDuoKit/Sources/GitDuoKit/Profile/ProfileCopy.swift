import Foundation
import GitDuoCore

/// 「我的」页 / 「我的 Star」页 / 设置页的全部可见文案
/// （PRD §4.17 / §4.18 / §4.20 / §5.11、TECH_SPEC §9.14 / §9.15）。
///
/// ## 为什么放在领域层
///
/// 与 `SearchCopy` / `FolderCopy` 同源：这些是**可见契约**（PRD §7 那张表逐条列着它们），
/// 而"什么时候说哪一句"是一条产品规则。放进 `GitDuoKit` 才能被单测钉住 ——
/// App target 没有测试 target。
///
/// ## ⚠️ 逐字来源
///
/// - 我的页 / 设置页 / 热力图那几行 → 原型 `scripts/12-me.js`（逐字）；
/// - 退出登录弹层 → 原型 `scripts/13-auth.js` 的 `openSignOutSheet`（逐字）；
/// - 「我的 Star」页的空态两行 → **PRD §7**（2026-10-09 新定，原型没有空态）；
/// - 标了「**规格未给**」的几条是本片自拟的，已在 `REVIEW-CHECKLIST` 登记。
public enum ProfileCopy {

    // MARK: - 我的页

    /// 大标题（原型逐字）。
    public static let pageTitle = "我的"

    /// 热力图卡片左侧那个数（原型 `${t.contrib} 次贡献`，演示值是 `1,024 次贡献`）。
    ///
    /// ⚠️ 千分位**照原型**（它自己就带逗号），而且这个数动辄四位数 ⇒ 必须分组。
    public static func contributionCount(_ count: Int) -> String {
        "\(GroupedNumber.string(from: count)) 次贡献"
    }

    /// 热力图卡片右侧那个**年份切换器**上显示的字（`2026 年`）。
    ///
    /// ## ⚠️ 它取代了原型逐字的那句「过去一年」（2026-10-09）
    ///
    /// 原型卡片右上写的是 `过去一年`（滚动窗口：一年前 → 现在）。加年份切换之后
    /// 这句话不成立了 —— 滚动窗口跨着两个年份，给不出年份标签
    /// （`ContributionYear` 的说明讲了这条，代价也记在那儿：当前年那个数比"过去一年"少）。
    ///
    /// ⚠️ **它同时是"范围声明"与"控件标签"**：卡片上不再有第二处说范围的地方，
    /// 所以这句话必须说全（带"年"字，不能只写 `2026`）。
    public static func yearLabel(_ year: Int) -> String { "\(year) 年" }

    /// x 轴月份表头（`1月` … `12月`）。
    ///
    /// ⚠️ **数字与"月"之间不留空格**：这是一根坐标轴上的**刻度**，而"1月"正是中文图表的写法
    /// —— 与 `contributionCount` 那种"给人读的数"（`1,024 次贡献`，**带空格**）**有意不同**。
    /// ⚠️ **顺带把理由说准：不是为了"省宽度"** —— 表头由 `ZStack` + `offset` 摆，
    /// **不参与布局**，多一个空格一个 pt 都省不到。真正的理由两条：
    /// ① `1月` 是中文图表刻度的写法；② 相邻刻度只隔约 50pt（一个月最少 4 列），
    /// 多一个空格会让那一排看着更挤（**视觉密度**，不是布局）。
    public static func monthLabel(_ month: Int) -> String { "\(month)月" }

    /// 年份切换器的读屏标签。
    ///
    /// ⚠️ **规格未给**（自拟，登记在偏差第 44 条）：原型没有这个控件、PRD 也没给措辞。
    /// 这里说的是"**这个控件做什么**"（切年份），并把**当前是哪一年**念出来 ——
    /// 只念动作（"切换年份"）会让读屏用户不知道现在是哪一年，只念年份又听不出它能点。
    public static func heatmapYearAccessibilityLabel(year: Int) -> String {
        "切换年份，当前 \(yearLabel(year))"
    }

    // MARK: - 菜单（原型两张卡片）

    public static let menuStars = "Star 管理"
    public static let menuFolders = "我的收藏"
    public static let menuPullRequests = "我的 Pull Request"
    public static let menuIssues = "我的 Issue"
    public static let menuSettings = "设置"

    // MARK: - 我的 Star（PRD §4.18 / §7）

    /// 推入页标题（原型 `SCR.stars.inline` 逐字）。
    public static let starsTitle = "我的 Star"

    /// 空态两行（PRD §7 逐字，2026-10-09 新定）。
    ///
    /// ⚠️ 第二行是**操作引导**（"怎么做才会有"），不是解释现状 ——
    /// 与探索页那两处（`暂无开放的 Issue` / `这个仓库当前没有开放中的 Issue`）
    /// **有意不同**：那两处说的是"**这个仓库**没有"，这两处说的是"**你**还没有"。
    public static let starsEmptyTitle = "还没有 Star 过任何仓库"
    public static let starsEmptyHint = "在仓库页点一下 Star，它就会出现在这里"

    /// 列表行那一颗按钮 —— 已 Star 时（原型 `SCR.stars.render` 逐字）。
    ///
    /// ⚠️ 与 §4.13 详情页那颗 `已 Star · {n}` **不是同一句**：那一颗带计数，
    /// 这一颗只表明状态（列表行上的星数在副标题里，按钮上再写一遍会挤）。
    public static let unstarAction = "已 Star"

    // MARK: - 设置（PRD §4.20、原型 `SCR.settings`）

    /// 推入页标题（原型 `SCR.settings.inline` 逐字）。
    public static let settingsTitle = "设置"

    /// 三个分区标题（原型逐字）。
    public static let sectionAppearance = "外观"
    public static let sectionAccount = "账户"
    public static let sectionAbout = "关于"

    public static let themeRow = "主题"

    /// 主题的右侧值（原型逐字）。
    ///
    /// ⚠️ **它是一行只读文字，不是切换器**：本期仅浅色（PRD §4.20、`TECH_SPEC §9.15`）。
    /// PRD 只给了"本期仅浅色"这一条，没有说要不要把"以后会有"说出来 ——
    /// 所以这一行**照原型不写任何解释**（多写一句就是对交付范围的承诺）。
    public static let themeValue = "浅色"

    /// 账户分区第一行 —— `GitHub App · {账号}`（原型逐字，用户名是活的）。
    public static func appRow(login: String) -> String { "GitHub App · \(login)" }

    /// 授权状态的右侧值（原型逐字）。
    ///
    /// ⚠️ 它是**恒为真**的：能进到设置页就说明本机有可用的令牌
    /// （令牌失效会在数据层被归一化成 `.unauthorized` 并把用户送回登录页）。
    /// 所以这里不写"未授权"分支 —— 那个状态在界面上不可达。
    public static let authorizationValue = "已授权"

    public static let signOutRow = "退出登录"

    /// 登出**在途**时那一行右侧显示的值（2026-10-09 用户走查裁定 · 决策 #78）。
    ///
    /// ## ⚠️ 为什么必须有这一句
    ///
    /// 按下确认之后是**弹层先关、登出随后进行** —— 弹层不能等结果：登出会把 `authState`
    /// 打回未认证 ⇒ `RootView` 换掉整棵主界面，而弹层正挂在那棵即将消失的树上
    /// （见 `SettingsView.signsOutAfterDismissal`）。于是"确认之后让按钮转圈"这条
    /// 最自然的反馈路径**被堵死了**，而从"弹层消失"到"登录页出现"之间还有一次
    /// **撤销 GitHub 侧授权的网络往返** ⇒ 这段时间屏幕完全静默，用户会以为按钮没生效。
    ///
    /// ## ⚠️ 它写得**尽量短**，因为它是一个状态、不是一句话
    ///
    /// 与 `MenuRow` 那一列其它值同一形态（`浅色` / `已授权` / `12.4 MB`）。
    /// ⚠️ 结尾用**中文省略号**（与 `SheetField` 的占位、`写评论…` 同一字形），
    /// 不是三个点 —— 三个点在中文里看起来像断句。
    public static let signingOutValue = "正在退出…"
    public static let clearCacheRow = "清除缓存"
    public static let versionRow = "版本"

    /// 版本右侧值：`2.0 (1)`（原型逐字，值是活的）。
    ///
    /// ⚠️ 两个数都从 `Bundle` 现读（PRD 走查单 #142 点名：**不许硬编码**）——
    /// 写死了每次发版都要改代码，而漏改**不会报错**，只会一直在界面上显示旧版本。
    public static func version(short: String, build: String) -> String { "\(short) (\(build))" }

    /// 清除缓存右侧值：`12.4 MB`（原型逐字，值是活的）。
    ///
    /// ## ⚠️ 与 `CommitSheetCopy` 那个 `sizeLabel` **不是同一个格式**
    ///
    /// 这里**数字与单位之间有一个空格**（原型 `12.4 MB`），
    /// 那边没有（`3.2MB`）。两处都是逐字抄各自的正本，所以**有意不合并**。
    ///
    /// ⚠️ 不足 `0.05MB` 时会显示成 `0.0 MB` —— 那是四舍五入的结果，
    /// **不是**"没有缓存"的断言（真要区分得再加一档 KB 单位，而原型只给了 MB 这一档）。
    public static func cacheSize(bytes: Int) -> String {
        String(format: "%.1f MB", Double(max(0, bytes)) / 1_000_000)
    }

    /// 清空缓存成功后的提示。
    ///
    /// ⚠️ **规格未给**（自拟）。PRD §4.20 只说"完成后显示释放空间"，
    /// 没给措辞 —— 这里照 8.7 那条 caption 的做法**把两个数都写出来**
    /// （释放了多少），因为"清完了"与"清掉了多少"不是同一件事。
    /// 与 `FolderCopy.deleted` 同构（都带一个数量）。
    public static func cacheCleared(released: Int) -> String {
        "已清除缓存 · 释放 \(cacheSize(bytes: released))"
    }

    // MARK: - §5.11 退出登录确认

    /// 弹层标题（原型 `openSignOutSheet` 逐字）。
    public static let signOutSheetTitle = "退出登录？"

    /// 说明段（原型逐字）。
    ///
    /// ⚠️ 括号里那句「授权记录不再出现在 GitHub 设置里」是**可验证的承诺**
    /// （切片 1 的真机验收第 7 步就验的它），不是客套 —— 它是"退出登录"与
    /// "只是本机清掉"之间**唯一**的区别。
    public static let signOutSheetHint = "将清除本机 Keychain 中的访问令牌与缓存，"
        + "并撤销 GitHub 侧的授权（授权记录不再出现在 GitHub 设置里）。"
        + "下次使用需要重新授权，但无需重新安装 App。"

    /// 确认按钮（原型逐字）。
    public static let signOutConfirmAction = "退出登录"

    /// 取消（原型逐字）。
    public static let cancelAction = "取消"

    /// 登出成功（撤销也成功）。
    ///
    /// ⚠️ 与 `AppEnvironment.signOut()` 现在那句**一模一样**，但**注意**：
    /// 这里收口它是因为降级那句（下一行）此前与 PRD 不一致 —— 见 `signOutDegradedNotice`。
    public static let signedOutNotice = "已退出登录 · 已同时撤销 GitHub 侧授权"

    /// 登出成功但**撤销失败**（离线 / 网络错误）。
    ///
    /// ## ⚠️ 2026-10-09：这一句与代码里实际用的**不一样**，以本句为准
    ///
    /// PRD §5.11 与 §7 两处逐字都带着结尾那半句
    /// 「**，可在设置中手动撤销**」，而 `AppEnvironment.signOut()` 里写的是
    /// 不带结尾的短版（`…（未能撤销 GitHub 侧授权）`）。
    ///
    /// 这半句不是修饰：TECH_SPEC §9.15 明写设置页要**保留"前往 GitHub 手动撤销"的入口，
    /// 正是作为撤销失败时的兜底**。提示不说出口在哪，那个兜底就等于不存在
    /// （用户只知道"没撤销成功"，不知道还能去哪补救）。
    /// ⇒ 已在切片 9 收口到这里，`AppEnvironment` 改为引用本常量（9.5 接线）。
    public static let signOutDegradedNotice = "已退出登录 · 本机令牌已清除"
        + "（未能撤销 GitHub 侧授权，可在设置中手动撤销）"

    /// 撤销失败的兜底入口（TECH_SPEC §9.15：设置页保留的网页跳转）。
    ///
    /// ⚠️ **规格未给**（自拟）：PRD 只写"保留手动撤销入口"，没给它的形态与措辞。
    /// 这里给的是**一句动作 + 一个地址**，与 `RepoCopy` 那边"跳网页端管理置顶"
    /// 的处置同构（GitHub 没有对应写接口时，客户端只负责把人送到网页端）。
    public static let manualRevokeAction = "前往 GitHub 手动撤销授权"
}
