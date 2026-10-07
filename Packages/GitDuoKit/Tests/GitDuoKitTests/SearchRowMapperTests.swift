import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// `SearchRowMapper` —— 四范围 DTO → 结果行的翻译（TECH_SPEC §9.2、PRD §4.2）。
///
/// 这组断言守的是**业务判断**，不是字段搬运：
/// 1. 会话行的**类型由响应决定**（`pull_request` 字段的存在性），不由我们发出的查询决定；
/// 2. PR 的「已合并」由 `state + merged_at` 算出来（GitHub 没有独立 merged 状态）；
/// 3. `repository_url` 的解析是**契约校验**（解错了那一行的 id 与去向全错）；
/// 4. 代码预览行折成**一行**、取第一处可用片段；没有就 `nil`（卡片不渲染那一行）。
@Suite("SearchRowMapper · 四范围 DTO → 行")
struct SearchRowMapperTests {

    private let now = Date(timeIntervalSince1970: 1_759_833_600)   // 2025-10-07 UTC

    // MARK: - 仓库 / 用户（字段搬运，但 nil 语义必须钉住）

    @Test("仓库行：四个字段原样带过去")
    func repositoryMapping() {
        let hit = SearchRowMapper.repository(
            SearchRepositoryDTO(
                fullName: "my-git/gitduo",
                description: "GitHub 客户端",
                language: "Swift",
                starCount: 128,
                createdAt: now
            )
        )

        #expect(hit.fullName == "my-git/gitduo")
        #expect(hit.description == "GitHub 客户端")
        #expect(hit.language == "Swift")
        #expect(hit.starCount == 128)
        #expect(hit.id == "my-git/gitduo")
    }

    @Test("用户行：可选字段原样带过去 —— **查不到就是 nil，不是 0**")
    func userMapping() {
        let hit = SearchRowMapper.user(SearchUserDTO(login: "mojombo"))

        #expect(hit.login == "mojombo")
        #expect(hit.name == nil)
        #expect(hit.publicRepoCount == nil, "nil = 不知道；0 = 就是零 —— 两者在界面上必须不同")
        #expect(hit.followerCount == nil)
        #expect(hit.metaLabel == nil, "拿不到数 ⇒ 整段不渲染，而不是写一句不知道真假的话")
    }

    @Test("用户行：拿到数时 metaLabel 两段都拼")
    func userMetaLabelWithCounts() {
        let hit = SearchRowMapper.user(
            SearchUserDTO(login: "dev-j", name: "jj", publicRepos: 5, followers: 210_000)
        )

        #expect(hit.profileMetaLabel == "@dev-j · 5 个仓库 · 210k 关注者")
        // 结果行副标题比弹层**多「公开」二字**（原型两处就是这么写的，不是笔误）。
        #expect(hit.metaLabel == "5 个公开仓库 · 210k 关注者")
    }

    // MARK: - 代码行

    @Test("代码行：仓库全名 / 路径 / 语言 / 预览逐个带过去")
    func codeMapping() throws {
        let hit = try SearchRowMapper.code(
            SearchCodeDTO(
                path: "Sources/App.swift",
                language: "Swift",
                repository: .init(fullName: "my-git/gitduo"),
                textMatches: [.init(fragment: "let x = 1")]
            )
        )

        #expect(hit.path == "Sources/App.swift")
        #expect(hit.repoFullName == "my-git/gitduo")
        #expect(hit.language == "Swift")
        #expect(hit.snippet == "let x = 1")
        // id 必须含仓库全名：两个仓库的同名文件不是同一行。
        #expect(hit.id == "my-git/gitduo/Sources/App.swift")
    }

