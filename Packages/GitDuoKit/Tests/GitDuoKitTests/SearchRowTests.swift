import Foundation
import Testing

@testable import GitDuoKit

/// 四种搜索结果行的取值与文案（PRD §4.2）。
///
/// 断言集中在两件容易出错、且出错了很难发现的事上：
/// **`id` 不能撞车**（切范围时 `ForEach` 会认错行）与
/// **数字/文案的格式各按各的规矩**（Star 用千分位、关注者用 k/m 缩写，原型就是这么分的）。
@Suite("SearchRow · 四种行 / 文案 / 去重键")
struct SearchRowTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - `id`

    @Test("⚠️ 四种行的 `id` 前缀各不相同 —— 切范围时整份列表被换掉，撞车就会认错行")
    func idsHaveDistinctPrefixes() {
        let rows: [SearchRow] = [
            .repository(RepositoryHit(fullName: "my-git/gitduo", starCount: 1)),
            .user(UserHit(login: "dev-j", publicRepoCount: 3, followerCount: 21)),
            .code(CodeHit(path: "README.md", repoFullName: "my-git/gitduo")),
            .conversation(ConversationHit(
                kind: .issue, number: 42, title: "登录按钮不可点",
                repoFullName: "my-git/gitduo", state: .open, updatedAt: base
            ))
        ]

        let ids = rows.map(\.id)
        #expect(ids.count == Set(ids).count)
        #expect(ids == [
            "repo:my-git/gitduo",
            "user:dev-j",
            "code:my-git/gitduo/README.md",
            "issue:my-git/gitduo#42"
        ])
    }

    @Test("⚠️ 代码行的键**必须含仓库全名**：两个仓库里的同名文件不是同一行")
    func codeIdIncludesRepository() {
        let a = CodeHit(path: "Package.swift", repoFullName: "my-git/gitduo")
        let b = CodeHit(path: "Package.swift", repoFullName: "apple/swift")

        #expect(a.id != b.id)
    }

    @Test("Issue 与 PR 编号相同也不撞（前缀带 `kind`）")
    func issueAndPullOfSameNumberDoNotCollide() {
        let issue = ConversationHit(
            kind: .issue, number: 7, title: "a", repoFullName: "o/r", state: .open, updatedAt: base
        )
        let pull = ConversationHit(
            kind: .pullRequest, number: 7, title: "a", repoFullName: "o/r", state: .open, updatedAt: base
        )

        #expect(issue.id != pull.id)
    }

    // MARK: - 仓库行

    @Test("owner / name 走同一份拆分实现（形状不符时**不猜**：整串当 name、owner 为空）")
    func repositorySplitsFullName() {
        let normal = RepositoryHit(fullName: "rust-lang/rust", starCount: 1)
        #expect(normal.owner == "rust-lang")
        #expect(normal.name == "rust")

        let weird = RepositoryHit(fullName: "a/b/c", starCount: 1)
        #expect(weird.owner == "")
        #expect(weird.name == "a/b/c", "猜一个 owner 会让路由指向不存在的仓库")
    }

    @Test("Star 用**千分位**（与仓库头部同一套，不是 `2.3k` 那种缩写）")
    func repositoryStarUsesGroupedNumber() {
        #expect(RepositoryHit(fullName: "o/r", starCount: 2_341).starLabel == "2,341")
        #expect(RepositoryHit(fullName: "o/r", starCount: 11_240).starLabel == "11,240")
        #expect(RepositoryHit(fullName: "o/r", starCount: 7).starLabel == "7")
    }

    // MARK: - 用户行

    @Test("结果行副标题：`{N} 个公开仓库 · {M} 关注者`（原型逐字，且关注者用 k/m 缩写）")
    func userMetaLabel() {
        let hit = UserHit(login: "torvalds", name: "Linus Torvalds", publicRepoCount: 5, followerCount: 210_000)

        #expect(hit.metaLabel == "5 个公开仓库 · 210k 关注者")
        #expect(hit.handle == "@torvalds")
        #expect(hit.id == "torvalds")
    }

    @Test("⚠️ 资料弹层那一句**有意不同**：多 `@登录名`、少「公开」二字（原型两处就是这么写的）")
    func userProfileMetaLabel() {
        let hit = UserHit(login: "dev-j", publicRepoCount: 3, followerCount: 21)

        #expect(hit.profileMetaLabel == "@dev-j · 3 个仓库 · 21 关注者")
        #expect(hit.profileMetaLabel != hit.metaLabel)
    }

    @Test("小数值不缩写、负数不吃亏（`CompactNumber` 自身的口径，这里只钉住它被用上了）")
    func userFollowerLabelBoundaries() {
        #expect(UserHit(login: "a", publicRepoCount: 0, followerCount: 999).metaLabel == "0 个公开仓库 · 999 关注者")
        #expect(UserHit(login: "a", publicRepoCount: 0, followerCount: 1_000).metaLabel == "0 个公开仓库 · 1k 关注者")
    }

    // MARK: - 代码行

    @Test("代码行副标题：`{仓库} · {语言}`")
    func codeMetaLabel() {
        let hit = CodeHit(path: "src/main.rs", repoFullName: "nicedoc/mdx-engine", language: "Rust")
        #expect(hit.metaLabel == "nicedoc/mdx-engine · Rust")
    }

    @Test("⚠️ 语言为 `nil` 时**整段去掉**（原型那处会拼出 `… · undefined`）")
    func codeMetaLabelWithoutLanguage() {
        #expect(CodeHit(path: "x", repoFullName: "o/r", language: nil).metaLabel == "o/r")
        #expect(CodeHit(path: "x", repoFullName: "o/r", language: "").metaLabel == "o/r")
    }

    @Test("代码预览行可以是 `nil`（服务端只在带 text-match 媒体类型时才给 `text_matches`）")
    func codeSnippetIsOptional() {
        #expect(CodeHit(path: "x", repoFullName: "o/r", snippet: nil).snippet == nil)
        #expect(CodeHit(path: "x", repoFullName: "o/r", snippet: "let a = 1").snippet == "let a = 1")
    }

    // MARK: - 会话行

    @Test("会话行副标题：`{仓库} #{编号} · {相对时间}` —— 仓库是**每条自己的**，不是原型里写死的那个")
    func conversationMetaLabel() {
        let hit = ConversationHit(
            kind: .issue, number: 42, title: "登录按钮不可点",
            repoFullName: "rust-lang/rust", state: .open, updatedAt: base
        )

        #expect(hit.metaLabel(now: base) == "rust-lang/rust #42 · 刚刚")
        #expect(hit.metaLabel(now: base.addingTimeInterval(3 * 86_400)) == "rust-lang/rust #42 · 3 天前")
        #expect(hit.id == "issue:rust-lang/rust#42")
    }

    @Test("会话行状态复用 `PullRequestState` —— 读屏词与探索页 PR 列表是同一套")
    func conversationStates() {
        #expect(ConversationHit(kind: .pullRequest, number: 1, title: "t", repoFullName: "o/r", state: .merged, updatedAt: base).stateLabel == "已合并")
        #expect(ConversationHit(kind: .pullRequest, number: 1, title: "t", repoFullName: "o/r", state: .closed, updatedAt: base).stateLabel == "已关闭")
        #expect(ConversationHit(kind: .issue, number: 1, title: "t", repoFullName: "o/r", state: .open, updatedAt: base).stateLabel == "开放")
    }

    @Test("两类的口径名（用于读屏与去向）")
    func conversationKindTitles() {
        #expect(ConversationKind.issue.title == "Issue")
        #expect(ConversationKind.pullRequest.title == "Pull Request")
        #expect(ConversationKind.allCases.map(\.rawValue) == ["issue", "pr"])
    }
}

