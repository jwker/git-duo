import Foundation
import GitHubAPI
import GitDuoCore

/// 一条会话评论（PRD §4.9 / §4.11）。
///
/// ## ⚠️ Issue 与 PR **共用一个模型**，因为服务端就是同一个资源
///
/// GitHub 把 PR 当作一种 Issue ⇒ PR 的会话评论与 Issue 的评论是**同一个端点**
/// （`GET/POST …/issues/{n}/comments`，见 `IssueCommentDTO` 的说明）。
/// 两个页面各造一个模型没有意义，反而会让"PR 的评论和 Issue 的评论有什么不同"
/// 这个问题在下一次改动里被重新问一遍。
///
/// ## 为什么没有 `isPending` / `avatarURL` 之类
///
/// 评论气泡（`CommentBubble`，切片 7.3）只画四样：头像、作者、时间、正文。
/// 头像用**登录名首字母 + 派生底色**（原型 `.avatar` 就是这么画的），
/// 不取 `avatar_url` —— 那会引入一次网络图片加载，而本片没有任何需求要真头像。
public struct IssueComment: Sendable, Hashable, Identifiable {

    /// 服务端的评论 id。**全局唯一**（不像编号是仓库内唯一）—— 去重与 `ForEach` 的键。
    ///
    /// ⚠️ 不用 `（作者 + 时间）` 之类的组合键：同一秒里同一个人可以发两条，
    /// 而 `ForEach` 撞键的表现是**少画一条**，屏幕上完全看不出来。
    public let id: Int

    /// 正文（Markdown 源文，**原样**，不裁不转义）。
    public let body: String

    /// 正文**已经解析好的块** —— 视图直接喂给 `MarkdownBody`（§11.1）。
    ///
    /// ## ⚠️ 它在**初始化器里**解析，不是让调用方各传一份
    ///
    /// 两个理由：
    ///
    /// 1. **`body` 与它不可能不一致**。做成一个从外面传进来的参数（哪怕带默认值），
    ///    就会有一处忘传 —— 而表现是"这条评论是空的"，不是报错。
    ///    放在 `init` 里，构造它的那一刻就解析完了。
    /// 2. **解析点落在数据到手的那一层**（同 `MarkdownDocument` 的说明）：
    ///    两个调用点（`LoadIssueDetail.comment(from:)` 与 `PostIssueComment.send`）
    ///    都只是构造一个 `IssueComment`，谁都不用记得"还要解析一遍"。
    ///
    /// ⚠️ 代价是**构造一个 `IssueComment` 会跑一次解析** —— 而它只在取数与发评论
    /// 这两处被构造（都不是热路径）。反过来，若改成视图里每次重绘解析
    /// （`MarkdownParser.blocks(from: comment.body)`），滚动一屏评论会重扫几十遍，
    /// 且每次结果都一样。
    public let bodyBlocks: [MarkdownBlock]

    /// 作者登录名。**可以是 `nil`**（账号被删除后 GitHub 把整段 `user` 置为 `null`）。
    public let authorLogin: String?

    /// 发表时刻。
    public let createdAt: Date

    public init(id: Int, body: String, authorLogin: String? = nil, createdAt: Date) {
        self.id = id
        self.body = body
        // `MarkdownDocument` 是"原文 + 块"的唯一构造入口，保证两者同源。
        self.bodyBlocks = MarkdownDocument(body).blocks
        self.authorLogin = authorLogin
        self.createdAt = createdAt
    }

    /// 读屏 / 无作者时的占位名。
    ///
    /// ⚠️ 作者为 `nil` 时**不写 `未知用户`**（那听起来像一个真实的账号名）——
    /// 用 `AuthorName.unknown`，它说的是确凿的事：那个账号被删了。
    ///
    /// 判据（含"空串也算拿不到"）只有一处：`AuthorName.display(_:)`。
    public var displayAuthor: String { AuthorName.display(authorLogin) }

    /// 气泡头部那个时间（`2 小时前`）。
    ///
    /// ⚠️ **与原型不完全一样，是有意的**：原型 `06-files.js:125` 硬编码的是
    /// `昨天 21:40`（带时刻），而全项目的相对时间只有 `RelativeTime` 那一套分档
    /// （`刚刚` / `n 分钟前` / `n 小时前` / `昨天` / `n 天前`）。
    /// 为评论单独造一套"带时刻"的格式，会让同一条评论在评论区与别处显示两种时间
    /// —— 那才是没人查得出来的不一致。属"原型给不出"（它的演示数据是单 token），
    /// 不是"原型给得不一致"。
    ///
    /// - Parameter now: 现时。**必传**（同 `IssueDetail.headNote(now:)` 的理由：
    ///   给它默认值等于在视图里悄悄引入第二个时间源）。
    public func timeLabel(now: Date) -> String {
        RelativeTime.string(from: createdAt, now: now)
    }
}

/// **读**评论的接缝（`GET …/issues/{n}/comments`）。
///
/// ## 为什么它单独成一条，而且**被 `IssueDetailDataSource` 继承**
///
/// 评论的读**不只服务 Issue 详情**：PR 详情的「对话」分区读的是同一个端点
/// （GitHub 把 PR 当作一种 Issue —— `IssueCommentDTO` 的说明）。
/// 而 PR 详情那一屏要的另外四样（详情 / 评审 / 文件 / Commits）都在另一个端点类上 ⇒
/// 它不能只依赖一个"什么都有"的宽协议。
///
/// 声明成 `IssueDetailDataSource` 的**父协议**之后：
/// - PR 侧的 `LoadPullDetail` 只要这一条（`any IssueCommentReading`）；
/// - Issue 侧的 `LoadIssueDetail` 拿到的是子协议（详情 + 评论）。
///
/// 两者共用**同一个方法签名**，于是 `GitHubRepoIssuesEndpoint` 只需要一个空扩展体。
public protocol IssueCommentReading: Sendable {

