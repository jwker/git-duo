import SwiftUI
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// **代码页**（原 §4.4 的「代码」分区，2026-10-14 独立成页 —— 走查第 63 条）。
///
/// ## 它为什么被搬出来
///
/// 用户在走查里报了两件事：① 文件浏览**占用太多空间**；② 点进下级目录
/// **整页重新加载**（还带着头部大卡与分段条一起转圈）。两者的根因是同一个
/// —— "代码"与仓库简介、Issues、PR、Commits 挤在同一页，而目录层级又写进了路由
///（`Route.repoDetail(fullName:section:path:)` 的 `path`）⇒ 每进一层就是**一个新页面**，
/// 那一页要从头部开始把四条数据重取一遍。
///
/// 现在：
/// - 目录层级是**这一页内部**的导航（下面那个 `levels` 数组），**不进路由**；
/// - 这一页**不画**头部大卡与分段条 ⇒ 首屏多出四五行的位置。
///
/// ## ⚠️ 一页服务两种仓库（与 `RepoTreeSection` 同一条）
///
/// `readOnly` 是"这是不是我自己的仓库"（铁律 #7：只读态显式传参）：
/// §4.4 首页那四行入口的第一行传 `false`，§4.13 探索页的文件浏览入口传 `true`。
/// 差别只在两处：右上角那颗「⋯」在只读那一档**少一项**（菜单里只剩「复制路径」）、
/// 分支弹层不给「管理分支…」（在他人仓库上给一个管理入口，点进去每一行都必然失败，
/// 而失败原因从那一屏看不出来）。
///
/// ## ⚠️ 层级怎么翻（这是本页的要点）
///
/// | 动作 | 结果 |
/// |---|---|
/// | 点一行目录 | **页内推进一层**（只换这一页里的内容，页面不换 —— PRD §4.4.1）|
/// | 导航栏那颗「返回」 | 栈里还有上一层 ⇒ **回上一层**；已在仓库根层 ⇒ 退出这一页 |
/// | 点面包屑某一层 | 把层级**截断**到那一层（不推新页面）|
/// | 点一行文件 | 推入文件页（那是**外层**路由）——返回时这一页连同整个层级原样还在 |
///
/// ⚠️ 两条"回上层"的路里**没有左滑手势** —— 见下面"代价"第 2 条。
///
/// ## ⚠️⚠️ 层级**不是**一条嵌套的 `NavigationStack`（2026-10-14 崩溃修复）
///
/// 第一版把层级做成了这一页里的 `NavigationStack(path: $levels)`。
/// 它**能编译、能跑起来，但一进这一页就崩**：
///
/// ```
/// Thread 1: Fatal error: 'try!' expression unexpectedly raised an error:
///           SwiftUI.AnyNavigationPath.Error.comparisonTypeMismatch
/// ```
///
/// **根因：SwiftUI 不支持把 `NavigationStack` 嵌在另一条 `NavigationStack` 的推入页里。**
/// 那两条栈会被 SwiftUI 当成同一条来处置 ⇒ 它拿"外层路径的元素"（`Route`）与
/// "内层路径的元素"（`RepoCodeLevel`）逐元素比对，类型不同就 `try!` 失败 ——
/// `comparisonTypeMismatch` 的字面意思就是"比较时类型不匹配"。
/// 当时那句藏内层导航栏的 `.toolbar(.hidden, for: .navigationBar)` 就是为了压掉嵌套栈
/// 叠出来的第二条导航栏，**那句本身就是这件事的信号**（现在它连同整个内层栈一起删了 ——
/// ⚠️ 删它不只是清理：留着它会去藏**外层**那条导航栏，本页连标题与返回键都会没有）。
///
/// 现在换成**页面自己的一个数组**：`levels: [RepoCodeLevel]`，**只有栈顶那一层被渲染**，
/// 每一层带着**它自己的会话**（`RepoTreeSession`，见 `RepoCodeLevel` 的说明）。
///
/// 于是"返回上一层，那一层的内容立刻就在"**仍然成立** —— 靠的**不是**
/// "视图还在栈里"（视图其实已经销毁了），而是"**数据还在**"：会话是引用类型，
/// 它躺在 `levels` 里，视图重建时那一层的目录页已经落地
/// （`RepoCodeViewModel.load` 的第一条守卫会跳过重取）。
///
/// ## ⚠️⚠️ 换层那一下有**两件事**必须做（2026-10-14，修完嵌套栈之后同日）
///
/// 用户报回：**点二级目录一直停在骨架屏**，而别的页面都正常（所以不是网络问题）。
///
/// 根因是上面那次崩溃修复留下的一条：这一页从此**只渲染栈顶那一层** ⇒ 换层只是
/// `level` 换了个人，而**视图身份**与 `.task` 的 `id` 都没变 ⇒ `.task` **不重跑**
/// ⇒ 新那一层的会话**从没被 `load` 过**（`page` 停在 `idle`）⇒ 画出来就是一块永久的骨架。
/// ⚠️ 在此之前，"每进一层会取数"**从来不是这一页保证的** —— 那时每一层是各自一个
/// `navigationDestination` 视图、各有自己的 `.task`（那是**栈**给的行为）。
///
/// 两件事各管一样，判据故意分在两处（症状差得很远，见 `tree(_:)` 里那两条注释）：
///
/// | 必做的事 | 漏了它的症状 |
/// |---|---|
/// | `.task(id:)` 的 id 带上**这一层的路径**（`RepoCodeLoadKey.path`）| **永远停在骨架屏**（取数根本没发生）|
/// | 内容换**身份**（`.id(level.path.raw)`）| 进子目录时**它是滚下去的**（继承了上一层的偏移）|
///
/// ⚠️ 这两行**都实跑验过**（2026-10-14，最小复现 + 退回验证：把 id 退回只带分支 ⇒
/// 换层那几次 `.task` 一次都不跑；把 `.id` 去掉 ⇒ 底层 `NSScrollView` 的偏移原样留着）。
/// 数在 `REVIEW-CHECKLIST` 第 63 条那条补记里。
///
/// ## ⚠️ 代价（如实记着，别当成设计本意）
///
/// 1. **没有系统的推进动画** —— 层级切换是即时替换。原型 `codeGo` 也只是重绘、
///    不带过渡，两边观感一致；要动画得自己写 `transition`，与推入方向（进层 / 返层 /
///    面包屑跳层三种）的对应关系会变成一堆要维护的状态，这一版不做。
/// 2. **没有系统的左滑返回** —— 那套手势属于**外层**那条栈，语义是"退出这一页"。
///    它现在被藏掉返回键之后**是什么状态只有真机上跑一次才知道**（见下）。
///    要让左滑变成"回上一层"就得自己写手势，而那与 PRD §1 的
///    "不做反直觉的手势导航"相悖 ⇒ 不做。
/// 3. 系统返回键上那半截**上一页的标题**也没有了（自己画的这一颗只有箭头）——
///    "上一层是谁"由面包屑回答，那是这一页更该看的地方。
///
/// ## ⚠️ 未目视（要真机 / 模拟器核对）
///
/// 1. 把系统返回键藏掉（`.navigationBarBackButtonHidden(true)`）之后，
///    **左滑手势是被禁用了、还是仍然会退出这一页** —— 两种都能接受（前者少一条路、
///    后者与"点返回键"的后果不同），但必须知道是哪一种，才好把 PRD §4.4.1 那一行写准。
/// 2. 自己画的那颗「返回」在导航栏里的位置与字形大小（全仓第一次用 `.topBarLeading`）。
/// 3. **进一层目录 / 返回上一层各走一次** —— 确认新那一层真的会取数、内容是**立刻就在**的、
///    并且**进来时是从顶部开始**的（不是接着上一层的滚动位置）。
///    ⚠️ 这条缺陷的**机制**已用最小复现实跑验过（见类型说明那张表下面的补记），
///    但**这一页的接线**只有真机能走 —— `make test` 不编译 App target，
///    "取数有没有被触发"在源码里也看不出来（那正是它报回来之前的样子）。
/// 4. **右上角那颗「⋯」在导航栏里的观感**（2026-10-14 挪进来）—— 它现在与左上角那颗
///    自己画的「返回」同在一行，两边的字形大小 / 垂直位置要看着像一对；
///    也顺便与 §4.5 文件页那颗并排比一眼（那正是这次改动的目的）。
///    ⚠️ 只读那一档菜单里**只有一项**（`复制路径`）—— 一项目菜单的样子也要看一眼。
struct RepoCodeView: View {

