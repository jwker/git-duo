import GitHubAPI
import GitDuoDesign
import GitDuoKit
import SwiftUI

/// **目录浏览分区** —— 面包屑 + 文件行 + README 三块（原型 `05-repo.js` 的代码分区
/// 与 `10-explore-repo.js` 的 `exploreTree`）。
///
/// ## 为什么它是一件共享件
///
/// §4.4「代码」分区与 §4.13 第 ⑤ / ⑥ 分区渲染的是**同一件事**：一条面包屑、
/// 一列目录条目、一份 README。原型这两处的 HTML 结构逐行对应，差别只有两处：
///
/// | | §4.4（自己的仓库） | §4.13（他人仓库） |
/// |---|---|---|
/// | 面包屑右侧 | 「＋ 添加」 | **无** |
/// | 分区标题 | **无**（顶部有分段条） | `文件浏览 · {path}` 与 `README.md` |
/// | 点一行 | 进 `repoDetail` / `fileView(readOnly: false)` | 进 `exploreRepoDetail` / `fileView(readOnly: true)` |
///
/// 前两处由参数表达（`title` / `trailing`），第三处由两个闭包表达。
/// 三处之外的一切（间距、字号、空目录那一句、README 的渲染）只有这一份 ——
/// 抄一份的话，"把空目录的灰字改成居中"这种改动只会落到其中一页。
///
/// ## 判据 #43：它留 Feature（不进设计包）
///
/// 它收 `RepoTreeSession`（领域模型 + 取数状态）⇒ 不进 `GitDuoDesign`。
/// 设计包里只有 `BreadcrumbBar`（只收 `branch` / `path` 两个基础类型）。
///
/// ## ⚠️ 它替调用方处理 `symlink` / `submodule`
///
/// 那两类条目（`TreeEntry.Kind.unsupported`）的内容在 App 里读不对 ——
/// 链接条目拿到的是目标那串文本、子模块的 `sha` 属于另一个仓库。
/// 所以它们的处置（出一句提示 + 跳网页端）收在本件里，`onOpen*` 两个闭包
/// **只会收到目录与文件** ⇒ 调用方不必再判一次 `kind`，
/// 也就不会出现"两页各判一次、其中一页漏判"。
struct RepoTreeSection<Trailing: View>: View {

    let session: RepoTreeSession

    /// 分区标题。`nil` = 不画（§4.4 靠顶部的分段条表明身份）。
    /// §4.13 传 `文件浏览 · {path}`。
    let title: String?

    /// 点一个目录 —— 参数是目标路径，调用方负责推入。
    let onOpenDirectory: (RepoPath) -> Void

    /// 点一个文件 —— 参数是文件路径。
    let onOpenFile: (RepoPath) -> Void

    let onTapBranch: () -> Void

    /// 点面包屑上某一层。参数是 `path` 的下标（**第 0 段是仓库全名**）。
    let onSelectSegment: (Int) -> Void

    private let trailing: Trailing

    @Environment(\.openURL) private var openURL
    @Environment(AppEnvironment.self) private var env

    init(
        session: RepoTreeSession,
        title: String? = nil,
        onOpenDirectory: @escaping (RepoPath) -> Void,
        onOpenFile: @escaping (RepoPath) -> Void,
        onTapBranch: @escaping () -> Void,
        onSelectSegment: @escaping (Int) -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.session = session
        self.title = title
        self.onOpenDirectory = onOpenDirectory
        self.onOpenFile = onOpenFile
        self.onTapBranch = onTapBranch
        self.onSelectSegment = onSelectSegment
        self.trailing = trailing()
    }

    var body: some View {
        switch session.page.presentation {
        case .skeleton:
            skeleton

        case .content:
            if let page = session.page.value {
                if let title {
                    SectionHeader(title: title)
                }
                content(page)
            }

        case let .failure(error):
            failure(error)
        }
    }

    // MARK: - 主体

    private func content(_ page: RepoTreePage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            breadcrumb(page)
                // 原型 `.crumb{margin-bottom:8px}`。
                .padding(.bottom, Theme.Spacing.s)

            CardBox(vertical: Theme.Spacing.xs, horizontal: 14) {
                if page.entries.isEmpty {
                    // 原型：`<div class="t3" style="padding:16px 8px;text-align:center">空目录</div>`
                    // ——**它也在卡片里面**（不是卡片外的一句提示）。
                    Text(RepoCopy.emptyDirectory)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.l)
                        .padding(.horizontal, Theme.Spacing.s)
                } else {
                    ForEach(Array(page.entries.enumerated()), id: \.element.id) { index, entry in
                        RepoFileRow(
                            entry: entry,
                            showsSeparator: index < page.entries.count - 1
                        ) {
                            open(entry)
                        }
                    }
                }
            }

