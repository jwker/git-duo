import Testing

@testable import GitDuoKit

/// PR 详情的三个分区（PRD §4.11 第 2 条、原型 `08-pr.js:15` 的 `.prtabs`）。
///
/// ## 这组断言守的两件事，出错时都不会报错
///
/// 1. **格数与顺序** —— 分段条按 `allCases` 画，漏一格或换顺序的后果不是崩溃，
///    而是"某一档点不着"或"它自己重排了"（同 `RepoSectionSegmentTests`）。
/// 2. **第三格带数据** —— 原型是 `文件 +842 −156`，那个统计**只有 PR 详情端点给**
///    （决策 #58）⇒ 标题必须吃一个参数。这条也很容易"改回无参属性"而不被发现：
///    屏幕上显示成 `文件 `（尾巴上一个孤零零的空格）看起来只像排版瑕疵。
@Suite("PR 详情三分区 · 格数与标题")
struct PullSectionTests {

    // MARK: - 格数与顺序

    @Test("⚠️ **只有三格**，顺序是「对话 / Commits / 文件」（原型 `08-pr.js:15` 逐位一致）")
    func threeSegmentsInOrder() {
        #expect(PullSection.allCases == [.conversation, .commits, .files])
    }

    @Test("默认落在**对话**（原型 `08-pr.js:6` 的 `p.seg||'conv'`）")
    func initialIsConversation() {
        #expect(PullSection.initial == .conversation)
    }

    @Test("""
        ⚠️ `initial` 与 `allCases.first` 是**同一件事** —— 挪动声明顺序时默认也跟着走
        """)
    func initialFollowsDeclarationOrder() {
        // 这条不是同义反复：`initial` 曾经最自然的写法是写死 `.conversation`，
        // 那样"把 files 挪到第一位"之后默认仍然停在对话，而没人会去改它。
        #expect(PullSection.initial == PullSection.allCases.first)
        // 与仓库详情那边**有意不同**：`RepoSection.initial` 是写死的 `.code`
        // （PRD §4.4 明写"分区一：代码（默认）"，那是一条产品指定、不是"第一条"）。
        #expect(RepoSection.initial == .code)
        #expect(RepoSection.allCases.first == .code)
    }

    // MARK: - 标题

    @Test("前两格是无数据的固定文案（原型逐字，含英文大小写）")
    func firstTwoTitlesAreFixed() {
        #expect(PullSection.conversation.title(stats: "+1 −1") == "对话")
        #expect(PullSection.commits.title(stats: "+1 −1") == "Commits")
    }

    @Test("⚠️ 第三格是 `文件 +842 −156` —— 统计来自详情端点，必须传进来")
    func filesSegmentCarriesStats() {
        let title = PullSection.files.title(stats: "+842 −156")

        #expect(title == "文件 +842 −156")
        // 两条"忘传/传空"的形态都要被这句话挡住 —— 它们**不会**编译失败，
        // 只会渲染出一个缺了统计的标题。
        #expect(title != "文件")
        #expect(title != "文件 ")
    }

    @Test("三格的标题互不相同（撞了不会报错，只会让某一格看起来点不着）")
    func titlesAreDistinct() {
        let stats = "+842 −156"
        let titles = PullSection.allCases.map { $0.title(stats: stats) }
        #expect(Set(titles).count == PullSection.allCases.count)
    }

    @Test("标题原样吃 `stats`（`PullDetail.statsLabel` 的输出），不自己拼加号减号")
    func titlePassesStatsThroughVerbatim() {
        // ⚠️ 分隔符与那对 `+` / `−`（U+2212，不是 ASCII 减号）都在 `PullCopy.statsLabel`
        //    一处拼好；本枚举只负责把它接在「文件」后面。
        let stats = PullCopy.statsLabel(additions: 842, deletions: 156)
        #expect(stats == "+842 −156")
        #expect(PullSection.files.title(stats: stats) == "文件 +842 −156")
    }
}
