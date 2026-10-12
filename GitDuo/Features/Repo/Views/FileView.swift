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
/// | `.content(.text)` | `CodeSurface` 代码块（按扩展名着色，认不出语言 ⇒ 纯文本） |
/// | `.content(.image)` | 图片（原始比例、限宽） |
/// | `.unsupported(reason)` | 「无法预览」+ **跳网页端出口**（**没下载**） |
/// | `.undecodable` | 「编码不认识」+ 跳网页端出口（**下载了**） |
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
/// ## ⚠️ 操作行的四个按钮从切片 8.4 起**各自不同**
///
/// | 按钮 | 8.4 之后 |
/// |---|---|
/// | `编辑` | **真做** —— 推入编辑器（§4.6 编辑模式）；**超过 1MB 的文本**与**图片**上不可点 |
/// | `历史` | 仍不可点（它指向"这个文件的提交历史"这一独立页面，PRD §4.5 标 ⏳） |
/// | `Raw` | 真做（决策 #51 的两处例外之一：复制原文，**零请求**） |
/// | `更多` | **真做** —— 打开 §5.15 文件操作菜单（重命名 / 删除） |
/// | `⑂ Fork 后可编辑` | 仍不可点（他人仓库那一档，Fork 本身没做） |
///
/// ⚠️ 「不可点」一律是 `allowsHitTesting(false)` + 读屏 hint，**不是** `.disabled`
/// —— 后者会变灰、看起来像"暂时不可用"，而那三个是"这一版就不做"。
/// 8.4 之后仍然不可点的只剩 `历史` / `Fork` 两颗。
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
/// 1. **操作行与页脚只在"看得了"时出现**。PRD §4.5 的权限差异表是按"能看的文件"
///    写的，没有覆盖"看不了"的两档；而 `编辑` 一个 App 根本显示不出来的文件是没有
///    意义的。所以那两档只给网页端出口 —— 那正是 PRD §4.5 为它们规定的动作。
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
        .refreshable { await model.refresh() }
        .task { await model.start() }
        // 三张弹层由一个枚举驱动（同 `BranchesView`）—— 文件操作菜单里的两个动作
        // 各自要**换成**另一张弹层，用布尔量表达就是"关一张、开一张"，而它中间的一帧是空屏。
        .sheet(item: $model.sheet, onDismiss: handleSheetDismissal) { route in
            presented(route)
                // ⚠️ 原型所有弹层都是**内容高度**（`.sheet{bottom:10px}` 自适应），
                //    而本仓从切片 1 起统一用 `.medium`（`ClearRecentSheet` 那张
                //    "标题 + 说明 + 两个整宽按钮"的卡片就是先例）。
                //    这一片三张都小，`.medium` 会留下半屏空白 —— 属既有偏差的延续，
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
        case .operations:
            FileOperationsSheet(
                fileName: model.path.displayName,
                // 两个动作各自把 `sheet` 换成另一张 —— **不经过 nil**
                // （见 `FileOperationsSheet` 的说明：关一次再开一次会在中间空一帧）。
                onRename: { model.sheet = .rename },
                onDelete: { model.sheet = .delete }
            )

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
    /// | 右侧 | 「⋯」菜单（复制路径 / 添加文件） | 「⋯」菜单（复制路径 / 复制文件名） |
    ///
    /// 合成一个控件就必须再加三个开关，而每个开关两档里总有一档是错的 ——
    /// 与 `SectionTabs` 不复用 `SegmentedBar` 是同一条理由。
    ///
    /// ## ⚠️ 右端那颗「⋯」是 **2026-10-12 加的**（按用户要求，第 56 条）
    ///
    /// 原型这一行**没有任何动作位**（`文件名 · 分支` 两个 `Text` 就完了）。
    /// 加它的理由与仓库页面包屑上那一颗相同：让"当前在哪"这件事可以直接复制走。
    /// 两处形状同一套（见下面 `crumbMenu`），**两处都用系统原生 `Menu`**。
    ///
    /// ⚠️ 它**当天就改过一次形状**：先落地的是一颗裸复制图标（只复制路径），
    /// 用户随即要求「换成三个点，菜单两项：复制路径 / 复制文件名」⇒ 现在与仓库页
    /// 那颗逐字同形。**没有留下"一颗图标按钮"的旧形态**。
    ///
    /// ⚠️ 它与同页的 `Raw`（复制**内容**）**不是一回事** —— 见 `FileCopy.copyPathAction`。
    ///
    /// ⚠️ 分支名 `lineLimit(1)`：分支名可以很长（`feature/客户XX-报价单改版`），
    /// 而文件名通常更长、更需要完整显示。
    private func crumb(branch: String) -> some View {
        // ⚠️ 与导航标题同源（`model.path`）—— 重命名之后两处一起跟着变。
        let display = model.path.displayName

        return HStack(spacing: 0) {
            // ⚠️ 这三段**单独包一层**、读屏合成都做在**这一层**上：
            //    2026-10-12 加的动作位就在外层，若把 `.accessibilityElement(children: .ignore)`
            //    留在最外面，那颗「⋯」会被一起合成掉 —— 读屏用户根本点不到它。
            HStack(spacing: 0) {
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

            Spacer(minLength: Theme.Spacing.s)

            crumbMenu
        }
        // 8 / 12：原型原值（`padding:8px 12px`）。
        .padding(.vertical, Theme.Spacing.s)
        .padding(.horizontal, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .fill(Theme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .stroke(Theme.Palette.borderSoft, lineWidth: 1)
        )
    }

    /// crumb 行右端那颗「⋯」（2026-10-12 新增，按用户要求 —— 第 56 条）。
    ///
    /// 菜单两项：`复制路径`（整条相对路径）/ `复制文件名`（只有最后一段）。
    ///
    /// ⚠️ 形状与仓库页面包屑那颗「⋯」**同一套**（13pt 图标 + `.padding(8)`、
    /// `Radius.control`、`surfaceSunken` 底、`Menu` 的 label 直挂图标）：
    /// 同一个动作在两个页面上要长得一样。**两处的差别只该是菜单项。**
    ///
    /// ⚠️ 与仓库页**有意不同的一处**：那边菜单里有「添加文件」（会弹一张 sheet），
    /// 这边两项**都不离开本页**（纯本地复制 + 一条 toast）—— 所以这里不需要任何
    /// `sheet` 状态。
    ///
    /// ⚠️ 它与 `noticeState` / `failureState` 那两档**无关** —— 那两档根本不画 crumb
    /// （`content` 只在 `.content` 那一条里建它），所以"看不了的文件"上不会出现这颗菜单，
    /// 也就没有"复制一个打不开的文件的路径"这种别扭事。
    ///
    /// ⚠️ **未目视**：`Menu` 的 label 由系统接管，它会不会给这颗图标套 tint
    /// 或自带按钮样式，只有跑一次模拟器才知道（与仓库页那一颗同一条风险）。
    private var crumbMenu: some View {
        Menu {
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
        } label: {
            Image(systemName: GitHubIcon.ellipsis)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(Theme.Spacing.s)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.Palette.surfaceSunken)
                )
                .contentShape(Rectangle())
        }
        .accessibilityLabel(FileCopy.crumbMenuAccessibilityLabel)
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

    @ViewBuilder
    private func fileBody(_ file: FileContent) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            contentSurface(file)

            // 原型 `margin-top:14px`（14 不在 4pt 阶里 ⇒ 写原值并注明出处）。
            actionRow.padding(.top, 14)

            // 原型 `margin-top:10px`（同上）。
            footer.padding(.top, 10)
        }
    }

    /// 正文：代码块或图片。
    @ViewBuilder
    private func contentSurface(_ file: FileContent) -> some View {
        switch file.body {
        case let .text(text):
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

    // MARK: - 操作行（原型 `justify-content:center;gap:10px`）

    private var actionRow: some View {
        HStack(spacing: 10) {
            if readOnly {
                // 原型的这两个按钮横向内边距是 22（`padding:9px 22px`，覆写了 `.btn` 的 16）。
                stubAction(FileCopy.forkToEditAction,
                           hint: FileCopy.forkToEditUnavailableHint,
                           horizontalPadding: 22)
            } else if let hint = model.editHint {
                // ⚠️ 「编辑」**画出来但不可点**的那两档（超过 1MB 的文本 / 图片）。
                //    形态与真按钮逐字相同（同一个 `ActionButton` + `.primary` + 22），
                //    差别只在按不动 —— 这正是决策 #51 要的效果："不冒充成品"。
                stubAction(FileCopy.editAction,
                           style: .primary,
                           hint: hint,
                           horizontalPadding: 22)
            } else {
                ActionButton(
                    title: FileCopy.editAction,
                    style: .primary,
                    horizontalPadding: 22,
                    fillsWidth: false
                ) {
                    // §4.6 编辑模式：路由只带仓库全名与路径 ——
                    // "哪条分支"由编辑器页自己按 §9.4.1 解析（同本页，同一份判据）。
                    // ⚠️ `directory: nil` —— 那一格只服务**新建模式**的预填落点（§5.8），
                    //    编辑模式的路径就是 `path` 这一格，两者不互相顶替。
                    env.router.push(.editor(
                        fullName: fullName, path: model.path.raw, mode: .edit, directory: nil
                    ))
                }
            }

            stubAction(FileCopy.historyAction, hint: FileCopy.historyUnavailableHint)

            // ⚠️ `Raw` **当真做**（决策 #51 的两处例外之一）。
            //    图片与不支持预览的文件没有"原文可复制" ⇒ 那个按钮**不出现**（§4.5）。
            if model.canCopyRaw {
                ActionButton(
                    title: FileCopy.rawAction,
                    style: .ghost,
                    fillsWidth: false
                ) {
                    model.copyRaw()
                }
            }

            if !readOnly {
                // §5.15 文件操作菜单（重命名 / 删除）。⚠️ 它**只把弹层换出来**，
                //    两个动作各自的确认层是另外两张（§5.16 / §5.17）。
                ActionButton(
                    title: FileCopy.moreAction,
                    style: .ghost,
                    fillsWidth: false
                ) {
                    model.sheet = .operations
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 「画出来但这一版不做」的按钮（决策 #51）。
    ///
    /// ⚠️ 逐字与真按钮一致（同一个 `ActionButton`），差别只在**按不动** ——
    /// 这正是决策 #51 要的效果："形态与原型一致，但不冒充成品"。
    ///
    /// ⚠️ 闭包必须是**真的什么都不做**：`allowsHitTesting(false)` 挡的是触摸，
    /// 而读屏的激活动作绕过命中测试 ⇒ 给一个会弹 toast 的闭包，
    /// 读屏用户就真的点得动这个"不可点"的按钮（`UserProfileSheet` 的同一处置）。
    private func stubAction(
        _ title: String,
        style: ActionButton.Style = .ghost,
        hint: String,
        horizontalPadding: CGFloat = 16
    ) -> some View {
        ActionButton(
            title: title,
            style: style,
            horizontalPadding: horizontalPadding,
            fillsWidth: false,
            action: {}
        )
        .allowsHitTesting(false)
        // 一颗按不动的按钮在读屏里就是个"按钮"，去掉那个 trait 才知道它其实是文字。
        .accessibilityRemoveTraits(.isButton)
        // hint 说清"为什么点不了"，而不是只说"不可用"。
        .accessibilityHint(hint)
    }

    /// 页脚说明（原型 `.t3` 居中）。
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

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SkeletonBar(height: 32)

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(0..<8, id: \.self) { _ in
                    SkeletonBar(height: 13, width: 210)
                }
            }
            // 与 `CodeSurface` 的 11 / 13 同值：骨架的形状要与它替换的东西对得上，
            // 否则内容到位那一刻整块会跳一下。
            .padding(.vertical, 11)
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.Palette.codeSurface)
            )
        }
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
