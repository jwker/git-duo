import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 一条搜索结果行 —— 四种行共用的分派入口。
///
/// ## 为什么不把四种行塞进一个"宽行 + 一堆可空字段"
///
/// 见 `SearchRow` 的类型说明：那样会让根本不存在的组合在类型上合法。
/// 这里只是把"哪一种行 → 哪一个视图"这一层薄分派写出来，
/// 四种行的形状各自待在自己的小视图里。
///
/// ## ⚠️ 2026-10-16 起它只产**内容**（NATIVE-MIGRATION P3）
///
/// 不再收 `showsSeparator` / `action`：行内边距、分隔线、点击与跳转都归 `List` 的行机制
/// （`SearchView` 把每一行包进 `NavigationLink` 或 `Button`）。理由见 `SearchRowBox`。
///
/// ## 它是内容层（决策 #43 的落点）
///
/// 四个小视图的入参都是领域模型（`RepositoryHit` / `UserHit` / `CodeHit` / `ConversationHit`）
/// ⇒ 它们认识业务，留在 Feature。设计包里只有"与业务无关的视觉件"
/// （本页用到的那三件 —— `UserAvatar`（owner 头像）/ `StatusPill` / `CodePreviewLine`）。
struct SearchRowView: View {

    let row: SearchRow

    /// 算相对时间用的"现在"。由页面在**结果到达那一刻**取一次传下来 ——
    /// 不在卡片内部取 `Date()`：那会让每次重绘拿到略微不同的值，
    /// 于是相对时间变成渲染时机的一部分（沿 `IssueCard` 的同一条纪律）。
    let now: Date

    var body: some View {
        switch row {
        case let .repository(hit):
            RepositoryResultRow(hit: hit)
        case let .user(hit):
            UserResultRow(hit: hit)
        case let .code(hit):
            CodeResultRow(hit: hit)
        case let .conversation(hit):
            ConversationResultRow(hit: hit, now: now)
        }
    }
}

// MARK: - 仓库

/// 仓库结果行（原型 `repoResultRow`）。
///
/// 形状：owner 头像（2026-10-15 起替代 `RepoAvatar.compact`，走查第 72 条）+「owner 弱化 / name 加粗」+ 简介 + 语言与 Star 两个 chip。
///
/// ⚠️ 与原型的两处**有意偏差**：
/// 1. **标题字号**：原型是 14px，这里用 `Font.rowTitle`（`.subheadline`，15pt）——
///    本仓的语义字号表里没有 14 这一档（最接近的就是 15）。
/// 2. **Star 数**：原型写成 `2,341` 那样的字符串是**演示数据**手写的；
///    这里走 `RepositoryHit.starLabel`（千分位全量 `GroupedNumber`）——
///    搜索结果是用户要读准的地方，不用 `124k` 那种缩写（见该属性的说明）。
///
/// ⚠️ 2026-10-16（P3）：原先行内的尖角（`RowChevron`）与尾部箭头一起撤掉 ——
/// 现在是 `List` 的 `NavigationLink` 行，系统自己画箭头（且箭头会随"能不能推入"变化，
/// 而自绘的那一枚不会）。`RowChevron` 这个件随之删除。
struct RepositoryResultRow: View {

    let hit: RepositoryHit

    var body: some View {
        SearchRowBox {
            // ⚠️ 2026-10-15 起是 **owner 头像**（圆形，走查第 72 条），不再是原型的
            //    文件夹图标块；尺寸仍是 32（`RepoAvatar.compact.diameter`）。
            UserAvatar(
                login: hit.owner,
                avatarURL: hit.ownerAvatarURL,
                diameter: RepoAvatar.compact.diameter
            )

            VStack(alignment: .leading, spacing: 0) {
                // 两色拼接：先各自做成 `Text`，再**一次性**插进同一个字面量
                // （`Text + Text` 自 iOS 26 起已废弃；而把两段先拼成 `String` 再交给
                //  `Text(_:)` 会丢掉各自的样式 —— 见 `PinRow` 的同款写法）。
                Text("\(ownerText)\(nameText)")
                    .font(Theme.Font.rowTitle)
                    .lineLimit(1)

                // 简介为空时原型写 `—`（演示数据里 `r.d` 可能为空）。
                Text(hit.description ?? "—")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .lineLimit(1)
                    // 原型 `margin-top:3px`：4pt 阶里没有 3 这一档，写原值。
                    .padding(.top, 3)

                chips
                    // 原型 `margin-top:6px`。
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var ownerText: Text {
        Text("\(hit.owner)/")
            .foregroundStyle(Theme.Palette.textTertiary)
            .fontWeight(.medium)
    }

    private var nameText: Text {
        Text(hit.name)
            .foregroundStyle(Theme.Palette.textPrimary)
            .fontWeight(.semibold)
    }

    /// `Swift`（带语言色点）与 `2,341`（带星形）两个 chip（原型 `.chip`：11px / 次级文字色）。
    ///
    /// ⚠️ 语言为 `nil` 时**整块不渲染**，不是画一个灰点：`LanguageColor.fallback`
    /// 就是给"未知语言"的灰，而"这个仓库没有主语言"与"语言名我们认不出"
    /// 在屏幕上会得到同一个点 —— 那是把"不知道"画成了"知道"。
    /// 这里选择少画一格（与 `SearchRow` 对可选字段的一贯口径一致）。
    private var chips: some View {
        HStack(spacing: Theme.Spacing.m) {
            if let language = hit.language, !language.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    Circle()
                        .fill(LanguageColor.color(for: language))
                        .frame(width: 9, height: 9)
                    Text(language)
                }
            }

            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "star")
                    .font(.system(size: 13))
                    .accessibilityHidden(true)
                Text(hit.starLabel)
            }
        }
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.Palette.textSecondary)
    }
}

