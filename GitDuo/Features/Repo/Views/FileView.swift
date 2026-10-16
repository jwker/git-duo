import GitHubAPI
import GitDuoDesign
import GitDuoKit
import SwiftUI
import UIKit

/// 文件查看页（PRD §4.5、原型 `SCR.fileView`、TECH_SPEC §9.5）。
///
/// ## 它只有一件事必须做对：三档结局要**长得不一样**
///
/// | 结局 | 界面 |
/// |---|---|
/// | `.content(.text)` | `CodeSurface` 代码块（按扩展名着色，认不出语言 ⇒ 纯文本）；**`.md` / `.markdown` 例外 —— 渲染成 markdown** |
/// | `.content(.image)` | 图片（原始比例、限宽） |
/// | `.unsupported(reason)` | 「无法预览」+ **跳网页端出口**（**没下载**） |
/// | `.undecodable` | 「编码不认识」+ 跳网页端出口（**下载了**） |
///
/// ## ⚠️ `.md` / `.markdown` 走 markdown 渲染是 **2026-10-12 用户要求新增的**（第 57 条）
///
/// 起初**所有文本都走代码块**，`.md` 也不例外 —— 而那是**照原型与 PRD 做的**：
/// 原型 `SCR.fileView` 的正文写死成一个代码块、演示数据是 Swift 文件
/// （**一次都没展示过"打开一个 `.md`"**），`PRD §4.5` 第 2 条也只写「代码块」。
/// 用户报回「md 没有进行格式渲染」⇒ 这是**加了一件原型从来没有的东西**，登记在第 57 条。
///
/// 分岔**不在这一层**：`FileContent.markdown` 非空就走 `MarkdownBody`，
/// 而"哪种扩展名算 markdown"的判据在领域层 `MarkdownFile`（有单测）。
///
/// 后两者合成一块的后果写在 `FileViewOutcome` 的类型说明里：文案总有一边是假话。
/// 所以本视图里那两块虽然**共用同一套版式**（`noticeState`），
/// 但**那一句说明必须从两个不同的常量来**，且不在这里用 `if` 互相顶替。
///
/// ## ⚠️ 分支由 `FileViewModel` 自己解析（路由不带它）
///
/// 见 `FileViewModel` 的类型说明。视图这里只把解析出来的分支画在面包屑上，
/// **不参与**"该用哪条 ref"的判定。
///
/// ## ⚠️ 操作按钮 2026-10-13 起收进**右上角那颗「⋯」菜单**（走查第 62 条）
///
/// 此前是正文下方一条居中的操作行（原型 `SCR.fileView` 的
/// `.row{justify-content:center;gap:10px;margin-top:14px}`）。用户要求
/// 「把底部的操作按钮都放入『...』的按钮打开的菜单中，并且这个『...』按钮放到右上角，
/// 就像其他页面的搜索按钮的位置」⇒ 现在走 **`ToolbarItem(placement: .topBarTrailing)`
/// + 系统原生 `Menu`** —— 与首页 / 探索 / 仓库三页右上角那颗搜索按钮**同一个位置、
/// 同一套控件**（UIKit 里那颗叫 `UIBarButtonItem`，带菜单的就是 `UIMenu`）。
///
/// ⚠️ **原型这一屏仍是底部一行**（`历史` / `Raw` / `更多` 三颗都在那儿）⇒
/// 这一处**有意偏离原型**，逐条登记在第 62 条。
///
/// | 菜单项 | 什么时候出现 | 做什么 |
/// |---|---|---|
/// | `编辑` | 自己的仓库**且这一屏拿到了内容** | 推入编辑器（§4.6 编辑模式） |
/// | `重命名` | 自己的仓库**且有内容** | 打开 §5.16 |
/// | `复制路径` / `复制文件名` | **总是出现**（只要在文件页） | 本地复制，零请求（2026-10-12 新增，第 56 条） |
/// | `复制原文` | 正文是**文本**时（`model.canCopyRaw`） | 决策 #51 的两处例外之一，零请求 |
/// | `删除文件` | 自己的仓库**且有内容** | 打开 §5.17（**危险色**） |
///
/// ### ⚠️ 两件"这一版就不做"的**从界面上撤下了**（用户 2026-10-13 裁定）
///
/// `历史`（PRD §4.5 标 ⏳）与**他人仓库**那颗 `⑂ Fork 后可编辑`。原实现把它们
/// 「画出来但不可点」（决策 #51 的形态），而**菜单里放一颗点不动的项**只表达得出
/// "暂时不可用" —— 与"这一版压根不做"分不开。用户在"照常可点但点了给说明 / 由系统灰掉 /
/// 不放进菜单"三档里选了**不放进菜单** ⇒ 界面上一处都不再提示这两个入口存在。
///
/// ⚠️ **代价如实登记**：`FileCopy` 里 `historyAction` / `historyUnavailableHint` /
/// `forkToEditAction` / `forkToEditUnavailableHint` 四个常量与它们的读屏 hint **一并删除**
/// （失去唯一消费端的常量留着，只会让下一个读的人先去判断"它是不是还在用" ——
/// 同 `GitHubIcon` 那条"有意没有"的处置）。
///
/// ### ⚠️ 唯一保留的"不可点"是「编辑」那两档（图片 / >1MB 的文本）
///
/// 它与上面那两件**性质不同**：功能**已经实现**，只是**这个文件不适用**
/// （编辑器是文本编辑器；>1MB 走不了 `PUT contents`）。菜单里的项只能靠系统灰
/// （`.disabled`）表达"当前不适用"，这与决策 #51「不用灰」在字面上分岔 ——
/// 那条的理由是"灰色像暂时坏了"，而这里"不适用"**正是**要说的意思。
/// 那句"为什么"仍然只有一个落点：`EditorCopy.editHint(for:)`，挂在这颗项的读屏 hint 上。
///
/// ⚠️ **与「复制原文」的处置有意不同**，别对齐：`复制原文` 在图片 / 二进制上是**整项不出现**
/// （那种文件连"原文"这个东西都没有，谈不上"不适用"），而这是**项目既有**的写法。
///
/// ## ⚠️ 「编辑」不可点的那两档，理由是**不同的两句话**
///
/// - **超过 1MB 的文本**（决策 #54 的边界、`REVIEW-CHECKLIST` 偏差 32）：
///   文件**能看**（走 raw），不能的只是"在 App 里改它"；
/// - **图片**：编辑器是**文本**编辑器，一张 png 在哪儿都编辑不了。
///
/// 合成一句"暂不可编辑"会让其中一档说出**假话**（用户会去网页端找一个
/// "压缩一下就能编辑"的办法）。两句话的落点收在 `EditorCopy.editHint(for:)` 一处。
///
/// ## ⚠️ 两处「规格未给，待评审」（本片新增，已登记）
///
/// 1. **页脚只在"看得了"时出现**。PRD §4.5 的权限差异表是按"能看的文件"写的，
///    没有覆盖"看不了"的两档 —— 那两档只给网页端出口，那正是 PRD §4.5
///    为它们规定的动作。
///    ⚠️ **2026-10-13 起这一条只管页脚了**（第 62 条）：操作行搬进了右上角那颗「⋯」，
///    而**菜单在四种状态下都画得出来** ⇒ 里面的项改由 `model.hasContent` 逐项把关
///    （见 `operationsMenu`），不再靠"整块不画"。
/// 2. 图片字节解不成图片时（扩展名说 png、字节不是 png）落到 `.undecodable` 那块，
///    而那句 `undecodableTextHint` 的措辞是"无法显示为**文本**"。这一档在服务端
///    行为正常时到不了（`LoadFileContent` 只在扩展名说它是图片时才走图片通道）。
struct FileView: View {

