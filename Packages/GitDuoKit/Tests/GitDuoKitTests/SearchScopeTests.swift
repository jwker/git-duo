import Foundation
import Testing

@testable import GitDuoKit

/// 搜索范围与防抖档位（PRD §4.2、TECH_SPEC §9.2）。
///
/// 这些字符串与顺序**逐字取自原型** `scripts/04-search.js`：
/// ```js
/// const SEARCH_SCOPES = [['repos','仓库'],['users','用户'],['code','代码'],['issues','Issue · PR']];
/// ```
/// 断言它们不是形式主义：`rawValue` 是缓存键的一部分（改名 ⇒ 切范围不再命中缓存，
/// 而症状只是"变慢了"，没人会想到是这里），显示名走的是结果标题（`{范围名} · {N} 个结果`）。
@Suite("搜索范围 · 文案 / 顺序 / 门槛 / 防抖")
struct SearchScopeTests {

    @Test("四个范围的显示名逐字对齐原型")
    func titlesMatchPrototype() {
        #expect(SearchScope.allCases.map(\.title) == ["仓库", "用户", "代码", "Issue · PR"])
    }

    @Test("顺序即分段控件顺序 —— `allCases` 与原型那份数组同序")
    func orderMatchesPrototype() {
        #expect(SearchScope.allCases == [.repositories, .users, .code, .issues])
    }

    @Test("`rawValue` 保留原型里的短名（它是缓存键的稳定字符串）")
    func rawValuesMatchPrototype() {
        #expect(SearchScope.allCases.map(\.rawValue) == ["repos", "users", "code", "issues"])
        #expect(SearchScope.allCases.map(\.id) == ["repos", "users", "code", "issues"])
    }

    @Test("⚠️ 只有代码范围要求「至少一个检索词」（其余范围只填限定符是合法的）")
    func onlyCodeRequiresBareTerm() {
        #expect(SearchScope.code.requiresBareTerm)
        #expect(!SearchScope.repositories.requiresBareTerm)
        #expect(!SearchScope.users.requiresBareTerm)
        #expect(!SearchScope.issues.requiresBareTerm)
    }

    @Test("⚠️ 代码范围的防抖更长（300ms → 500ms）—— 那一档配额只有 10 次/分钟")
    func codeDebouncesLonger() {
        #expect(SearchDebounce.interval(for: .code) == .milliseconds(500))
        #expect(SearchDebounce.interval(for: .repositories) == .milliseconds(300))
        #expect(SearchDebounce.interval(for: .users) == .milliseconds(300))
        #expect(SearchDebounce.interval(for: .issues) == .milliseconds(300))
    }

    @Test("两档常量本身：300ms / 500ms")
    func intervalConstants() {
        #expect(SearchDebounce.standard == .milliseconds(300))
        #expect(SearchDebounce.code == .milliseconds(500))
    }
}

/// 「新输入到来 ⇒ 上一次的响应作废」那道闸门（`SearchRequestToken`）。
///
/// 它守的是一类**很安静**的错：先输 `swi`、再输 `swiftui`，
/// 若前者的响应后到而没被丢掉，屏幕上就会留下 `swi` 的结果，而输入框里写着 `swiftui`。
@Suite("搜索请求令牌 · 过期判定")
struct SearchRequestTokenTests {

    @Test("刚发的号就是最新的")
    func freshTokenIsCurrent() {
        var token = SearchRequestToken()
        let first = token.issue()

        #expect(token.isCurrent(first))
        #expect(token.current == first)
    }

    @Test("⚠️ 再发一次 ⇒ **上一个号立刻作废**（这正是「慢响应不许上屏」的判据）")
    func previousTokenIsStale() {
        var token = SearchRequestToken()
        let first = token.issue()
        let second = token.issue()

        #expect(!token.isCurrent(first))
        #expect(token.isCurrent(second))
        #expect(first != second)
    }

    @Test("还没发过请求时 `current` 是 0；而 `issue()` 从 1 起递增 ⇒ **真发过的号永远不为 0**")
    func tokensStartAtZeroAndAreMonotonic() {
        var token = SearchRequestToken()

        #expect(token.current == 0, "「尚未发起」的状态")

        let first = token.issue()
        let second = token.issue()

        #expect(first == 1)
        #expect(second == 2)
        #expect(first != 0, "调用方拿到的号恒非 0 —— 它才可能被误当成「尚未发起」")
    }
}