// MARK: - 用户

/// 用户结果行（原型 `userResultRow`）。
///
/// 形状：`UserAvatar`（34）+ 「昵称 + @登录名」+ 简介 + `N 个公开仓库 · M 关注者`。
///
/// ⚠️ 两处与仓库行**有意不同**（原型里就是这么分的，别顺手统一）：
/// - 人数用 **k/m 缩写**（`210k`），与仓库 Star 的千分位不是一套；
/// - 副标题**可能整段不存在** —— `/search/users` 未必返回那两个计数（见 `UserHit.metaLabel`）。
struct UserResultRow: View {

    let hit: UserHit

    var body: some View {
        SearchRowBox {
            UserAvatar(login: hit.login)

            VStack(alignment: .leading, spacing: 0) {
                title
                    .font(Theme.Font.rowTitle)
                    .lineLimit(1)

                if let bio = hit.bio, !bio.isEmpty {
                    Text(bio)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .lineLimit(1)
                        .padding(.top, 3)
                }

                if let meta = hit.metaLabel {
                    Text(meta)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        // 原型 `margin-top:4px`（与简介那处 3px 不同，就照它写）。
                        .padding(.top, Theme.Spacing.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 「昵称 @登录名」。**昵称为空时只留 `@登录名`** ——
    /// 原型直接拼 `x.n`，遇到没填昵称的人会印出 `undefined`（它的演示数据里都有昵称）。
    private var title: Text {
        guard let name = hit.name, !name.isEmpty else { return Text(hit.handle) }
        return Text(
            "\(Text(name).foregroundStyle(Theme.Palette.textPrimary).fontWeight(.semibold)) \(Text(hit.handle).foregroundStyle(Theme.Palette.textTertiary).fontWeight(.medium))"
        )
    }
}

// MARK: - 代码

/// 代码结果行（原型 `codeResultRow`）。
///
/// 形状：文件图标 + 路径 + `{仓库} · {语言}` + 等宽预览行。
///
/// ⚠️ **它没有尖角** —— 原型这一行就没画（`.sr-item` 的最后一个元素是内容，不是 `I.chev`）。
/// 别的四种行都有，所以这一处很容易"顺手补上"，而补了就与原型不一致。
/// （⚠️ 2026-10-16 起所有行都不再自绘尖角，这一条差别随之消失 —— 但这行仍然**不该**被
/// 特殊对待：它现在是普通的 `NavigationLink` 行，系统给的箭头与其他三行一模一样。）
///
/// ⚠️ 对齐是 `.top`（原型这一行单独加了 `align-items:flex-start`）。
struct CodeResultRow: View {

    let hit: CodeHit

    var body: some View {
        SearchRowBox(alignment: .top) {
            Image(systemName: "doc.text")
                .font(.system(size: 16))
                .foregroundStyle(Theme.Palette.textTertiary)
                // 图标不参与压缩（同 `LinkRow` 的做法）。
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                // 原型 `font-size:13.5px; word-break:break-all` —— 路径**折行**而不是截尾，
                // 所以这里不加 `lineLimit`：长路径在原型上就是会占两行。
                // 13.5px 落到本仓最近的一档是 `footnote`(13)。
                Text(hit.path)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Palette.textPrimary)

                Text(hit.metaLabel)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.top, 3)

                // 预览行来自 `text_matches`，请求没带那个媒体类型时它就不存在 ⇒
                // 整块不渲染，而不是画一个空框（见 `CodeHit.snippet`）。
                if let snippet = hit.snippet, !snippet.isEmpty {
                    CodePreviewLine(text: snippet)
                        // 原型 `.sr-code{margin-top:5px}`。
                        .padding(.top, 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Issue / PR

/// Issue / PR 结果行（原型 `convResultRow`）。
///
/// 形状：状态图标 + 标题 + `{仓库} #{编号} · {时间}` + 状态胶囊。
///
/// ## ⚠️ 状态图标：PR 那一半**复用** `PullCard` 的映射，不重写
///
/// 同一个 `PullRequestState` 在探索 PR 列表与搜索结果里必须是**同一套图标**，
/// 各写一份必然分叉（"已合并"在一处带汇合箭头、另一处不带）。所以 PR 走
/// `PullCard.icon(for:)` / `PullCard.tint(for:)`（同 target，直接调用）。
///
/// ## ⚠️ 状态胶囊的**族**由领域层算
///
/// 「已关闭的 Issue 是紫族、已关闭未合并的 PR 才是红族」这条规则在
/// `ConversationHit.statusTone`（可单测）里；这里只做一次显式翻译。
///
/// ## ⚠️ 与原型的一处有意偏差
///
/// 原型这一行的图标只按 `kind` 二分（`kind==='pr'` 一律画分支箭头，连已合并的也是），
/// 而我们按**状态**给（已合并 ⇒ 汇合箭头）。理由是同一 App 内的**一致性**：
/// 探索 PR 列表（切片 4 已验收）对已合并的 PR 画的就是汇合箭头，
/// 搜索页画成别的会让用户以为看错了。已登记，待裁定。
struct ConversationResultRow: View {

    let hit: ConversationHit
    let now: Date

    var body: some View {
        SearchRowBox {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                // 原型 `font-size:13.5px` ⇒ `footnote`(13)。
                Text(hit.title)
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(2)

                Text(hit.metaLabel(now: now))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            StatusPill(title: hit.statePillTitle, tone: pillTone)
        }
        // 读屏时**先说中文状态**。不给这一句的话，念出来的是胶囊上的英文
        // `Open` —— 而这一页其余部分全是中文（`stateLabel` 就是为这件事存在的）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(hit.stateLabel) · \(hit.title)，\(hit.metaLabel(now: now))"
        )
    }

    // MARK: - 状态 → 图标 / 配色 / 胶囊族

    private var icon: String {
        switch hit.kind {
        case .issue: hit.state == .open ? StateIcon.issueOpen : StateIcon.issueClosed
        case .pullRequest: PullCard.icon(for: hit.state)
        }
    }

    private var tint: Color {
        switch hit.statusTone {
        case .open: Theme.Palette.stateOpenIcon
        case .completed: Theme.Palette.stateCompletedIcon
        case .closed: Theme.Palette.stateClosed
        }
    }

    /// 领域层的「族」→ 设计包的「配色档」。两侧名字不同是有意的
    /// （见 `ConversationStatusTone` 的说明），这里是一次显式翻译。
    private var pillTone: StatusPill.Tone {
        switch hit.statusTone {
        case .open: .open
        case .completed: .merged
        case .closed: .closed
        }
    }
}

#Preview {
    @Previewable @State var now = Date()

    // 它现在是 `List` 的行内容 ⇒ 预览也按 `List` 摆。
    List {
        SearchRowView(
            row: .repository(RepositoryHit(
                fullName: "my-git/gitduo",
                description: "iOS 第三方 GitHub 客户端 · SwiftUI",
                language: "Swift",
                starCount: 2_341
            )),
            now: now
        )

        SearchRowView(
            row: .repository(RepositoryHit(fullName: "nicedoc/mdx-engine", starCount: 5_102)),
            now: now
        )

        SearchRowView(
            row: .user(UserHit(
                login: "dev-j", name: "jiangjiang", bio: "my-git · iOS / SwiftUI 开发",
                publicRepoCount: 3, followerCount: 21
            )),
            now: now
        )

        // 两个计数都查不到 ⇒ 副标题整段不渲染（不是显示 0）。
        SearchRowView(
            row: .user(UserHit(login: "torvalds", name: "Linus Torvalds")),
            now: now
        )

        SearchRowView(
            row: .code(CodeHit(
                path: "Packages/GitDuoKit/Sources/GitHubAPI/GitHubClient.swift",
                repoFullName: "my-git/gitduo",
                language: "Swift",
                snippet: "let client = GitHubClient(token: store.load())"
            )),
            now: now
        )

        // 预览行缺失（请求没带 `text-match`）⇒ 不画空框。
        SearchRowView(
            row: .code(CodeHit(path: "README.md", repoFullName: "o/r", language: nil)),
            now: now
        )

        // 三族各一条 —— 注意两条 `.closed` 的**颜色不同**（Issue 紫 / PR 红）。
        SearchRowView(
            row: .conversation(ConversationHit(
                kind: .issue, number: 35, title: "Markdown 列表渲染缩进错误",
                repoFullName: "my-git/gitduo", state: .closed, updatedAt: now.addingTimeInterval(-259_200)
            )),
            now: now
        )

        SearchRowView(
            row: .conversation(ConversationHit(
                kind: .pullRequest, number: 57, title: "feat: 仓库详情四分区导航",
                repoFullName: "my-git/gitduo", state: .open, updatedAt: now.addingTimeInterval(-7_200)
            )),
            now: now
        )

        SearchRowView(
            row: .conversation(ConversationHit(
                kind: .pullRequest, number: 51, title: "fix: OAuth 回调地址校验",
                repoFullName: "my-git/gitduo", state: .merged, updatedAt: now.addingTimeInterval(-259_200)
            )),
            now: now
        )
    }
}
