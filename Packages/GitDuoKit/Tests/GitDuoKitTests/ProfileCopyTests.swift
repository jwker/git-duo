import Testing

@testable import GitDuoKit

/// **「我的」页 / 我的 Star / 设置页的全部可见文案**（`ProfileCopy`）的断言
/// —— PRD §4.17 / §4.18 / §4.20 / §5.11。
///
/// ## 为什么单独一个文件
///
/// 同 `FolderCopyTests`：这一族文案在 9.1 建起来时**一条断言都没有**，
/// 而 `AGENTS.md §5` 的纪律是"文案是契约、一律提为可测领域数据"。
///
/// ## 这一套里最贵的两条
///
/// ① **设置页那一行「前往 GitHub 手动撤销授权」与降级提示是一对** ——
///    提示说"可在设置中手动撤销"，那就必须**真的有一个入口**在那儿（偏差第 40 条）；
/// ② **菜单文字与页面标题是同一个字符串**（`ProfileCopy.menuPullRequests` 与
///    `MyConversationsCopy.title(for: .pullRequest)`）—— 两处各写一遍，
///    早晚会出现"菜单改了、页面标题没改"，而两个屏**不会同屏出现**，
///    看一屏永远发现不了。
@Suite("我的页 / 设置页文案 · 逐字与两处承诺（§4.17 / §4.18 / §4.20 / §5.11）")
struct ProfileCopyTests {

    // MARK: - 我的页

    @Test("我的页与热力图那两句逐字（原型 `SCR.me`）")
    func profilePageIsVerbatim() {
        #expect(ProfileCopy.pageTitle == "我的")
        // ⚠️ 原型卡片右上那句「过去一年」**已被年份切换器取代**（2026-10-09，用户走查第 2 条）：
        //    滚动窗口（一年前 → 现在）跨着两个年份、给不出年份标签，所以那句话连同
        //    `ProfileCopy.contributionRange` 一起删了。接替它的是 `yearLabel(_:)`
        //    —— **它不再是"照原型逐字"，而是本片新定的**（下一套断言守着它）。
        //    这条注释留在这里，是因为"少了一行断言"本身看不出是删的还是漏的。
        // ⚠️ 千分位**照原型**（它自己就带逗号），而这个数动辄四位数。
        #expect(ProfileCopy.contributionCount(1024) == "1,024 次贡献")
        #expect(ProfileCopy.contributionCount(0) == "0 次贡献")
    }

    @Test("⚠️ 热力图年份与月份那三句（取代了「过去一年」，偏差第 44 条）")
    func heatmapCopyReplacesTheRollingWindowPhrase() {
        // ⚠️ 年份那句**必须带"年"字**：卡片上不再有第二处说范围的地方
        //    —— 它同时是"范围声明"与"控件标签"，只写 `2026` 会让范围那句话消失。
        #expect(ProfileCopy.yearLabel(2026) == "2026 年")

        // ⚠️ 月份表头**数字与"月"之间不留空格**：它是坐标轴上的刻度，`1月` 是中文图表的写法
        //    （与 `contributionCount` 那种"给人读的数"——`1,024 次贡献`，**带空格**——有意不同）。
        //    ⚠️ 理由**不是"省宽度"**（表头不参与布局），见 `ProfileCopy.monthLabel` 的说明。
        #expect(ProfileCopy.monthLabel(1) == "1月")
        #expect(ProfileCopy.monthLabel(12) == "12月")

        // ⚠️ **规格未给**（自拟，登记在偏差第 44 条）：原型没有这个控件、PRD 也没给措辞。
        //    它要把两件事都说了 —— 这个控件做什么（切年份）+ 现在在哪一年：
        //    只说动作会让读屏用户不知道现在是哪一年，只说年份又听不出它能点。
        let label = ProfileCopy.heatmapYearAccessibilityLabel(year: 2025)
        #expect(label.contains("切换年份"))
        #expect(label.contains(ProfileCopy.yearLabel(2025)))
    }

    @Test("五条菜单逐字（原型两张卡片）")
    func menuItemsAreVerbatim() {
        #expect(ProfileCopy.menuStars == "Star 管理")
        #expect(ProfileCopy.menuFolders == "我的收藏")
        #expect(ProfileCopy.menuPullRequests == "我的 Pull Request")
        #expect(ProfileCopy.menuIssues == "我的 Issue")
        #expect(ProfileCopy.menuSettings == "设置")
    }

    @Test("⚠️⚠️ 菜单文字与「我的 PR / Issue」那两页的标题**必须是同一个字符串**")
    func conversationTitlesShareOneDefinition() {
        // 两个菜单项与两页标题是**同一句话**（PRD §4.21 逐字）。
        // 两处各写一遍时，"菜单改了、页面标题没改"（或反过来）**看一屏永远发现不了**
        // —— 它们不会同屏出现。所以 `MyConversationsCopy.title(for:)` 向这里取。
        #expect(MyConversationsCopy.title(for: .pullRequest) == ProfileCopy.menuPullRequests)
        #expect(MyConversationsCopy.title(for: .issue) == ProfileCopy.menuIssues)
    }