    let fullName: String

    /// 他人仓库那一档（§4.13 进来时是 `true`）。
    let readOnly: Bool

    /// **从哪一层开始看**（`.root` = 仓库根）。
    ///
    /// ⚠️ 这不是"当前层"：进去之后用户怎么走**与它无关**（页内那个层级说了算），
    /// 它只决定进页那一刻栈底铺到哪。要它的唯一理由是**入口可能不是根** ——
    /// 仓库首页的 README（§4.4 / §4.13）里一个指向 `docs/` 的链接点下去，
    /// 用户期望的是打开那个目录（那处接线在 `RepoReadmeSection` 里）。
    let startPath: RepoPath

    let detail: LoadRepoDetail
    let treeLoader: LoadRepoTree
    let branches: LoadBranches
    let memory: any BranchMemoryStore
    let saver: SaveFile

    /// §5.8 两个上传出口的取件与预处理（决策 #71 / #72）。
    ///
    /// ⚠️ 与本页的关系只是**过一手**：弹层是这一页呈现的，而依赖一律由 `RouteView`
    ///    从组合根带下来（页面不 new 用例 —— `AGENTS.md §3` 的铁律）。
    let intake: UploadIntake

    let toast: ToastCenter

    @Environment(AppEnvironment.self) private var env

    @State private var model: RepoCodeViewModel