    @Test("⚠️ 代码行：仓库全名不是 owner/name ⇒ 抛 malformedFullName（校验契约，不猜）")
    func codeRejectsMalformedRepoName() {
        #expect(throws: RepositoryMappingError.self) {
            _ = try SearchRowMapper.code(
                SearchCodeDTO(
                    path: "a.swift",
                    repository: .init(fullName: "gitduo"),
                    textMatches: nil
                )
            )
        }
    }

    // MARK: - 预览行（snippet）

    @Test("snippet：多行 fragment 折成一行（不改内容，只改排版）")
    func snippetFoldsToSingleLine() {
        let snippet = SearchRowMapper.snippet(
            from: [.init(fragment: "func apply() {\n    state = .loading\n}")]
        )

        #expect(snippet == "func apply() { state = .loading }")
    }

    @Test("snippet：第一处 fragment 是空 ⇒ 用下一处；全都不可用 ⇒ nil")
    func snippetSkipsEmptyAndReturnsNil() {
        #expect(SearchRowMapper.snippet(from: nil) == nil, "不带 text-match 媒体类型时没有这个键")
        #expect(
            SearchRowMapper.snippet(from: [.init(fragment: nil), .init(fragment: "  \n\t")]) == nil,
            "跳过 nil 与折完为空的片段"
        )
        #expect(
            SearchRowMapper.snippet(from: [.init(fragment: nil), .init(fragment: "ok")]) == "ok",
            "不可用的前一处不该把后面能用的也吞掉"
        )
    }

    // MARK: - 会话行（本套件的重点）

    @Test("会话行 Issue：没有 pull_request 键 ⇒ kind 是 .issue，状态只有 open / closed")
    func conversationIssue() throws {
        let hit = try SearchRowMapper.conversation(
            SearchConversationDTO(
                number: 42,
                title: "登录页错位",
                state: "open",
                updatedAt: now,
                repositoryURL: URL(string: "https://api.github.com/repos/my-git/gitduo")!
            )
        )

        #expect(hit.kind == .issue)
        #expect(hit.state == .open)
        #expect(hit.repoFullName == "my-git/gitduo")
        #expect(hit.id == "issue:my-git/gitduo#42")
    }

    @Test("⚠️ 会话行类型**取自响应**：is:issue 的查询里混进一条 PR 也按 PR 画")
    func conversationKindComesFromResponse() throws {
        let hit = try SearchRowMapper.conversation(
            SearchConversationDTO(
                number: 7,
                title: "修复令牌落盘",
                state: "closed",
                updatedAt: now,
                repositoryURL: URL(string: "https://api.github.com/repos/o/r")!,
                pullRequest: .init(mergedAt: now)
            )
        )

        #expect(hit.kind == .pullRequest, "判据是 pull_request 字段的存在性，不是我们发的哪条查询")
        #expect(hit.state == .merged)
        #expect(hit.id == "pr:o/r#7")
    }

    @Test("会话行 PR 三态：closed + merged_at 有值 ⇒ .merged；没有 ⇒ .closed；open ⇒ .open")
    func conversationPRStates() throws {
        let url = URL(string: "https://api.github.com/repos/o/r")!
        func pr(_ state: String, mergedAt: Date?) throws -> PullRequestState {
            try SearchRowMapper.conversation(
                SearchConversationDTO(
                    number: 1, title: "t", state: state, updatedAt: now,
                    repositoryURL: url, pullRequest: .init(mergedAt: mergedAt)
                )
            ).state
        }

        #expect(try pr("open", mergedAt: nil) == .open)
        #expect(try pr("closed", mergedAt: now) == .merged)
        #expect(try pr("closed", mergedAt: nil) == .closed, "「已关闭」≠「已合并」")
    }

    // MARK: - repository_url 解析（契约）

    @Test("repository_url：repos/{owner}/{repo} 三段 ⇒ 解出 owner/repo")
    func parsesRepositoryURL() throws {
        let full = try SearchRowMapper.repositoryFullName(
            fromRepositoryURL: URL(string: "https://api.github.com/repos/my-git/gitduo")!
        )
        #expect(full == "my-git/gitduo")
    }

    @Test("⚠️ repository_url 形状不对 ⇒ 抛 malformedFullName（猜一个会让去向指向别处）")
    func rejectsMalformedRepositoryURL() {
        for bad in [
            "https://api.github.com/repos/a/b/c",      // 三段之后还有东西
            "https://api.github.com/users/a",          // 不是 repos/
        ] {
            #expect(throws: RepositoryMappingError.self) {
                _ = try SearchRowMapper.repositoryFullName(fromRepositoryURL: URL(string: bad)!)
            }
        }
    }
}