    @Test("我的 Star：标题与空态两行逐字（空态是 PRD §7 新定的，原型没有）")
    func starsPageIsVerbatim() {
        #expect(ProfileCopy.starsTitle == "我的 Star")
        #expect(ProfileCopy.starsEmptyTitle == "还没有 Star 过任何仓库")
        // ⚠️ 第二行是**操作引导**（"怎么做才会有"）—— 与探索页那两处
        //    （说的是"这个仓库没有"）**有意不同**：这里说的是"**你**还没有"。
        #expect(ProfileCopy.starsEmptyHint == "在仓库页点一下 Star，它就会出现在这里")
        #expect(ProfileCopy.unstarAction == "已 Star")
    }

    // MARK: - 设置页

    @Test("设置页五行与三个分区逐字（原型 `SCR.settings`）")
    func settingsPageIsVerbatim() {
        #expect(ProfileCopy.settingsTitle == "设置")
        #expect(ProfileCopy.sectionAppearance == "外观")
        #expect(ProfileCopy.sectionAccount == "账户")
        #expect(ProfileCopy.sectionAbout == "关于")
        #expect(ProfileCopy.themeRow == "主题")
        #expect(ProfileCopy.themeValue == "浅色")
        #expect(ProfileCopy.signOutRow == "退出登录")
        #expect(ProfileCopy.clearCacheRow == "清除缓存")
        #expect(ProfileCopy.versionRow == "版本")
    }

    @Test("账户第一行带活的登录名；授权状态恒为「已授权」")
    func accountRowIsLiveAndAuthorized() {
        #expect(ProfileCopy.appRow(login: "jiangjiang") == "GitHub App · jiangjiang")
        // ⚠️ 不写"未授权"分支：能进设置页就说明本机有可用令牌
        //    （失效会在数据层被归一化成 `.unauthorized` 并把用户送回登录页）⇒ 那个状态不可达。
        #expect(ProfileCopy.authorizationValue == "已授权")
    }

    @Test("版本与缓存大小：两个值都是活的，且缓存那个数**带一个空格**")
    func liveValuesFormatCorrectly() {
        #expect(ProfileCopy.version(short: "2.0", build: "1") == "2.0 (1)")
        // ⚠️ `12.4 MB`（带空格）与 `CommitSheetCopy` 的 `3.2MB`（不带）**不是同一个格式**：
        //    两处都逐字抄各自的正本，所以**有意不合并**。
        #expect(ProfileCopy.cacheSize(bytes: 12_400_000) == "12.4 MB")
        #expect(ProfileCopy.cacheSize(bytes: 0) == "0.0 MB")
        // 负数只可能来自一次算错，兜成 0 而不是印一个负的大小。
        #expect(ProfileCopy.cacheSize(bytes: -1) == "0.0 MB")
        #expect(ProfileCopy.cacheCleared(released: 12_400_000) == "已清除缓存 · 释放 12.4 MB")
    }

    // MARK: - §5.11 退出登录（本文件里最需要被钉住的一条）

    @Test("退出登录弹层三句逐字")
    func signOutSheetIsVerbatim() {
        #expect(ProfileCopy.signOutSheetTitle == "退出登录？")
        #expect(ProfileCopy.signOutConfirmAction == "退出登录")
        #expect(ProfileCopy.cancelAction == "取消")
        // ⚠️ 括号里那句「授权记录不再出现在 GitHub 设置里」是**可验证的承诺**
        //    （切片 1 的真机验收第 7 步验的就是它）—— 它是"退出登录"与
        //    "只是本机清掉"之间**唯一**的区别，删了这句，两件事在文案上就再也分不开了。
        #expect(ProfileCopy.signOutSheetHint.contains("授权记录不再出现在 GitHub 设置里"))
        #expect(ProfileCopy.signOutSheetHint.contains("无需重新安装 App"))
    }

    @Test("⚠️⚠️ 降级那句与「设置页手动撤销入口」是一对，**缺一个另一个就是空头承诺**")
    func degradedNoticeAndManualEntryMustStayPaired() {
        // 这条是本片（切片 9）新增偏差第 40 条的要害：
        // 撤销失败时那句提示点名叫用户"可在设置中手动撤销"，而那时人**已经在登录页上了**
        // ⇒ 设置页那个入口**只能常驻**（不能等失败时才出现）。
        // 缺了入口，这句提示就是"承诺实现了做不到的事"（`AGENTS.md §5` 点名的那类问题）；
        // 缺了这半句，那个入口就等于不存在（用户不知道还能去哪补救）。**两条一起看。**
        #expect(ProfileCopy.signOutDegradedNotice.contains("可在设置中手动撤销"))
        #expect(!ProfileCopy.manualRevokeAction.isEmpty)

        // 成功那句不带兜底（撤销成功了就没什么要补救的）—— 两句不能合并。
        #expect(ProfileCopy.signedOutNotice == "已退出登录 · 已同时撤销 GitHub 侧授权")
        #expect(!ProfileCopy.signedOutNotice.contains("手动撤销"))
        #expect(ProfileCopy.signedOutNotice != ProfileCopy.signOutDegradedNotice)
    }

    @Test("手动撤销入口那句是一句**完整的动作说明**（所以点它不再弹解释）")
    func manualRevokeActionIsSelfExplanatory() {
        // 与「Revert」「置顶管理」那几处不同：那些要先解释"为什么这件事在 App 里做不到"，
        // 而本行的标题本身已经说清了动作与去处（`SettingsView.openManualRevoke` 的说明）
        // ⇒ 它**不弹提示**、直接开浏览器。这条断言守的是"别把它改成一句名词"。
        #expect(ProfileCopy.manualRevokeAction == "前往 GitHub 手动撤销授权")
    }
}