    /// 页内层级栈（栈顶 = 当前目录）。第 0 层恒是仓库根。
    ///
    /// ⚠️ 它**只是这一页自己的一个数组**，不是一条 `NavigationStack`（理由见类型说明）——
    /// 而且**只有栈顶那一层会被渲染**：底下的层靠各自的会话留着内容，视图不留在树上。
    @State private var levels: [RepoCodeLevel]

    @State private var sheet: CodeSheet?

    /// 本页的弹层路由。
    ///
    /// ⚠️ 用 `Identifiable` 枚举驱动 `.sheet(item:)`，**不用 `isPresented` 布尔量**
    /// （同全仓其余页面）：三张弹层里有两对是"关一张、开下一张"的连续动作，
    /// 布尔量在那一帧里会出现两个同时为真 / 同时为假的状态。
    ///
    /// ⚠️ 每一项都**带着那一层的路径** —— 三个动作都作用在"某一层"上
    /// （复制它的路径、往它里面添加文件、切它的分支），而弹层呈现期间
    /// 用户可能已经返回上一层（甚至退出这一页）了 ⇒ 不能靠"当前层"再推一次。
    private enum CodeSheet: Identifiable {
        case branch(RepoPath)
        case addFile(RepoPath)
        case upload(UploadDraft, directory: RepoPath)

        var id: String {
            switch self {
            case let .branch(path): "branch-\(path.raw)"
            case let .addFile(path): "addFile-\(path.raw)"
            case let .upload(draft, directory): "upload-\(directory.raw)-\(draft.fileName)-\(draft.data.count)"
            }
        }
    }

    init(
        fullName: String,
        readOnly: Bool,
        startPath: RepoPath,
        detail: LoadRepoDetail,
        treeLoader: LoadRepoTree,
        branches: LoadBranches,
        memory: any BranchMemoryStore,
        saver: SaveFile,
        intake: UploadIntake,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.readOnly = readOnly
        self.startPath = startPath
        self.detail = detail
        self.treeLoader = treeLoader
        self.branches = branches
        self.memory = memory
        self.saver = saver
        self.intake = intake
        self.toast = toast

        let model = RepoCodeViewModel(
            fullName: fullName,
            readOnly: readOnly,
            detail: detail,
            treeLoader: treeLoader,
            branches: branches,
            memory: memory,
            saver: saver,
            toast: toast
        )
        _model = State(initialValue: model)
        // 层级**在这里就铺好**：从仓库根一路到起始层（起始层是根时只有一层）。
        //
        // ⚠️ 铺好的中间层**一开始并不取数** —— 只有**栈顶那一层**会被渲染
        //    （见类型说明），于是只有它那个 `.task` 会跑；从一条 `docs/a/b` 的链接
        //    进来不会当场发三个请求。中间层会在**真的被走到**那一刻才取
        //    （点面包屑往回跳、或一层层返回来时）。
        //
        // ⚠️ 也不能只铺起始层那一层：面包屑点第 k 段 = "回到第 k 层"，
        //    那个映射靠**下标**（`levels[k]`）—— 中间层缺一个就会跳错一层（见 `chain`）。
        _levels = State(initialValue: Self.chain(to: startPath).map {
            RepoCodeLevel(path: $0, session: model.makeSession(path: $0))
        })
    }

    /// 从仓库根到 `path` 的**每一层**（含两端）。
    ///
    /// ⚠️ 中间层不能省：面包屑点第 k 段 = "回到第 k 层"，而那个映射靠
    /// `levels` 的**下标**（`levels[k]`）。中间层缺一个，"点面包屑"就会跳错一层。
    private static func chain(to path: RepoPath) -> [RepoPath] {
        guard !path.isRoot else { return [.root] }

        var paths: [RepoPath] = [.root]
        var accumulated: [String] = []
        for component in path.components {
            accumulated.append(component)
            paths.append(RepoPath(path: accumulated.joined(separator: "/")))
        }
        return paths
    }

