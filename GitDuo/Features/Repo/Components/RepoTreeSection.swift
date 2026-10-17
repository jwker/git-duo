import GitHubAPI
import GitDuoDesign
import GitDuoKit
import SwiftUI

/// **目录浏览分区** —— 面包屑 + 文件行（原型 `05-repo.js` 的 `codeBodyHTML`）。
///
/// ## ⚠️ 2026-10-14：它从"两页各一份"收成**只有一个调用方**（走查第 63 条）
///
/// 此前 §4.4「代码」分区与 §4.13 第 ⑤ / ⑥ 分区各渲染一份；现在两处都收进了
/// **同一个代码页**（`RepoCodeView`，只读态由 `readOnly` 决定）⇒ 本件不再需要协调
/// "两页长得不一样"。原型侧同步改了：`exploreTree` 删除，两档共用 `SCR.repoCode`。
///
/// ## ⚠️ 同日：README 那一块**搬走了**（用户要求 README 进仓库首页）
///
/// 它原先长在本分区里（"面包屑 + 文件行 + README"三块）—— 现在 README 画在
/// **两个首页**上（`RepoReadmeSection`，§4.4 四行入口之下 / §4.13 入口行之后）。
/// ⇒ 本件只剩**面包屑 + 文件行**两件事，形状反而更贴合"目录浏览"这个名字。
/// 连带：`LoadRepoTree` 不再取 README、`RepoTreePage.readme` 字段退役。
///
/// ## ⚠️ 同日再收一次：`title` 与 `trailing` 两个参数**一起删了**（用户裁定）
///
/// 收了唯一调用方之后，这两个参数都成了死参数：
///
/// | 参数 | 什么时候变死的 |
/// |---|---|
/// | `title`（分区标题）| 代码页**不画**分区标题（那正是它省下空间的地方之一）⇒ 收进唯一调用方那一刻起就没人传 |
/// | `trailing`（面包屑右侧动作位）| 2026-10-14 那颗「⋯」搬到了**导航栏右上角**（用户要求与文件页统一）⇒ 两个档都不再传 |
///
/// 两个都删掉之后，本件**不再需要泛型参数**（原来那个 `<Trailing: View>` 只服务
/// `trailing`），成了一个普通 `struct`。留着它们等于"给下一个读的人一道判断题：
/// 这两个参数到底还有没有在用" —— 同 `FileCopy` 那次"失去唯一消费端的常量一并删除"。
///
/// ⚠️ 若哪天又要把它当**通用分区**用（比如在仓库首页内嵌一段目录浏览），
/// 那时再加回需要的参数 —— 而不是现在留两个没人传的开口。
///
/// ## ⚠️ 2026-10-16 起回到 `ScrollView`（本轮修复）
///
/// P3 第二批曾把文件行装进 `List`；实测回归：面包屑宽度变窄、与文件行不对齐。
/// 原因是面包屑与文件行**自带几何**（内边距 / 底色），坐在 `List` 行里会被系统
/// 行内边距再缩一次。⇒ 本件恢复为 `VStack` + `CardBox` 装文件行；面包屑直接
/// 放在 `VStack` 里，宽度与文件行一致。
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
struct RepoTreeSection: View {

    let session: RepoTreeSession

    /// 点一个目录 —— 参数是目标路径，调用方负责推入。
    let onOpenDirectory: (RepoPath) -> Void

    /// 点一个文件 —— 参数是文件路径。
    let onOpenFile: (RepoPath) -> Void

    let onTapBranch: () -> Void

    /// 点面包屑上某一层。参数是 `path` 的下标（**第 0 段是仓库全名**）。
    let onSelectSegment: (Int) -> Void

    @Environment(\.openURL) private var openURL
    @Environment(AppEnvironment.self) private var env