            readmeSection(page)
        }
    }

    /// 面包屑条：分支胶囊 + `仓库全名 / … / 当前层`（+ 调用方的右侧动作位）。
    private func breadcrumb(_ page: RepoTreePage) -> some View {
        // ⚠️ `path` 的**第 0 段是仓库全名**（原型把仓库名当作路径的第一段，
        //    `navToSub('')` 回到根目录）⇒ 根目录下 `path.count == 1`。
        BreadcrumbBar(
            branch: page.branch,
            path: [session.fullName] + session.path.components,
            onTapBranch: onTapBranch,
            onSelectSegment: onSelectSegment
        ) {
            trailing
        }
    }

    /// 根目录下的 README 区块。
    ///
    /// ⚠️ **只有根目录有** —— `LoadRepoTree.fetch` 有意只在根目录问 `readme`
    /// 端点（在任何子目录下问它都会拿到同一份仓库级 README，
    /// 而那不是"这个目录的说明"）。所以这里不再判一次路径。
    @ViewBuilder
    private func readmeSection(_ page: RepoTreePage) -> some View {
        if let readme = page.readme, !readme.isEmpty {
            // ⚠️ 小节标题取 `RepoCopy.readmeSectionTitle`（字面 `README.md`）——
            //    §4.13 原先另有一个 `ExploreRepoCopy.readmeSection`，值与它**完全相同**，
            //    6.4 合并成一处（同一个标题在两个页面上不可能该长得不一样）。
            SectionHeader(title: RepoCopy.readmeSectionTitle)
            // ⚠️ 解析（`MarkdownParser`）在取数层已经做完 —— `MarkdownDocument`
            //    带的是算好的块。视图只负责画，不在 `body` 里重扫全文。
            //
            // ⚠️ 链接要**在这里接一次线**（2026-10-07 目视发现的第 3 条）：
            //    README 里大量链接是仓库内的相对地址（`[中文](README_zh.md)`），
            //    系统打不开一个没有 scheme 的地址 ⇒ 表现为"点了没反应"。
            //    判据（哪一档去哪儿）全在领域层的 `RepoLinkResolver`，这里只做分派 ——
            //    两页（§4.4 / §4.13）共用本件，接线也只有这一处。
            MarkdownBody(blocks: readme.blocks) { url in
                switch RepoLinkResolver.target(
                    for: url,
                    fullName: session.fullName,
                    // README 画在**它所在的那个目录**下，所以基准就是当前目录
                    // （`LoadRepoTree` 只在根目录问 `readme` 端点，见上一层说明）。
                    baseDirectory: session.path
                ) {
                case let .file(path):
                    onOpenFile(path)
                    return .handled

                case let .directory(path):
                    onOpenDirectory(path)
                    return .handled

                case .external:
                    // 外部地址必须落到系统，否则 README 里所有外链会一起静默失效。
                    return .systemAction

                case .anchor, .unresolved:
                    // 两档都**没有落点**（页内锚点这一版不做；相对地址跳出仓库根时
                    // 猜不出它想去哪儿）。`.discarded` 是"我们要过它、并决定不跳"，
                    // 比 `.handled` 诚实 —— 后者声称"已经处理了"。
                    return .discarded
                }
            }
        }
    }

    // MARK: - 点一行

    /// ⚠️ `symlink` / `submodule` **在这里被拦下**（见类型说明）——
    /// `onOpen*` 两个闭包只会收到可进入的条目。
    private func open(_ entry: TreeEntry) {
        guard entry.kind.isNavigable else {
            // ⚠️ 先出提示再开浏览器：`openURL` 会把 App 切到后台，
            //    而提示挂在本 App 上 —— 反过来那句话用户多半看不到。
            env.toast.show(RepoCopy.unsupportedEntryToast)
            if let url = RepoWebLinks.blob(
                fullName: session.fullName,
                ref: session.branch ?? "HEAD",
                path: entry.path
            ) {
                openURL(url)
            }
            return
        }

        switch entry.kind {
        case .directory: onOpenDirectory(entry.path)
        case .file: onOpenFile(entry.path)
        // 上面那个 `guard` 已经排除了它；这一支只是为了让 switch 穷尽 ——
        // 删掉它，将来给 `Kind` 加一档时这里会静默落到"什么都不做"。
        case .unsupported: return
        }
    }

    // MARK: - 骨架 / 失败

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SkeletonBar(height: 32)
            CardBox(vertical: Theme.Spacing.m, horizontal: 14) {
                ForEach(0..<6, id: \.self) { _ in
                    SkeletonBar(height: 15, width: 190)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// 分区内的失败 —— 内容区里的一小块，**不掀翻整页**（§8.5）。
    private func failure(_ error: GitHubError) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("这一块加载失败")
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
            Button("重试") {
                Task { await session.reload() }
            }
            .font(Theme.Font.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Self.failureHint(error))
    }

    private static func failureHint(_ error: GitHubError) -> String {
        switch error {
        case .transport: "网络不可用"
        case .rateLimited: "请求过于频繁"
        case .unauthorized: "登录状态已失效"
        default: "服务暂时不可用"
        }
    }
}

extension RepoTreeSection where Trailing == EmptyView {

    /// 面包屑右侧没有动作位的那一种（§4.13 的他人仓库就没有「＋ 添加」）。
    init(
        session: RepoTreeSession,
        title: String? = nil,
        onOpenDirectory: @escaping (RepoPath) -> Void,
        onOpenFile: @escaping (RepoPath) -> Void,
        onTapBranch: @escaping () -> Void,
        onSelectSegment: @escaping (Int) -> Void
    ) {
        self.init(
            session: session,
            title: title,
            onOpenDirectory: onOpenDirectory,
            onOpenFile: onOpenFile,
            onTapBranch: onTapBranch,
            onSelectSegment: onSelectSegment,
            trailing: { EmptyView() }
        )
    }
}
