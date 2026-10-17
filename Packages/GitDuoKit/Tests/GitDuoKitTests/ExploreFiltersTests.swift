import Foundation
import Testing

@testable import GitDuoKit

/// 探索页的筛选状态与两类可见文案（PRD §3.12 / §4.12，harness `harness.js:321–345`）。
@Suite("ExploreFilters · 未选语义 / 取消 / 文案")
struct ExploreFiltersTests {

    // MARK: - 默认与文案

    @Test("默认：日期范围 = 本周，语言不选（PRD §3.12 明写）")
    func defaultState() {
        #expect(ExploreFilters.default.range == .thisWeek)
        #expect(ExploreFilters.default.language == nil)
    }

    @Test("语言选项是补全后的主流编程语言清单（GitHub trending/explore 官方筛选，2026-10-17 起不再限 5 项）")
    func languageOptionsMatchExpandedGitHubSet() {
        #expect(ExploreFilters.languageOptions == [
            "JavaScript", "TypeScript", "Python", "Java", "C++", "C", "C#", "Go",
            "Rust", "Ruby", "PHP", "Swift", "Kotlin", "Dart", "Shell", "Objective-C",
            "Scala", "R", "MATLAB", "Lua", "Perl", "Haskell", "Elixir", "Clojure",
            "Erlang", "F#", "OCaml", "Julia", "Crystal", "Zig", "Nim", "Solidity",
            "Assembly", "Fortran", "Groovy", "Visual Basic", "Delphi", "COBOL",
            "Pascal", "PowerShell", "Vim Script", "Batchfile", "SQL", "HTML", "CSS",
            "Vue", "Svelte", "CoffeeScript", "TeX", "ActionScript",
        ])
        // 仍保留原 PRD 的 5 项（harness.js 对其有断言）。
        #expect(ExploreFilters.languageOptions.contains("Swift"))
        #expect(ExploreFilters.languageOptions.contains("Rust"))
        #expect(ExploreFilters.languageOptions.contains("TypeScript"))
        #expect(ExploreFilters.languageOptions.contains("Python"))
        #expect(ExploreFilters.languageOptions.contains("Go"))
    }

    @Test("chip 文案：未选时是占位「日期」/「语言」，已选时是选中值")
    func chipLabels() {
        let blank = ExploreFilters(range: nil, language: nil)
        #expect(blank.rangeChipLabel == "日期")
        #expect(blank.languageChipLabel == "语言")

        let picked = ExploreFilters(range: .thisMonth, language: "Swift")
        #expect(picked.rangeChipLabel == "本月")
        #expect(picked.languageChipLabel == "Swift")

        // 原型断言的实际形态：语言 chip 未选时**以「语言」开头**（`harness.js:324`），
        // 选中后以选中的语言名开头（`harness.js:332`）。
        #expect(blank.languageChipLabel.hasPrefix("语言"))
        #expect(picked.languageChipLabel.hasPrefix("Swift"))
    }

    @Test("弹层行文案与角标窗口词**有意不同**：`今天` / `今日`")
    func todayHasTwoWritings() {
        #expect(ExploreDateRange.today.title == "今天")
        #expect(ExploreDateRange.today.badgeLabel == "今日")
        #expect(ExploreDateRange.allCases.map(\.title) == ["今天", "本周", "本月"])
        #expect(ExploreDateRange.allCases.map(\.badgeLabel) == ["今日", "本周", "本月"])
    }

    @Test("弹层标题（也是 toast 前缀）与占位文案")
    func filterKindCopy() {
        #expect(ExploreFilterKind.range.title == "日期范围")
        #expect(ExploreFilterKind.language.title == "编程语言")
        #expect(ExploreFilterKind.range.blankLabel == "日期")
        #expect(ExploreFilterKind.language.blankLabel == "语言")
    }

    // MARK: - 窗口与系数

    @Test("三个时间窗逐字对齐原型（1440 / 10080 / 43200 分钟）")
    func windows() {
        #expect(ExploreDateRange.today.window == 86_400)
        #expect(ExploreDateRange.thisWeek.window == 604_800)
        #expect(ExploreDateRange.thisMonth.window == 2_592_000)
    }

    @Test("换算系数：今天 1/7 · 本周 1 · 本月 4.3（PRD §4.12）")
    func scaleFactors() {
        #expect(ExploreDateRange.today.scaleFactor == 1.0 / 7.0)
        #expect(ExploreDateRange.thisWeek.scaleFactor == 1)
        #expect(ExploreDateRange.thisMonth.scaleFactor == 4.3)
    }

    // MARK: - 选中 / 取消

    @Test("选中某项：状态写入 + 返回 .picked，toast 形如「编程语言：Swift」")
    func pickingReturnsPicked() {
        var filters = ExploreFilters.default

        let change = filters.select(language: "Swift")

        #expect(filters.language == "Swift")
        #expect(change == .picked(.language, "Swift"))
        #expect(change.toastText == "编程语言：Swift")
    }

    @Test("**再点当前项 = 取消**，回到「全部」并提示「已取消」（harness 断言 toast 含「已取消」）")
    func tappingSameValueCancels() {
        var filters = ExploreFilters(range: nil, language: "Swift")

        let change = filters.select(language: "Swift")

        #expect(filters.language == nil, "再点一次必须回到「全部」")
        #expect(change == .cancelled(.language))
        #expect(change.toastText == "编程语言：已取消，显示全部")
        #expect(change.toastText.contains("已取消"))
        #expect(filters.languageChipLabel == "语言", "chip 必须回到占位文案")
    }

    @Test("日期范围的取消同理：回到占位「日期」")
    func rangeCancellation() {
        var filters = ExploreFilters.default

        let change = filters.select(range: .thisWeek)

        #expect(filters.range == nil)
        #expect(change == .cancelled(.range))
        #expect(change.toastText == "日期范围：已取消，显示全部")
        #expect(filters.rangeChipLabel == "日期")
    }

    @Test("两个筛选**互不干扰**：选语言不会动日期范围，反之亦然")
    func filtersAreIndependent() {
        var filters = ExploreFilters.default

        _ = filters.select(language: "Rust")
        #expect(filters.range == .thisWeek, "选语言不该顺手把日期范围重置")

        _ = filters.select(range: .thisMonth)
        #expect(filters.language == "Rust", "选日期不该把语言丢掉")
    }

    @Test("高亮只反映「有没有选」，与选了哪一项无关")
    func highlight() {
        let blank = ExploreFilters(range: nil, language: nil)
        #expect(!blank.isHighlighted(.range))
        #expect(!blank.isHighlighted(.language))

        let picked = ExploreFilters(range: .today, language: nil)
        #expect(picked.isHighlighted(.range))
        #expect(!picked.isHighlighted(.language))
    }

    @Test("选中值回传 —— 弹层靠它打 ✓")
    func selectedValue() {
        let filters = ExploreFilters(range: .thisMonth, language: nil)

        #expect(filters.selectedValue(.range) == "本月")
        #expect(filters.selectedValue(.language) == nil)
    }

    // MARK: - 缓存键

    @Test("缓存键吃下三个维度 —— 少任何一个都会让「切回来看到别的筛选的结果」")
    func cacheKeyCoversAllThreeDimensions() {
        let base = ExploreCacheKey(board: .rising, filters: .default)

        #expect(base != ExploreCacheKey(board: .active, filters: .default))
        #expect(base != ExploreCacheKey(board: .rising, filters: ExploreFilters(range: .today, language: nil)))
        #expect(base != ExploreCacheKey(board: .rising, filters: ExploreFilters(range: .thisWeek, language: "Go")))

        // 同榜同筛选 ⇒ 必须相等（否则"来回切换直接命中"永远命中不了）
        #expect(base == ExploreCacheKey(board: .rising, filters: .default))
    }
}