    /// `GET /repos/{o}/{r}/issues/{n}/comments` 的一页。
    ///
    /// ⚠️ `perPage` 没有默认值：它由调用方显式给 100（见 `LoadIssueDetail.commentPageSize`），
    /// 写成协议默认值会让"某一处悄悄用了 30"变得不可见。
    func issueComments(
        owner: String,
        repo: String,
        number: Int,
        perPage: Int,
        cursor: URL?
    ) async throws -> Page<IssueCommentDTO>
}

/// 让真实端点满足读评论的接缝。
extension GitHubRepoIssuesEndpoint: IssueCommentReading {}

/// 发评论的接缝 —— 由 `GitHubAPI` 的 `GitHubRepoIssuesEndpoint` 空扩展体满足。
///
/// ## 为什么单独一个协议（而不是并进 `RepoIssuesDataSource`）
///
/// `RepoEndpoints.swift` 那份清单里是"一个端点类 = 一个协议"，因为那边每个端点**只服务一屏**。
/// `GitHubRepoIssuesEndpoint` 从切片 7 起服务三屏、读写足迹各不相同：
///
/// | 用例 | 需要的方法 |
/// |---|---|
/// | `LoadRepoIssues`（列表） | 列表 |
/// | `LoadIssueDetail`（详情 + 评论） | 详情、评论读 |
/// | `CreateIssue`（新建） | 新建 |
/// | `PostIssueComment`（发评论，**Issue 与 PR 两页共用**） | 评论写 |
///
/// 合成一个宽协议的话，列表用例的测试替身也得写一个 `createIssue` 桩
/// —— 那份替身于是"声称列表页能建 Issue"。测试替身里的谎最难发现，也最先扩散。
///
/// ⚠️ 参数用 `String` / `Int` 而**不是**领域层类型，是接缝的硬约束（同
/// `RepoIssuesDataSource` 的说明）：被扩展的端点看不见领域层的类型，依赖是单向的。
public protocol IssueCommentPosting: Sendable {

    /// `POST /repos/{o}/{r}/issues/{n}/comments` —— **PR 的评论也走它**。
    ///
    /// - Returns: 服务端回的那条评论（201）。调用方用它的 `id` / `createdAt`
    ///   追加到本地列表，而不是自己造一条"刚刚" —— 自造的那条会与服务端
    ///   真正落库的时间、以及别人的机器上看到的时间都对不上。
    func createIssueComment(
        owner: String,
        repo: String,
        number: Int,
        body: String
    ) async throws -> IssueCommentDTO
}

/// 让真实端点满足上面的接缝。空扩展体能成立，靠的是**方法签名逐字一致**。
extension GitHubRepoIssuesEndpoint: IssueCommentPosting {}

/// 发一条评论（PRD §4.9「发送」、§4.11「评论发送」）。
///
/// ## 空内容的判定在**领域层**，不在视图
///
/// PRD 两处都写了「空内容时提示先写内容」（§7 的 `先写点内容再发送`）。
/// 把"什么算空"收在 `canSend(_:)` 一个地方：视图里写一次
/// `body.trimmingCharacters(in: .whitespaces).isEmpty` 就是一处会与
/// 服务端口径分叉的复制品 —— 而且**它分叉了不会报错**，只会让一个
/// 全是空格/换行的评论发出去（GitHub 会收下，讨论里多一条空气泡）。
///
/// ## 草稿不在这里
///
/// PRD §4.9 的提示条承诺「草稿已保留，可重试」⇒ 草稿由 `CommentDraftStore`
/// （决策 #59）负责，**只落盘、随退出登录清空**。本用例失败就是抛错、不吞 ——
/// 让调用方在同一个 `catch` 里"显示提示条 + 存草稿"，而不是把两件事分到两层去做。
public struct PostIssueComment: Sendable {

    private let source: any IssueCommentPosting

    public init(source: any IssueCommentPosting) {
        self.source = source
    }

    /// 内容是否可以发送。
    ///
    /// ⚠️ 判据是**去掉首尾空白之后非空**：一个只有换行 / 空格的输入框
    /// 在用户眼里就是空的，而 `!body.isEmpty` 会放它过去。
    public static func canSend(_ body: String) -> Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// - Parameters:
    ///   - body: 正文，**原样发出**（`canSend` 通过后不再裁剪 —— 前导缩进
    ///     在 Markdown 里是有意义的，裁掉会把一段代码块变成普通段落）。
    /// - Returns: 服务端落库的那条评论。
    /// - Throws: 任何网络 / 校验错误。⚠️ **调用方负责把草稿留下**（见类型说明）。
    public func send(fullName: String, number: Int, body: String) async throws -> IssueComment {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let dto = try await source.createIssueComment(
            owner: owner,
            repo: repo,
            number: number,
            body: body
        )
        return IssueComment(
            id: dto.id,
            body: dto.body,
            authorLogin: dto.user?.login,
            createdAt: dto.createdAt
        )
    }
}