    init(
        session: RepoTreeSession,
        onOpenDirectory: @escaping (RepoPath) -> Void,
        onOpenFile: @escaping (RepoPath) -> Void,
        onTapBranch: @escaping () -> Void,
        onSelectSegment: @escaping (Int) -> Void
    ) {
        self.session = session
        self.onOpenDirectory = onOpenDirectory
        self.onOpenFile = onOpenFile
        self.onTapBranch = onTapBranch
        self.onSelectSegment = onSelectSegment
    }

    var body: some View {
        switch session.page.presentation {
        case .skeleton:
            skeleton

        case .content:
            if let page = session.page.value {
                VStack(alignment: .leading, spacing: 0) {
                    breadcrumb(page)
                        // 原型 `.crumb{margin-bottom:8px}`。
                        .padding(.bottom, Theme.Spacing.s)

                    content(page)
                }
            }

        case let .failure(error):
            failure(error)
        }
    }

    // MARK: - 主体

    private func content(_ page: RepoTreePage) -> some View {
        CardBox() {
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
                        // 原型的规则是"除最后一条之外都画"（底线件）。
                        showsSeparator: index < page.entries.count - 1
                    ) {
                        open(entry)
                    }
                }
            }
        }
    }

    /// 面包屑条：分支胶囊 + `仓库全名 / … / 当前层`。
    ///
    /// ⚠️ **2026-10-14 起右端没有动作位了** —— 那颗「⋯」搬到了代码页的导航栏右上角
    /// （`RepoCodeView.levelMenu`，与文件页同形）。`BreadcrumbBar` 那边对应的
    /// `trailing` 槽也一并删除。
    private func breadcrumb(_ page: RepoTreePage) -> some View {
        // ⚠️ `path` 的**第 0 段是仓库全名**（原型把仓库名当作路径的第一段，
        //    `codeGo('')` 回到仓库根那一层）⇒ 根目录下 `path.count == 1`。
        BreadcrumbBar(
            branch: page.branch,
            path: [session.fullName] + session.path.components,
            onTapBranch: onTapBranch,
            onSelectSegment: onSelectSegment
        )
    }

    // ⚠️ README 那一块（原 `readmeSection(_:)`，约 60 行）**2026-10-14 整体搬走了**
    //    —— 它现在画在两个**首页**上（`RepoReadmeSection`，§4.4 四行入口之下 /
    //    §4.13 入口行之后）。它不该是"进了代码页才看得到"的东西：
    //    README 是"这个仓库是什么"，而代码页回答的是"里面有什么文件"。
    //    连带的取数变化见 `LoadRepoTree`（它不再取 README）。

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

    /// 本分区首屏的骨架。
    ///
    /// ⚠️ **形状与尺寸纪律都在 `RepoTreeSkeleton` 里**（2026-10-09 切片 10 收口）：
    /// 代码页（§4.4.1）与 §4.13 用的就是本视图，而 `RepoDetailView` 在代码浏览
    /// 还嵌在它里面那会儿**自己又抄了一份逐字相同的骨架** ⇒ 现在两边共用 `RepoTreeSkeleton`。
    /// 本件只是把它接在这里（写法与原先一致）。
    private var skeleton: some View {
        RepoTreeSkeleton()
    }

    /// 分区内的失败 —— 内容区里的一小块，**不掀翻整页**（§8.5）。
    ///
    /// ⚠️ **2026-10-14：它此前是本文件里一份逐字重复的实现** —— 文案、布局、
    /// 读屏 hint 与 `SectionFailure` 一模一样（那是那个共用件被提出来时**漏掉的一个
    /// 调用方**：它当年服务的是「代码 / Commits / Issues / PR」四段，而本件
    /// 在改造中换过几次外壳，这一份就留了下来）。现在改成直接用共用件，
    /// 本件自带的那个 `failureHint` 静态函数随之删除（它与 `SectionFailure.hint(for:)`
    /// 同一张表 —— 留着就意味着"改了一处、另一处还是旧话术"）。
    private func failure(_ error: GitHubError) -> some View {
        SectionFailure(error: error) {
            Task { await session.reload() }
        }
    }
}