    let fullName: String
    let readOnly: Bool

    @Environment(\.openURL) private var openURL

    /// 导航（推入编辑器）与弹层的宿主。
    ///
    /// ⚠️ 本页的**依赖**（取数 / 写通道 / 记忆 / 提示）仍然由调用方逐条传进来，
    /// 这里只取 UI 通道 —— 与 `RepoDetailView` 的分工逐字相同（AGENTS.md §3 的铁律）。
    @Environment(AppEnvironment.self) private var env

    @State private var model: FileViewModel

    /// ⚠️ **不是在弹层的回调里直接 `pop()`**。
    ///
    /// 弹层正挂在**本页**身上，而本页就是栈顶 —— 先把栈顶弹掉，弹层会被一起掀掉
    /// （没有下滑动画、导航栏闪一下）。所以这个标记只是"记下要往回走"，
    /// 真正的 `pop()` 放在 `.sheet(onDismiss:)` 里：那一刻弹层已经关完了。
    @State private var popsAfterDismissal = false

    init(
        fullName: String,
        path: RepoPath,
        readOnly: Bool,
        loader: LoadFileContent,
        detail: LoadRepoDetail,
        memory: any BranchMemoryStore,
        renameFile: RenameFile,
        deleteFile: DeleteFile,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.readOnly = readOnly
        _model = State(initialValue: FileViewModel(
            fullName: fullName,
            path: path,
            // ⚠️ 路由只带 `fullName` / `path` / `readOnly` 三个参数（§8.2 正本）
            //    ⇒ 这两样这里**不知道**。代价如实说：`.largeText` / `.image`
            //    会多一个 RTT（先问一次 `contents` 拿 `sha` 与 `size`，再走 raw）。
            //    而 `LoadFileContent` 里那条"size 判小了就补一次 raw"的救援路
            //    正好覆盖"判成 `.text` 其实是空壳"的情形 —— 两条路都在。
            size: nil,
            blobSHA: nil,
            readOnly: readOnly,
            loader: loader,
            detail: detail,
            memory: memory,
            renameFile: renameFile,
            deleteFile: deleteFile,
            toast: toast
        ))
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Palette.background)
        // 标题就是文件名（原型这一屏的导航栏没有别的写法）。
        //
        // ⚠️ 取 `model.path` 而**不是**构造时传进来的那个路由参数：重命名成功之后
        //    这一页的路径会变（§5.16「返回文件查看页（该页路径跟着变）」），
        //    而路由上那一份是**进来时**的参数、不会跟着动。
        .navigationTitle(model.path.displayName)
        .navigationBarTitleDisplayMode(.inline)
        // 右上角那颗「⋯」—— 与首页 / 探索 / 仓库三页那颗搜索按钮**同一个位置、同一套控件**
        // （`ToolbarItem(placement: .topBarTrailing)`），差别只在 label 是个 `Menu`
        // 而不是一个 `Button`（2026-10-13 用户要求把底部操作行搬进来，第 62 条）。
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                operationsMenu
            }
        }
        .refreshable { await model.refresh() }
        .task { await model.start() }
        // 两张弹层由一个枚举驱动（同 `BranchesView`）—— 菜单里那两项各自要**换成**
        // 一张确认层，用布尔量表达就是"关一张、开一张"，而它中间的一帧是空屏。
        // ⚠️ **2026-10-13 起是三张变两张**：中间那张「文件操作」弹层撤掉了（第 62 条），
        //    重命名 / 删除现在是菜单里直接可点的两项。
        .sheet(item: $model.sheet, onDismiss: handleSheetDismissal) { route in
            presented(route)
                // ⚠️ 原型所有弹层都是**内容高度**（`.sheet{bottom:10px}` 自适应），
                //    而本仓从切片 1 起统一用 `.medium`（先例是那张"标题 + 说明 +
                //    两个整宽按钮"的确认卡 —— ⚠️ 它 2026-10-16 已换成系统 `.alert`，
                //    见 `HomeView`）。
                //    这两张都小，`.medium` 会留下半屏空白 —— 属既有偏差的延续，
                //    已登记到逐屏对照 21 里一起看（收口要一套"内容高度"约定，不由本片拍板）。
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    /// 弹层关完之后才做的事。
    ///
    /// ⚠️ 目前只有一件：**删除办妥之后往回走一层**（PRD §5.17「返回上一级目录列表」）。
    /// 重命名**不在这里** —— 它的"路径跟着变"落在 `model.path` 上，不换路由。
    private func handleSheetDismissal() {
        guard popsAfterDismissal else { return }
        popsAfterDismissal = false
        env.router.pop()
    }

    // MARK: - 弹层

    @ViewBuilder
    private func presented(_ route: FileViewModel.SheetRoute) -> some View {
        switch route {
        // ⚠️ **没有 `.operations` 了**（2026-10-13，第 62 条）：那张中间弹层撤掉，
        //    菜单里点「重命名」/「删除文件」直接落到下面这两张确认层中的一张。
        case .rename:
            RenameFileSheet(source: model.path, isWorking: model.isWorking) { input in
                await model.rename(input: input)
            }

        case .delete:
            DeleteFileSheet(
                fileName: model.path.displayName,
                // 说明里那句 `在 {分支} 上`。`branch` 在能预览的文件上必定有值
                // （`FileViewModel.load()` 先定 ref、再取内容），而这一屏只有能预览才进得来。
                branch: model.branch ?? "",
                isWorking: model.isWorking
            ) {
                // ⚠️ 标记要在 `await` **之后**才写对：失败（403 / 断网）时
                //    `confirmDelete()` 回 `false`，用户留在原地（文件还在，
                //    弹回目录列表会让他以为什么都没发生过）。
                popsAfterDismissal = await model.confirmDelete()
            }
        }
    }

    // MARK: - 主区域

    @ViewBuilder
    private var content: some View {
        switch model.outcome.presentation {
        case .skeleton:
            skeleton

        case .content:
            // `branch` 与 `outcome` 同时有值：`FileViewModel.load()` 先定 ref、再取文件。
            if let branch = model.branch, let outcome = model.outcome.value {
                VStack(alignment: .leading, spacing: 0) {
                    crumb(branch: branch)
                        // 原型 `.crumb{margin-bottom:8px}`。
                        .padding(.bottom, Theme.Spacing.s)

                    outcomeBody(outcome)
                }
            }

        case let .failure(error):
            failureState(error)
        }
    }

    /// 面包屑：`**{文件名}** · {分支}`（原型 `SCR.fileView` 逐字）。
    ///
    /// ⚠️ **与 `BreadcrumbBar` 不是同一个控件**，虽然类名都叫 `.crumb`：
    ///
    /// | | §4.4 代码分区 | §4.5 文件查看 |
    /// |---|---|---|
    /// | 首段 | 分支胶囊（可点、带 `▾`） | **文件名**（加粗、不可点） |
    /// | 路径 | 仓库全名 / … / 当前层 | **无** |
    /// | 右侧 | 「⋯」菜单（复制路径 / 添加文件） | **无**（2026-10-13 起撤下，第 62 条） |
    ///
    /// 合成一个控件就必须再加三个开关，而每个开关两档里总有一档是错的。
    ///
    /// ⚠️ 判据补充（2026-10-16，P2）：**"要不要合成一件"看的是功能，不是形状。**
    /// 这里的两件**功能不同**（一个是只读的路径显示、一个带分支胶囊与菜单）⇒ 不合并；
    /// 而 P2 里 `SectionTabs` 与 `SegmentedBar` **功能完全相同**（都是"切一档"）、
    /// 只差外观 ⇒ 那一对已经合并成一件（`SectionTabs` 已删）。
    ///
    /// ## ⚠️ 右端那颗「⋯」只活了 2026-10-12 一天（第 56 条 → 第 62 条）
    ///
    /// 那天按用户要求在这一行右端加了一颗「⋯」（菜单两项 = `复制路径` / `复制文件名`，
    /// 与仓库页面包屑那颗逐字同形）。**次日用户要求把底部操作行也收进「⋯」、
    /// 并把它摆到右上角** ⇒ 一屏两颗同名图标（一颗管路径、一颗管操作）没有道理，
    /// 用户裁定**并进右上角那颗**、这一行回到原型原样（`文件名 · 分支` 两个 `Text`）。
    ///
    /// ⚠️ 所以这一行现在是**逐字回到原型**的：没有动作位、没有 `Spacer`、
    /// 读屏合成直接做在最外层（不再需要"单独包一层"那个规避 —— 那个规避是为了
    /// 别把外层那颗按钮一起合成掉，现在外层没有按钮了）。
    ///
    /// ⚠️ 分支名 `lineLimit(1)`：分支名可以很长（`feature/客户XX-报价单改版`），
    /// 而文件名通常更长、更需要完整显示。
    private func crumb(branch: String) -> some View {
        // ⚠️ 与导航标题同源（`model.path`）—— 重命名之后两处一起跟着变。
        let display = model.path.displayName

        return HStack(spacing: 0) {
            Text(display)
                .font(Theme.Font.breadcrumb.weight(.semibold))
                .foregroundStyle(Theme.Palette.accent)

            Text(" · ")
                .font(Theme.Font.breadcrumb)
                .foregroundStyle(Theme.Palette.textSecondary)

            Text(branch)
                .font(Theme.Font.breadcrumb)
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
        }
        // 拼出来的那一串在读屏里是"文件名 空格 点 空格 分支"，粘在一起听不出层次。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(display)，当前分支 \(branch)")
        // 8 / 12：原型原值（`padding:8px 12px`）。
        .padding(.vertical, Theme.Spacing.s)
        .padding(.horizontal, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 方案 A：面包屑类条是**白块**（同 `BreadcrumbBar`：原型 `--card`、圆角 12、无边框）。
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.Palette.surface)
        )
    }

    // MARK: - 操作菜单（右上角 · 2026-10-13 新增，走查第 62 条）

    /// 右上角那颗「⋯」—— 原来那条底部操作行**整个搬进来了**。
    ///
    /// ## ⚠️ 位置与控件都是照着**根页右上角那一颗**做的
    ///
    /// `HomeView` 右上角有一颗 `ToolbarItem(placement: .topBarTrailing)` 的按钮
    /// —— 2026-10-16 起它是**头像**（进「我的」）；在那之前它是三处根页各一颗的
    /// 搜索放大镜（走查第 85 条把搜索搬去了底部 Tab）。
    /// 这里用的是**同一个位置**，label 从 `Button` 换成一个 `Menu`
    /// —— SwiftUI 会把它渲染成系统的菜单按钮（UIKit 的 `UIBarButtonItem` + `UIMenu`），
    /// **不用自己画底色 / 圆角 / 尺寸**（那正是 `crumbMenu` 当初要手画的原因：
    /// 它长在内容区里，系统不管它）。
    ///
    /// ## ⚠️ 六项的出现条件是**按"这一档能不能做"分的**，不是按仓库归属一刀切
    ///
    /// | 项 | 条件 | 为什么 |
    /// |---|---|---|
    /// | `编辑` | 自己的仓库 **且有内容** | 图片 / >1MB 那两档**画成灰项**（见下） |
    /// | `重命名` | 自己的仓库 **且有内容** | 那条写通道要取 sha；看都看不了的文件谈不上 |
    /// | `复制路径` / `复制文件名` | **恒有** | 只用 `path`（路由上就有），与内容无关 |
    /// | `复制原文` | `model.canCopyRaw` | 图片 / 二进制没有"原文" —— 与旧操作行同一判据 |
    /// | `删除文件` | 自己的仓库 **且有内容** | 同 `重命名` |
    ///
    /// ⚠️ **"有内容"这一条是必须的**：旧实现里整条操作行只画在 `.content` 那一条
    /// （`fileBody`）里 —— 骨架 / 失败 / 「无法预览」/「编码不认识」四档根本没有它。
    /// 而工具栏按钮**四种状态下都画得出来**（它挂在 `body` 上，不在 `content` 里）
    /// ⇒ 少了这道判据，一个二进制文件的菜单里会出现一颗能点的「编辑」，
    /// 点进去必然落到"这不是文本"那个失败态（用户一路点下来一件事都没做错）。
    /// 判据落在 `FileViewModel.hasContent` 一处。
    ///
    /// ## ⚠️ 「编辑」那两档用 `.disabled` —— 与决策 #51 字面分岔（见类型说明）
    ///
    /// 菜单项只能靠**系统灰**表达"当前不适用"，而灰项的读屏**也**点不动
    /// ⇒ 旧实现那条"闭包必须是真的什么都不做"的告诫在这里不适用
    /// （`allowsHitTesting` 那套是防"读屏能激活一个假按钮"的）。
    /// 那句"为什么"经 `accessibilityHint` 挂在**这一项自己**身上。
    ///
    /// ⚠️ **未目视**（同第 56 条那条）：`Menu` 的 label、灰项与**危险色**的实际观感
    /// 都由系统接管，只有跑一次模拟器才知道 —— 尤其"危险色出现在系统菜单里"
    /// 在本项目是第一次（此前危险色只出现在自绘的 `ActionButton` / `SheetRow` 上）。
    private var operationsMenu: some View {
        Menu {
            if !readOnly, model.hasContent {
                Button {
                    // §4.6 编辑模式：路由只带仓库全名与路径 ——
                    // "哪条分支"由编辑器页自己按 §9.4.1 解析（同本页，同一份判据）。
                    // ⚠️ `directory: nil` —— 那一格只服务**新建模式**的预填落点（§5.8）。
                    env.router.push(.editor(
                        fullName: fullName, path: model.path.raw, mode: .edit, directory: nil
                    ))
                } label: {
                    Label(FileCopy.editAction, systemImage: GitHubIcon.edit)
                }
                // 图片 / >1MB 的文本：这一档编辑不了，两句话都收在 `EditorCopy.editHint`。
                .disabled(model.editHint != nil)
                .accessibilityHint(model.editHint ?? "")

                Button {
                    model.sheet = .rename
                } label: {
                    Label(FileCopy.renameAction, systemImage: GitHubIcon.pencil)
                }
            }

            // ⚠️ 这两项**不吃** `hasContent`：路径在路由上就有，骨架屏上也复制得走
            //    —— 而它们正是"看不了的文件"上唯一还能用的两件（第 56 条新增的那两项）。
            Button {
                model.copyPath()
            } label: {
                Label(FileCopy.copyPathAction, systemImage: GitHubIcon.copy)
            }

            Button {
                model.copyFileName()
            } label: {
                Label(FileCopy.copyFileNameAction, systemImage: GitHubIcon.file)
            }

            // 图片与不支持预览的文件没有"原文"可复制 ⇒ 这一项**不出现**（§4.5）。
            if model.canCopyRaw {
                Button {
                    model.copyRaw()
                } label: {
                    Label(FileCopy.rawAction, systemImage: GitHubIcon.raw)
                }
            }

            if !readOnly, model.hasContent {
                // 危险色 + 排在最后：它是这一屏唯一**不可逆**的动作。
                Button(role: .destructive) {
                    model.sheet = .delete
                } label: {
                    Label(FileCopy.deleteAction, systemImage: GitHubIcon.trash)
                }
            }
        } label: {
            Image(systemName: GitHubIcon.ellipsis)
        }
        .accessibilityLabel(FileCopy.operationsMenuAccessibilityLabel)
    }

    // MARK: - 三档结局

    @ViewBuilder
    private func outcomeBody(_ outcome: FileViewOutcome) -> some View {
        switch outcome {
        case let .content(file):
            fileBody(file)

        case let .unsupported(reason):
            // ⚠️ `reason` 决定那一句说明 —— 图片太大与二进制对用户的下一步不一样
            //    （前者"等网络好点或者去网页端"，后者"这里根本打不开它"）。
            noticeState(hint: reason == .imageTooLarge
                        ? FileCopy.unsupportedImageHint
                        : FileCopy.unsupportedBinaryHint)

        case .undecodable:
            // ⚠️ 与 `.unsupported` **必须**给不同的那一句：上面那句明说"App 不下载它的
            //    内容"，而这一档我们**刚刚下载了它**。照那句说就是假话。
            noticeState(hint: FileCopy.undecodableTextHint)
        }
    }

    // MARK: - 可以看的那一档

    /// 正文 + 页脚说明。
    ///
    /// ⚠️ **2026-10-13 起这里没有操作行了**（第 62 条）：那四颗按钮搬到了右上角那颗「⋯」里
    /// ⇒ 正文下面直接就是页脚。原型那两处外边距（`margin-top:14px` 的操作行、
    /// `margin-top:10px` 的页脚）因此少了一处，**保留页脚那 10**（它量的是"正文到页脚"，
    /// 与操作行在不在无关）。
    @ViewBuilder
    private func fileBody(_ file: FileContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            contentSurface(file)

            // 原型 `margin-top:10px`（10 不在 4pt 阶里 ⇒ 写原值并注明出处）。
            footer.padding(.top, 10)
        }
    }

    /// 正文：代码块、markdown 文档或图片。
    @ViewBuilder
    private func contentSurface(_ file: FileContent) -> some View {
        switch file.body {
        case let .text(text):
            // ⚠️ 只有 `.md` / `.markdown` 会拿到一份解析好的文档（判据在领域层
            //    `MarkdownFile`）—— 其余文本仍是代码块。两条都是既有件，
            //    本岔路口只决定画哪一个（走查第 57 条）。
            if let document = file.markdown {
                markdownSurface(document, at: file.path)
            } else {
                CodeSurface(lines: CodeHighlighting.lines(
                    // ⚠️ `FileContent.lines(of:)` 而不是 `split(separator:)`：
                    //    后者会吃掉空行 ⇒ **行号全错位**（领域层有单测钉住这条）。
                    FileContent.lines(of: text),
                    // 语言按**当前路径的扩展名**认。原型这一屏是硬编码的 Swift 演示数据，
                    // 认不出的语言由 `CodeSurface` 走纯文本降级（不去猜，见 `CodeLanguage.named`）。
                    // ⚠️ 取 `file.path`（这一份内容自己的路径）而不是 `model.path`：
                    //    重命名之后两者会短暂不同 —— 内容还没重取，而路径已经换新了。
                    language: CodeLanguage.named(FilePreviewKind.extensionOf(file.path.displayName))
                ))
                // 只读浏览里"把这一段复制走"是正常需求，而原型的 `<pre>` 本来就是可选的
                // （浏览器默认行为）⇒ 取原型。`DiffCard` 里 PRD §4.7 有明写，这一页没有。
                .textSelection(.enabled)
            }

        case let .image(data):
            if let image = UIImage(data: data) {
                imageSurface(image)
            } else {
                // 扩展名说它是图片，而字节不是 ⇒ 落到"下载了但解不出来"那一块。
                // ⚠️ 见类型说明里的第 2 条「规格未给」。
                noticeState(hint: FileCopy.undecodableTextHint)
            }
        }
    }

    /// md 正文：与 README / Release 说明**同一套**渲染（`MarkdownBody` 的 `.document` 档
    /// —— 无面板、无内边距、15pt 正文），所以同一份 README 在仓库首页
    /// 与在文件页点开之后长得一样。
    ///
    /// ⚠️ 左右那 16pt 由**本页**给（`body` 里那圈 `Spacing.page`）—— 正文档的内边距
    ///    在 2026-10-15 走查第 75 条归零了，这里不给的话正文会顶到屏幕边。
    ///
    /// ⚠️ **走到这里的路径必然是 `.md` / `.markdown`**（`file.markdown` 非空），
    /// 判据在领域层 `MarkdownFile`，本视图不再判一次。
    ///
    /// ⚠️ 链接要**在这里接一次线**（与 `RepoReadmeSection` 的 README 正文同一套）：
    /// md 里大量链接是仓库内的相对地址（`[中文](README_zh.md)`），而系统打不开
    /// 一个没有 scheme 的地址 ⇒ 表现为"点了没反应"。判据（哪一档去哪儿）
    /// 全在领域层的 `RepoLinkResolver`，这里只做分派。
    ///
    /// ⚠️ 基准目录是**这个文件所在的目录**（不是文件自己的路径）——
    /// 相对链接以它为基准。取 `at:` 传进来的 `file.path`（这一份内容自己的路径），
    /// 与上面认语言那一处同源（重命名后两者短暂不同）。
    private func markdownSurface(_ document: MarkdownDocument, at path: RepoPath) -> some View {
        MarkdownBody(
            blocks: document.blocks,
            // ⚠️ **图片要在这里接一次线**（2026-10-12，走查第 58 条）：md 里的图
            //    大多是**仓库内的相对地址**（`../images/x.png`），不发请求画不出来，
            //    而"去哪个仓库、哪个分支取"只有这一层知道。基准目录与链接那处同源
            //    （文件所在目录）。
            //    ⚠️ `ref` 取 `model.branch`（这一页自己解析出来的那个），不是路由上的 ——
            //    §8.2 的路由不带分支，与 `FileViewModel` 那条说明同源。
            imageContext: MarkdownImageContext(
                fullName: fullName,
                ref: model.branch,
                baseDirectory: path.deletingLastComponent(),
                store: env.markdownImages
            )
        ) { url in
            switch RepoLinkResolver.target(
                for: url,
                fullName: fullName,
                baseDirectory: path.deletingLastComponent()
            ) {
            case let .file(linked):
                // ⚠️ `readOnly` 沿用本页的 —— 同一条仓库浏览链上权限不变
                //    （他人仓库里点开的 md 里再点一个文件，仍是只读浏览）。
                env.router.push(.fileView(
                    fullName: fullName, path: linked.raw, readOnly: readOnly
                ))
                return .handled

            case let .directory(linked):
                // ⚠️ **两档都进同一个代码页**（2026-10-14 起）—— 可写性由 `readOnly` 表达，
                //    它带着**起始层**（`linked`）：用户点的是"某个目录"，期望的是打开它，
                //    而不是回到仓库根再自己找一遍。
                //
                // ⚠️ 这里是全仓**唯一**会带 `path` 进代码页的地方（其余入口都是根目录）——
                //    这也是 `Route.repoCode` 为什么还留着一个 `path` 参数的全部理由。
                env.router.push(.repoCode(
                    fullName: fullName,
                    readOnly: readOnly,
                    path: linked.isRoot ? nil : linked.raw
                ))
                return .handled

            case .external:
                // 外部地址必须落到系统，否则 md 里所有外链会一起静默失效。
                return .systemAction

            case .anchor, .unresolved:
                // 两档都**没有落点**（页内锚点这一版不做；相对地址跳出仓库根时猜不出
                // 它想去哪儿）。`.discarded` 是"我们要过它、并决定不跳"，比 `.handled` 诚实。
                return .discarded
            }
        }
        // 与代码块那一档相同：只读浏览里"把这一段复制走"是正常需求。
        .textSelection(.enabled)
    }

    /// 图片：**原始比例、限宽、不放大**。
    ///
    /// ⚠️ 有意不写 `scaledToFit()` 之外的任何缩放：一张 16×16 的 favicon 被拉满
    /// 屏幕宽会变成一个巨大的马赛克，而用户点进来是想看"这个文件长什么样"。
    private func imageSurface(_ image: UIImage) -> some View {
        Image(uiImage: image)
            // ⚠️ `.resizable()` + `scaledToFit()`：不 `resizable` 的话超出屏幕的图
            //    会被裁掉（而没有任何滚动条提示右边还有内容）。
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.Palette.codeSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .stroke(Theme.Palette.borderSoft, lineWidth: 1)
            )
    }

    // MARK: - 页脚

    /// 页脚说明（原型 `.t3` 居中）。
    ///
    /// ⚠️ 它是这一屏**唯一**留下的一行正文外的东西（操作行 2026-10-13 搬进了右上角菜单，
    /// 第 62 条）。留在原地的理由：它说的是"保存之后会发生什么"（一次 commit /
    /// 提交面板能选什么），而那件事发生在**编辑器**里 —— 与操作入口摆在哪儿无关。
    private var footer: some View {
        Text(readOnly ? FileCopy.readOnlyFooter : FileCopy.ownFooter)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: - 看不了的两档

    /// 「看不了」的**共用版式**：一个图标 + 标题 + 那一句说明 + 网页端出口。
    ///
    /// ⚠️ 版式共用是**有意**的（两档的视觉行为一致），而那句话由调用方从**两个不同的
    /// 常量**传进来 —— 共用版式不等于共用文案（`FileViewOutcome` 的类型说明）。
    ///
    /// ⚠️ 这一块**不给操作行**：见类型说明里的第 1 条「规格未给」。
    private func noticeState(hint: String) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: GitHubIcon.unsupportedFile)
                .font(.system(size: 30))
                .foregroundStyle(Theme.Palette.textTertiary)
                // 装饰性图标，标签由下面两行文字给。
                .accessibilityHidden(true)

            Text(FileCopy.unsupportedTitle)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)

            Text(hint)
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Palette.textTertiary)
                .multilineTextAlignment(.center)

            ActionButton(title: FileCopy.openInBrowserAction, style: .ghost) {
                openInBrowser()
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .padding(.horizontal, Theme.Spacing.m)
    }

    // MARK: - 骨架 / 失败

    /// ## ⚠️ 2026-10-16 起不再手抄几何（NATIVE-MIGRATION P1）
    ///
    /// 画的是真实的 `fileBody(_:)` + 占位内容 + `.redacted` —— 上面那句"与
    /// `CodeSurface` 的 11 / 13 同值、否则到位时会跳"从此自动成立（同一份布局）。
    ///
    /// ⚠️ 占位是**代码块**那一档（`FileContent.placeholder` 的 `markdown: nil`）：
    /// 真实内容若是 `.md`，到位时形状会换 —— 占位只能选一档，多数文件是代码。
    private var skeleton: some View {
        fileBody(.placeholder)
            .redacted(reason: .placeholder)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// 首屏失败 —— 必须留一个出口（PRD §1 设计原则 4）。
    private func failureState(_ error: GitHubError) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(Theme.Palette.textTertiary)

            Text("加载失败")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.textSecondary)

            Button("重试") {
                Task { await model.refresh() }
            }
            .font(Theme.Font.bodyStrong)

            // ⚠️ 取不到内容时网页端是这一页**唯一总是可用**的出路 ——
            //    不留它，用户在一个 404 上就只剩"重试"可点（而同一次失败还会再来一遍）。
            Button(FileCopy.openInBrowserAction) {
                openInBrowser()
            }
            .font(Theme.Font.footnote)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .accessibilityElement(children: .combine)
        // 失败原因**只说确定的那一件事**：404 与无权限被 GitHub 混同（§4.3），
        // 不得替用户断定是"文件不存在"还是"你没权限"。
        .accessibilityHint(Self.failureHint(error))
    }

    // MARK: - 网页端出口

    /// 打开这一页对应的 GitHub 网页端地址。
    ///
    /// ⚠️ 地址由 `FileViewModel.webURL` 拼（拿不到分支时用字面 `HEAD`
    /// —— GitHub 的 `blob` 路由需要一段引用名，省掉它会 404）。
    private func openInBrowser() {
        guard let url = model.webURL else { return }
        openURL(url)
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

#Preview {
    @Previewable @State var environment = AppEnvironment()
    NavigationStack {
        FileView(
            fullName: "my-git/gitduo",
            path: RepoPath(path: "GitDuo/App/AppTabs.swift"),
            readOnly: false,
            loader: environment.fileContent,
            detail: environment.repoDetail,
            memory: environment.branchMemory,
            renameFile: environment.renameFile,
            deleteFile: environment.deleteFile,
            toast: environment.toast
        )
    }
    .environment(environment)
}