    var body: some View {
        // ⚠️ 渲染的是**栈顶那一层**（不是 `levels[0]`）—— 换层就是换它，
        //    于是"进一层"在这一页里只体现为一次重绘（见类型说明）。
        //
        // ⚠️ 2026-10-16 起：主干回到 `ScrollView`（本轮修复）。面包屑与文件行
        //    自带几何，坐在 `List` 行里会被系统行内边距再缩一次 ⇒ 宽度不对、间距过大。
        ScrollView {
            content(current)
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Palette.background)
        // ⚠️ 这两条是给**外层**那条导航栏的：本页是推入页，标题写仓库名
        //    （不写仓库全名 —— 顶部那行宽度有限，而全名在上一页刚看过）。
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        // ⚠️ 系统那颗返回键的语义是"退出这一页"（它属于**外层**栈），
        //    而这一页要的是"先回上一层目录" ⇒ 藏掉它、换成 `backButton`。
        //    ⚠️ 藏掉之后**左滑手势**还剩什么，只有真机才知道（见类型说明的"未目视"）。
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                backButton
            }
            // 右上角那颗「⋯」—— 与文件页（`FileView.operationsMenu`）
            // **同一个位置、同一套控件**（2026-10-14 用户要求，从面包屑右侧搬来）。
            // ⚠️ 它挂在 `body` 上（不在 `content(_:)` 里）⇒ 骨架 / 失败态也画得出来，
            //    里面的项各自把关（与文件页同一条处置）。
            ToolbarItem(placement: .topBarTrailing) {
                levelMenu(current.path)
            }
        }
        .refreshable {
            // 下拉 = 重取**这一层**（别的层没被看着，也没被要求刷新）。
            await current.session.reload()
        }
        // ⚠️ 这个 id 由 `RepoCodeLoadKey` 算（两半都必须在，见那个类型的说明）：
        //
        // ① **默认分支**：它是**异步**来的，而这一层的取数要等它（`load` 的第一条守卫就是
        //    `guard let defaultBranch`）。⚠️ **更正（2026-10-14 同日顺手核了一遍）**：
        //    取数那一支只在分支到手之后才会被渲染（分支还没来那一格骨架由
        //    `content(_:)` 画）⇒ 这一半**现在到不了 `nil`**、也就不会真的触发过一次重跑。
        //    留着它是因为它描述了取数的**依赖**（同 `RepoCodeLoadKey` 的说明）——
        //    哪天的改动让骨架由"会话自己"画（而不是整页那一格），少了它就会静默退化。
        //
        // ② **这一层的路径**：换层（点目录 / 点面包屑 / 返回上一层）在这里只体现为
        //    `level` 换了个人，而 `defaultBranch` **一个字都没变** ⇒ id 里不含路径的话
        //    `.task` **不会重跑** ⇒ 新那一层的会话从没被 `load` 过、`page` 停在 `idle`，
        //    屏幕上是一块**永不消失的骨架**。⚠️ 2026-10-14 用户报回的正是这一条
        //    （"点二级目录一直停在骨架屏、而别的页面都正常"）—— 它由"删掉嵌套栈"那次
        //    修复引入（见类型说明）。
        //
        // ③ id 里**不再需要"我在不在栈顶"**（随嵌套栈一起去掉）：现在**只有栈顶那一层
        //    被渲染**，走到这里的就是栈顶（见类型说明）。
        //
        // ⚠️ 而"返回上一层"**不会**因此重取：id 变了，`.task` 确实会再跑一次，
        //    但那一层的 `page` 已经落地，`model.load` 的第一条守卫会把它挡掉 ——
        //    "返回即所见"靠的是这个，不是"视图还留在栈里"（视图其实已经销毁了）。
        //
        // ⚠️ 第 ② 条在 2026-10-14 用最小复现**实跑验过**：id 只用分支时，换层那几次
        //    `.task` **一次都不跑**（屏幕就是永久骨架）；id 带上路径之后，每一次换层都跑
        //    （返回上一层那次也跑，由守卫挡掉重取）。
        .task(id: RepoCodeLoadKey(branch: model.defaultBranch, path: current.path)) {
            await model.load(current.session)
        }
        // ⚠️ 换层 = **换这一个 `ScrollView` 的身份**（2026-10-14 同批补）：滚动位置跟着归零。
        //    不做的话，上一层那个偏移会被继承下来 —— 子目录进来就是滚下去的，
        //    而"我在哪一层"（面包屑）恰恰在内容最上面。
        //    （同日实测：不换身份时底层 `NSScrollView` 的偏移**原样留着**、换身份后归零，
        //    数见 `REVIEW-CHECKLIST` 第 63 条那条补记。）
        //    ⚠️ **取数不靠这一行**（靠上面那个 `.task` 的 id），两处分着写是有意的：
        //    漏了下面这一行，症状是"进子目录时它是滚下去的"；漏了上面 id 里的路径，
        //    症状是"永远停在骨架屏"。两种症状差得很远，判据就该分在两处。
        .id(current.path.raw)
        .task { await model.start() }
        .sheet(item: $sheet) { route in
            presented(route)
        }
    }

    /// 当前层（栈顶）。
    ///
    /// ⚠️ 到不了"空"那一档：`init` 铺的链至少有一层（仓库根），而层级只会被
    /// 推入与截断（`pop(toCrumb:)` 那个 `guard` 保证了至少留 1 层）
    /// ⇒ 这里是一个**由构造保证**的前提，不是"少判了一次"。
    private var current: RepoCodeLevel {
        levels[levels.count - 1]
    }

    /// 导航栏左上角那颗自己画的「返回」。
    ///
    /// **一个按钮两种去向**（和原型 `backOrPop()` 同一套，见类型说明那张表）：
    /// - 栈里还有上一层 ⇒ 回上一层目录（这一页不退出）；
    /// - 已经在仓库根层 ⇒ `env.router.pop()`，退出这一页（同 `FileView` 删除办妥后那一步）。
    ///
    /// ⚠️ **读屏文案必须分两句**（`RepoCopy` 两常量）：只说"返回"，
    ///    读屏用户分不清退的是**一层目录**还是**整页**。
    private var backButton: some View {
        Button {
            if levels.count > 1 {
                levels.removeLast()
            } else {
                env.router.pop()
            }
        } label: {
            Image(systemName: GitHubIcon.back)
        }
        .accessibilityLabel(
            levels.count > 1
                ? RepoCopy.backOneLevelAccessibilityLabel
                : RepoCopy.leaveCodePageAccessibilityLabel
        )
    }

    private var name: String {
        (try? RepositoryMapper.splitFullName(fullName))?.name ?? fullName
    }

    // MARK: - 一层

    @ViewBuilder
    private func content(_ level: RepoCodeLevel) -> some View {
        // ⚠️ 三支里**没有** `.toolbar(.hidden, for: .navigationBar)` ——
        //    它当初是为了藏掉内层那条栈的导航栏（现在没有内层栈了），
        //    留下来的话藏的就是**外层**那条：这一页会连标题与返回键一起消失。
        if let failure = model.failure {
            // 头部拿不到 ⇒ 连目录都取不了（分支无从解析）—— 整页失败 + 一个出口。
            PageFailure(error: failure) { Task { await model.retry() } }

        } else if model.defaultBranch == nil {
            // 头部还在路上 —— 目录还没法取（它要 `defaultBranch`）。
            // ⚠️ `RepoTreeSkeleton` 自带面包屑那一段（占位分支名 / 路径段）。
            RepoTreeSkeleton()

        } else {
            tree(level)
        }
    }

    private func tree(_ level: RepoCodeLevel) -> some View {
        // ⚠️ `RepoTreeSection` 现在吐的是普通视图（面包屑 + `CardBox` 装文件行），
        //    容器是上面 `body` 里的 `ScrollView`。
        RepoTreeSection(
            session: level.session,
            onOpenDirectory: { target in openDirectory(target) },
            onOpenFile: { target in
                // ⚠️ 文件页是**外层**路由（它是另一个页面，不属于这一页的层级）
                //    —— 返回时这一页连同整个层级原样还在（层级不重取，理由见类型说明）。
                env.router.push(.fileView(
                    fullName: fullName, path: target.raw, readOnly: readOnly
                ))
            },
            onTapBranch: { sheet = .branch(level.path) },
            onSelectSegment: { index in pop(toCrumb: index) }
        )
    }

    /// 导航栏右上角那颗「⋯」。
    ///
    /// ## 与文件页那颗**逐字同形**（2026-10-14 用户要求"和文件详情页样式统一"）
    ///
    /// | | §4.4.1 代码页（本页） | §4.5 文件页 |
    /// |---|---|---|
    /// | 位置 | `ToolbarItem(.topBarTrailing)` | 同左 |
    /// | 控件 | 系统原生 `Menu` | 同左 |
    /// | label | 一颗裸的 `Image(ellipsis)` | 同左 |
    /// | 菜单项 | 复制路径 / 添加文件 | 编辑 / 重命名 / 复制路径 / 复制文件名 / 复制原文 / 删除文件 |
    ///
    /// ⚠️ 字面上的差别只剩**菜单项**：两页的"这一屏有哪些动作"本来就不同，
    /// 而**位置、控件、字形、要不要自己画底色**这几件事必须一模一样 ——
    /// 那才是"样式统一"（差别在内容，不在长相）。
    ///
    /// ## ⚠️ 它原先长在**面包屑右侧**（2026-10-14 搬走，不是重画）
    ///
    /// 原形是 `codeBodyHTML` 里 `margin-left:auto` 那颗「＋ 添加」。**内容区里的东西
    /// 系统不管** ⇒ 当初得自己画字号 / 前景色 / 内边距 / 圆角底（`surfaceSunken`）。
    /// 搬到导航栏之后这四样一起删掉、交给系统 —— 这也是它现在能与文件页那颗
    /// **逐字相同**的原因。
    ///
    /// ⚠️ **原型同一天也搬了**（不是"原型还留在旧形态"）：那颗「＋ 添加」换成导航栏
    /// 右上角的「⋯」（`SCR.repoCode.action` → `openCodeMenuSheet`，`05-repo.js:113`），
    /// 面包屑右端从那一刻起是空的。两边的差别只剩**展开形态** —— App 是系统原生
    /// 下拉菜单，原型一律落到底部 sheet（原型没有那种控件）。
    ///
    /// ⚠️ 菜单作用在**当前这一层**（`current.path`）：层级切换会重绘本页、
    /// 菜单跟着重算，所以里面那两项始终对应用户正看着的那一层
    /// （弹层里另存着 `path`，呈现期间用户返回上一层也不会错位 —— 见 `CodeSheet`）。
    ///
    /// ## ⚠️ 只读那一档**整颗菜单照给**，只是少一项（用户 2026-10-14 裁定）
    ///
    /// 此前是"整颗不给"（原话：一颗菜单只为一项存在没有意义）。改成照给的理由是
    /// **与文件页一致** —— 文件页在他人仓库上照样画那颗「⋯」，只是项变少：
    /// - `复制路径` **恒有**：在别人的仓库上同样有用（粘到 issue 里）；
    /// - `添加文件` 只在**自己的仓库**、且**目录已经到手**时给（他人仓库上做不了：
    ///   要写就得先 Fork；而骨架 / 失败态连分支都还不知道，给了也只会显示空分支）。
    private func levelMenu(_ path: RepoPath) -> some View {
        Menu {
            Button {
                model.copyPath(at: path)
            } label: {
                Label(RepoCopy.copyPathAction, systemImage: GitHubIcon.copy)
            }

            if !readOnly, model.defaultBranch != nil {
                Button {
                    sheet = .addFile(path)
                } label: {
                    Label(RepoCopy.addFileMenuAction, systemImage: GitHubIcon.file)
                }
            }
        } label: {
            // ⚠️ 就是这一颗裸图 —— 底色 / 圆角 / 尺寸全由系统给（同文件页）。
            Image(systemName: GitHubIcon.ellipsis)
        }
        .accessibilityLabel(RepoCopy.operationsMenuAccessibilityLabel)
    }

    // MARK: - 层级动作

    /// 点一行目录 ⇒ **往层级里推进一层**（换掉这一页显示的内容，不推新页面）。
    private func openDirectory(_ path: RepoPath) {
        // ⚠️ 会话在**这里**建（不在 `content` 里）：渲染期间建对象是明令禁止的。
        //    已经在这一层上时不再推（点同一行两次不该叠出两层一样的页面）。
        guard !levels.contains(where: { $0.path == path }) else { return }
        levels.append(RepoCodeLevel(path: path, session: model.makeSession(path: path)))
    }

    /// 点面包屑的某一层 ⇒ **把层级截断到那一层**（不推新页面）。
    ///
    /// - Parameter index: 面包屑上的下标，**第 0 段是仓库全名**。
    ///   `BreadcrumbBar` 的 `path` 就是 `[fullName] + session.path.components`，
    ///   而 `levels[k]` 正是第 k 段 ⇒ **两个下标是同一个数**。
    ///   点第 k 段 = 保留 `levels[0...k]`。
    ///
    /// ## ⚠️ 原先这里少算了一位（2026-10-14 修，与嵌套栈那次崩溃同一天发现）
    ///
    /// 原来写的是 `levels.removeLast(levels.count - index)`，而"要保留几层"是
    /// `index + 1` ⇒ 两个后果：**在子目录里点第 0 段（仓库全名）会把层级删空**
    /// （`removeLast(count)`），紧接着 `current` 就是一次 `Index out of range`；
    /// 而点第 k 段会落到第 k-1 层（错位一层）。
    /// 改成 `keep` 之后 `keep ≥ 1` 恒成立 ⇒ 层级**永不为空**
    /// （`current` 那条"由构造保证"的注释说的就是这里）。
    ///
    /// ⚠️ **2026-10-14 当天原型也改成了这一套**（`codeGo` 只重绘 `#codeBody`、
    /// 不推新页面）—— 这里**不再是**"与原型有意不同"，两边现在是同一个模型：
    /// 点文件夹往里走、点面包屑跳层、返回键回上一层，三条路共用同一个层级。
    ///
    /// （改动之前原型这一处是 `navToSub` —— **推入一层新页面**，于是"返回上一层"
    /// 要靠返回键、而每一层都要从头部重取一遍。那条通路已随原型同步一起删掉。）
    private func pop(toCrumb index: Int) {
        let keep = index + 1 // 第 0 段是仓库全名 = `levels[0]`
        // 点最后一段（= 当前层）时它本来就不可点，这一句只是兜底。
        guard keep < levels.count else { return }
        levels.removeLast(levels.count - keep)
    }

    // MARK: - 弹层

    @ViewBuilder
    private func presented(_ route: CodeSheet) -> some View {
        switch route {
        case let .branch(path):
            BranchSheet(
                state: session(at: path).branchList,
                currentBranch: session(at: path).branch ?? "",
                // 他人仓库那一档不给「管理分支…」（见类型说明）。
                isReadOnly: readOnly,
                onSelect: { picked in
                    sheet = nil
                    Task {
                        await model.switchBranch(
                            to: picked, sessions: levels.map(\.session)
                        )
                    }
                },
                onManage: {
                    sheet = nil
                    env.router.push(.branches(fullName: fullName))
                },
                onRetry: { Task { await model.loadBranches(session(at: path)) } }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .task { await model.loadBranches(session(at: path)) }

        case let .addFile(path):
            // §5.8。⚠️ 三个出口**都是"换成另一张"**（编辑器 / 提交弹层），
            //    所以这里每一处都先把 `sheet` 置成下一个值 ——
            //    直接 `dismiss()` 会先关掉这张、再开下一张，中间那一帧是空屏。
            AddFileSheet(
                branch: session(at: path).branch ?? "",
                intake: intake,
                onNewFile: {
                    sheet = nil
                    // 新建模式的路径由**编辑器里的输入框**定（§4.6），
                    // ⚠️ 但要把它**预填成"就在这一层目录里建"**（2026-10-12 用户报回
                    //    「添加 / 上传都落在根目录、而不是我打开的对应目录」）——
                    //    根目录时传 `nil`，编辑器那边与过去逐字相同。
                    env.router.push(.editor(
                        fullName: fullName,
                        path: nil,
                        mode: .create,
                        directory: path.isRoot ? nil : path.raw
                    ))
                },
                onPicked: { draft in
                    // 选中那一刻字节已经在手上（`UploadDraft` 的说明）——
                    // 这里只把它交给下一张弹层，**并带上落点那一层**。
                    sheet = .upload(draft, directory: path)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)

        case let .upload(draft, directory):
            // §5.8 的后两个出口 → §5.9 的提交弹层（**同一个** `CommitSheet`，
            // 与编辑器那条路共用；差别只在标题来源与多一行只读的落点）。
            uploadCommitSheet(draft, directory: directory)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    /// 上传出口的「提交更改」（§5.8 → §5.9）。
    ///
    /// ⚠️ 用的是**与编辑器同一个** `CommitSheet`。差别只有三处：
    /// 标题来源（`draft.source`）、多一行只读的「将写入 `{路径}`」、
    /// 以及这一条路**恒为新建**（`model.upload` 写死 `nil`）。
    /// 另做一张弹层会让 §5.9 那两行输入 / 409 两个出口 / 两档结果屏各抄一份。
    ///
    /// ⚠️ `defaultBranchName` 在**呈现这一刻**算：`FileWriteTarget.defaultNewBranchName(now:)`
    /// 的 `now` 必传（同 `EditorView`），在这里取 `Date()` 与在那里取是同一件事 ——
    /// 关键是它只在弹层出现时算一次，而不是每次重绘都变。
    private func uploadCommitSheet(_ draft: UploadDraft, directory: RepoPath) -> some View {
        let session = session(at: directory)

        return CommitSheet(
            source: draft.source,
            fullName: fullName,
            branch: session.branch ?? "",
            // ⚠️ 上传出口**必须露出落点**：路径是 App 定的（§5.8 / 决策 #70②），
            //    不露出来用户就只能靠猜 —— 而"东西存到哪"是这一步唯一可能搞错的事。
            //    ⚠️ 它与 `model.upload` 写下去的是**同一个方法**算出来的那一份
            //    （`uploadDestination`）—— 两处各算一次的那天，说出来的和做出来的会不一样。
            //    算不出来时给 `nil`：那一档提交必然失败，宁可**不显示**也不要显示一个假落点。
            destinationPath: model.uploadDestination(for: draft.fileName, at: directory),
            // ⚠️ 动过才非 nil（切片 8.7 / 8.8）—— 那一句 caption 就是"App 改了你选中的
            //    字节 / 甚至文件名"这件事的唯一出口（决策 #71⑤ · #72⑤）。
            adjustment: draft.adjustment,
            defaultBranchName: FileWriteTarget.defaultNewBranchName(now: Date()),
            onSubmit: { commit, _ in
                // ⚠️ 那个 `sha` 参数在这里**有意丢掉**：上传恒为新建
                //    （`RepoCodeViewModel.upload` 里写死 `nil`），不存在"基准过期"这一档。
                await model.upload(draft, commit: commit, at: directory, session: session)
            },
            onSettled: { outcome, commit in
                toast.show(CommitSheetCopy.toast(
                    for: outcome,
                    currentBranch: session.branch ?? "",
                    message: commit.effectiveMessage
                ))
                // ⚠️ **这里不 pop**：用户是从**这一页**点「添加文件」进来的，
                //    提交完该留在这儿看那个新文件（目录已由 `model.upload` 刷过）。
                //    「提交完返回上一页」是**编辑器**那条路的规定（§4.6），不是这一条。
            }
        )
    }

    /// 栈里某一层路径对应的会话。
    ///
    /// ⚠️ 到不了"找不到"那一档：会话在**推入之前**就建好了（`openDirectory`），
    /// 而栈只会被推入与截断 ⇒ 能出现在 `levels` 里的路径必然有会话。
    /// 写成 `?? levels[0].session` 只是为了让类型成立，不是一条真会走到的分支
    /// （真走到的话是上面的前提被破坏，而不是这里少判了一次）。
    private func session(at path: RepoPath) -> RepoTreeSession {
        levels.first { $0.path == path }?.session ?? levels[0].session
    }
}

/// 页内层级里的一层：**路径 + 那一层自己的会话**。
///
/// ## ⚠️ 为什么会话要跟着层走
///
/// 1. **"哪一层用什么数据"要在推入那一刻就定。** 若改成"另开一张表按路径查、
///    没有就建一个"，那句"没有就建一个"会落在**渲染期间** ——
///    在 `content` 里改状态是 SwiftUI 明令禁止的（运行时会有告警，而界面不一定看得出异常）。
/// 2. （原）`NavigationStack` 的 `navigationDestination` 在渲染期间求值 ⇒ 会话必须
///    能跟着路径值走。**这个理由随嵌套栈一起去掉了**（2026-10-14，见 `RepoCodeView` 的说明）。
/// 3. **只有栈顶那一层被渲染** ⇒ 底下几层的视图是销毁的。"返回上一层内容立刻就在"
///    全靠**会话还躺在 `levels` 里**（它带着已经落地的目录页）。若把会话挂在视图上
///    （`content` 里的 `@State`），返回时就要重取一遍 —— 那正是用户报的那个问题。
///
/// ⚠️ `==` 只认 `path`（会话是引用类型，不该参与相等判断）——
/// `openDirectory` 靠它防"点同一行两次叠出两层一样的页面"。
///
/// ⚠️ **2026-10-14：`Identifiable` 与 `Hashable` 一起删了**（那时只写 `Equatable`）。
/// 两个都只服务嵌套栈那条 `NavigationStack(path:)`（它要求元素 `Hashable`、
/// 顺带给过一个 `id`）；现在唯一的用法是上面那个 `contains` ⇒ **只需要 `==`**。
private struct RepoCodeLevel: Equatable {

    let path: RepoPath
    let session: RepoTreeSession

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.path == rhs.path }
}

/// 代码页那个 `.task(id:)` 的 id —— **哪一层 + 哪条默认分支**（2026-10-14 新增）。
///
/// ## ⚠️ 为什么是结构体，而不是拼成一个字符串
///
/// `.task(id:)` 只认一件事：**这个值变没变**。所以这个类型存在的全部意义就是
/// "把'该不该重跑取数'的那几个输入**一个不漏地**装进来"，而结构体让这件事由编译器保证
/// （两个字段都得给，少一个编译不过）。
///
/// ⚠️ 上一版拼的是字符串，而且**只带了默认分支**（`"\(branch ?? "-")"`）——
/// 于是换层（点目录 / 点面包屑 / 返回上一层）时那个值一个字都没变 ⇒ `.task` 不重跑
/// ⇒ 新那一层的会话从没被取过（`page` 停在 `idle`）⇒ 屏幕上是一块**永不消失的骨架**。
/// 这就是 2026-10-14 用户报回的那条：**点二级目录一直停在骨架屏，而别的页面都正常**
/// （所以也不像网络问题）。⚠️ 它是同日"删掉嵌套栈"那次修复的**直接后果**：在那之前
/// 每一层是各自一个 `navigationDestination` 视图、各有自己的 `.task`
/// ⇒"每进一层会取数"是**栈**给的保证，收掉栈之后没有人接这棒。
///
/// ⚠️ 改成结构体之后，"漏一半"不再是一种写法；顺带把拼字符串那版要额外操心的两件
/// 与取数无关的事（分隔符用什么、`nil` 拿什么占位）一并消掉了。
///
/// ⚠️ 两个字段各自管一件事、**都不能省**（逐条见 `tree(_:)` 里那两条注释）：
/// - `branch`：它是**异步**来的，无 id 的 `.task` 会在它还是 `nil` 时就跑完并返回；
/// - `path`：换层的唯一信号（那一刻分支不会变）。
private struct RepoCodeLoadKey: Equatable {

    /// 进页时解析出的默认分支 —— `load` 的**前提**（它第一条守卫就是 `guard let defaultBranch`）。
    ///
    /// ⚠️ 在**当前结构**里它**到不了 `nil`**：这个 `.task` 挂在 `tree(_:)` 上，而那一支只在
    /// 分支到手之后才会被渲染（分支还没来那一格骨架由 `content(_:)` 画）⇒ 这一半现在
    /// 不会真的触发过一次重跑。留着它的理由是**它描述了取数的依赖**：哪天骨架改成由
    /// "会话自己"画（那时 `.task` 会先带着 `nil` 跑一次），少了它就会静默退化成
    /// "永远停在骨架屏"—— 那正是这条缺陷的另一副面孔。
    let branch: String?

    /// 这一层在仓库内的相对路径（根 = `RepoPath.root`）。
    let path: RepoPath
}