/// 搜索页可见文案（PRD §4.2 / §7、决策 #45）。
@Suite("SearchCopy · 文案与热词")
struct SearchCopyTests {

    @Test("输入框占位符、两个小节标题、清除按钮、历史空态、清空提示（原型逐字）")
    func staticCopyMatchesPrototype() {
        #expect(SearchCopy.fieldPlaceholder == "搜索仓库、用户、代码、Issue…")
        #expect(SearchCopy.recentSectionTitle == "最近搜索")
        #expect(SearchCopy.hotSectionTitle == "热门关键词")
        #expect(SearchCopy.clearHistoryAction == "清除")
        #expect(SearchCopy.emptyHistory == "还没有搜索记录")
        #expect(SearchCopy.historyClearedToast == "已清除搜索记录")
        #expect(SearchCopy.needsKeyword == "先输入关键词")
    }

    @Test("结果标题：`{范围名} · {N} 个结果`，N 带千分位（真实结果动辄上千）")
    func resultsTitle() {
        #expect(SearchCopy.resultsTitle(scope: .repositories, totalCount: 6) == "仓库 · 6 个结果")
        #expect(SearchCopy.resultsTitle(scope: .issues, totalCount: 3_847) == "Issue · PR · 3,847 个结果")
    }

    @Test("无结果两行（原型逐字）")
    func noResultsCopy() {
        #expect(SearchCopy.noResultsTitle(scope: .repositories, keyword: "swiftui") == "没有匹配「swiftui」的仓库")
        #expect(SearchCopy.noResultsTitle(scope: .issues, keyword: "登录") == "没有匹配「登录」的Issue · PR")
        #expect(SearchCopy.noResultsHint == "换个关键词，或切换上方范围试试")
    }

    @Test("回车提示：`搜索「swiftui」`")
    func submittedToast() {
        #expect(SearchCopy.submittedToast(keyword: "swiftui") == "搜索「swiftui」")
    }

    @Test("⚠️ 不完整的说明行**与探索页那句有意不同**：搜索页没有下拉刷新，出口只能是重试")
    func incompleteNoticeDiffersFromExplore() {
        #expect(SearchCopy.incompleteResults == "结果可能不完整（GitHub 计算超时）· 请重试")
        #expect(SearchCopy.incompleteResults != ExploreBoardNotice.incompleteResults)
    }

    @Test("热门关键词逐字取自原型 `SEARCH_HOT`（决策 #45：无服务端数据源，内置静态词表）")
    func hotKeywordsMatchPrototype() {
        #expect(SearchHotKeywords.all == ["swiftui", "markdown", "设计令牌", "oauth", "折叠屏"])
    }

    @Test("§5.10 与「加载更多」的文案（原型逐字 / PRD §4.2 逐字）")
    func slice54Copy() {
        #expect(SearchCopy.loadMoreAction == "加载更多")
        #expect(SearchCopy.userSheetTitle == "用户")
        #expect(SearchCopy.followAction == "关注")
        #expect(SearchCopy.publicReposAction == "查看公开仓库")
    }
}
