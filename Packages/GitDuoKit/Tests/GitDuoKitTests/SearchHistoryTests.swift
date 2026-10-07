import Foundation
import Testing

@testable import GitDuoKit

/// 「最近搜索」的不变式（PRD §4.2、TECH_SPEC §9.2）。
///
/// 原型只有一行实现：
/// ```js
/// SEARCH_HISTORY = [q].concat(SEARCH_HISTORY.filter(x=>x!==q)).slice(0,8);
/// ```
/// —— 空白不记 · 去重 · 置顶 · 裁到 8，四件事任一漏掉，表现都很具体：
/// 不去重 ⇒ 连按两次回车出现两条一样的；不置顶 ⇒ 复用旧词后它仍停在原位；
/// 不裁剪 ⇒ 越用越长。
@Suite("SearchHistoryStore · 去重 / 置顶 / 上限")
struct SearchHistoryTests {

    @Test("上限是 8 条（PRD §4.2）")
    func maxCountIsEight() {
        #expect(InMemorySearchHistoryStore.maxCount == 8)
    }

    @Test("新词置顶，最新在最前")
    func newestFirst() async {
        let store = InMemorySearchHistoryStore()
        await store.record(term: "swiftui")
        await store.record(term: "markdown")

        #expect(await store.terms() == ["markdown", "swiftui"])
    }

    @Test("同一个词再搜 ⇒ **只留最新一条**并排到最前（不产生重复行）")
    func deduplicatesAndMovesToFront() async {
        // 存储的口径是**最新在前**：`["a","b","c"]` 里 `a` 最新、`c` 最旧。
        // 再搜一次最旧的 `c` ⇒ 它应当被拎到最前，且不留下第二份。
        let store = InMemorySearchHistoryStore(seed: ["a", "b", "c"])
        await store.record(term: "c")

        let terms = await store.terms()
        #expect(terms == ["c", "a", "b"])
        #expect(terms.count == Set(terms).count, "出现重复行就是这条不变式破了")
    }

    @Test("⚠️ 去重是**精确匹配**（原型用 `x !== q`）—— 大小写不同算两个词")
    func deduplicationIsExact() async {
        let store = InMemorySearchHistoryStore(seed: ["SwiftUI"])
        await store.record(term: "swiftui")

        #expect(await store.terms() == ["swiftui", "SwiftUI"])
    }

    @Test("超过 8 条时淘汰**最旧**的那条，而不是最新的")
    func trimsOldest() async {
        let store = InMemorySearchHistoryStore()
        for index in 0..<10 {
            await store.record(term: "t\(index)")
        }

        let terms = await store.terms()
        #expect(terms.count == 8)
        #expect(terms.first == "t9", "最新的必须在最前")
        #expect(!terms.contains("t0"), "最旧的两条应被裁掉")
        #expect(!terms.contains("t1"))
    }

    @Test("⚠️ 空输入 / 纯空白**不记**（原型 `if(!q) return`）—— 否则连按回车会塞进一串空行")
    func blankIsNotRecorded() async {
        let store = InMemorySearchHistoryStore(seed: ["swiftui"])
        await store.record(term: "")
        await store.record(term: "   ")
        await store.record(term: "\n\t")

        #expect(await store.terms() == ["swiftui"])
    }

    @Test("录入时两端去空白（否则「`swiftui `」与「`swiftui`」会各占一格）")
    func termIsTrimmedOnRecord() async {
        let store = InMemorySearchHistoryStore(seed: ["swiftui"])
        await store.record(term: "  swiftui  ")

        #expect(await store.terms() == ["swiftui"], "去空白后应命中已有那条，而不是新增")
    }

    @Test("预置数据先清洗再收下：去空白、丢空串、按精确匹配去重、裁到 8")
    func seedIsCleanedAndTrimmed() async {
        let store = InMemorySearchHistoryStore(
            seed: ["  a  ", "", "a", "   ", "b", "c", "d", "e", "f", "g", "h", "i"]
        )

        let terms = await store.terms()
        #expect(terms.first == "a", "去空白后应与后面那个 `a` 合并，且保留先出现的那个位置")
        #expect(!terms.contains(""))
        #expect(!terms.contains("   "))
        #expect(terms.count == 8)
    }

    @Test("清除后为空 —— 且**不弹确认层**（原型 `clearSearchHistory` 直接清 + toast）")
    func clearEmptiesTheList() async {
        let store = InMemorySearchHistoryStore(seed: ["swiftui", "oauth"])
        await store.clear()

        #expect(await store.terms().isEmpty)
    }
}

/// 落盘编解码的往返（TECH_SPEC §7.1：最近搜索走 **UserDefaults + JSON**）。
///
/// ## 为什么这门测试非有不可
///
/// 落盘实现落在 App target，而 **App target 没有测试 target**（`AGENTS.md §3`）。
/// 于是"存进去取不回来"是一类**没有任何提示的故障**：不报错、不崩溃，
/// 只是每次冷启动后「最近搜索」都空着。
@Suite("SearchHistory · 落盘编解码")
struct SearchHistoryCodingTests {

    @Test("编码 → 解码：条数、内容、顺序一个不丢（顺序就是首页读的那个顺序）")
    func roundTripKeepsEverything() throws {
        let original = ["swiftui", "设计令牌", "oauth"]

        let restored = SearchHistoryCoding.decode(
            from: try #require(SearchHistoryCoding.encode(original))
        )

        #expect(restored == original)
    }

    @Test("解码**不抛错**：坏数据退化成空数组，而不是让搜索页打不开")
    func decodingGarbageYieldsEmpty() {
        #expect(SearchHistoryCoding.decode(from: Data("不是 JSON".utf8)).isEmpty)
        #expect(SearchHistoryCoding.decode(from: Data()).isEmpty)
        // 形状对但元素类型不对：同样退化，不崩。
        #expect(SearchHistoryCoding.decode(from: Data(#"[{"t":1}]"#.utf8)).isEmpty)
    }
}
