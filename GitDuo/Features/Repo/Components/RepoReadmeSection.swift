import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 仓库首页上的 **README 区块** —— 小节标题 + 正文，自带三档（§4.4 / §4.13）。
///
/// ## ⚠️ 2026-10-14：它是从 `RepoTreeSection.readmeSection` **平移**出来的
///
/// 在那之前 README 画在**代码页的仓库根那一层**（README 与目录是一体的）。
/// 现在它画在两个**首页**上：§4.4 自己的仓库（四行入口之下）与 §4.13 他人仓库
/// （⑤ 文件浏览那一条入口之后）—— 于是这一块连同它那三套接线一起搬到这里。
///
/// ⚠️ **两页共用一份**是有判据的（与 `RepoTreeSection` 当年收成一份同一条）：
/// 下面那三套接线里有两套属于"错了不报错"的那一类，两处各写一遍，
/// 将来只会改到其中一份。
///
/// ## 它的三套接线（都在这里，别在调用方再写一遍）
///
/// | 接线 | 漏了它的症状 |
/// |---|---|
/// | **相对链接**走 `RepoLinkResolver` | README 里绝大多数链接是仓库内相对地址（`[中文](README_zh.md)`）⇒ 系统打不开没有 scheme 的地址，表现是"点了没反应" |
/// | **相对图片**走 `MarkdownImageContext` | 仓库内的图（`assets/hero.png`）画不出来 |
/// | 小节标题取 `RepoCopy.readmeSectionTitle` | 同一个标题在两个页面上长得不一样 |
///
/// ## ⚠️ 三档收在本件里，调用方只给一个 `LoadState`
///
/// | 档 | 画什么 |
/// |---|---|
/// | 还没到（`idle` / `loading`）| 一小块骨架（**形状与真实内容对齐**：标题条 + 几行正文条）|
/// | 有内容 | 标题 + `MarkdownBody`；⚠️ **README 不存在或全空白时什么都不画** |
/// | 失败 | `SectionFailure`（那一块给「重试」，**不掀翻整页**，§8.5）|
///
/// 收在这里而不是留给调用方各写一遍：两个页面的三档**逐字相同**，
/// 而"骨架形状"与"失败出口"是最容易在一处改、另一处忘掉的那类东西。
/// 调用方因此只剩一行（`RepoReadmeSection(state: …)`）。
///
/// ## ⚠️ 它只收值，**不收会话、不碰取数**
///
/// 需要的东西恰好都是基础值 + 一个已解析好的文档（判据 #43 的延伸）。
/// 落点由 `readOnly` **一处**决定：两页的落点逐字相同，只有"这是不是我自己的仓库"
/// 那一档不同 —— 所以它是一个 `Bool`，不是两个闭包
/// （`RepoTreeSection` 用闭包是因为它两个调用方里落点不同；这里没有）。
struct RepoReadmeSection: View {

    /// README 的取数状态。
    ///
    /// ⚠️ `LoadState<MarkdownDocument?>` 里的**内层 Optional 是有意的**：
    /// 外层是"取数到没到"（`nil` = 还没到），内层是"这个仓库到底有没有 README"
    /// （`.loaded(nil)` = 确实没有 —— 那是**正常结果**，不是错误，§9.5）。
    /// 两者混起来的话，"没有 README 的仓库"会先显示一小块永远不消失的骨架。
    let state: LoadState<MarkdownDocument?>

    let fullName: String

    /// 取 README 时用的那条分支 —— **必须与取数那一处一致**
    /// （否则切分支之后正文换了、图还是旧分支的）。
    let ref: String

    /// 这是不是我自己的仓库（铁律 #7：只读态显式传参）。
    /// 它只影响**从这里点出去**的那两页（文件页 / 代码页）拿到哪一组界面。
    let readOnly: Bool

    /// 那一块失败后的重试出口（`LoadState` 里没有"重试"这个概念，它是视图的事）。
    let onRetry: () -> Void

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        switch state.presentation {
        case .skeleton:
            // ⚠️ `.skeleton` 同时覆盖 `idle` 与 `loading`（`LoadPresentation` 的说明）——
            //    对用户来说两者都是"东西还没来"。
            skeleton

        case .content:
            content

        case let .failure(error):
            SectionFailure(error: error, onRetry: onRetry)
        }
    }

    // MARK: - 有内容

    @ViewBuilder
    private var content: some View {
        // ⚠️ 双层 Optional 在这里**压平再判**（见 `state` 的说明）：
        //    外层 `?? nil` 解掉 `LoadState` 那一层，`if let` 解掉"有没有 README"。
        if let document = state.value ?? nil, !document.isEmpty {
            SectionHeader(title: RepoCopy.readmeSectionTitle)

            MarkdownBody(
                blocks: document.blocks,
                // ⚠️ **图片也要接一次线**（2026-10-12，走查第 58 条）：README 里的图
                //    多是仓库内的相对地址，而基准目录就是**仓库根**
                //    （README 恒在根，见 `LoadRepoReadme`）。
                imageContext: MarkdownImageContext(
                    fullName: fullName,
                    ref: ref,
                    baseDirectory: .root,
                    store: env.markdownImages
                )
            ) { url in
                switch RepoLinkResolver.target(
                    for: url,
                    fullName: fullName,
                    // ⚠️ README 就在仓库根 ⇒ 基准恒为根（`..` 之类跳出根的地址
                    //    会被 resolver 判成 `.unresolved`，见下面那一支）。
                    baseDirectory: .root
                ) {
                case let .file(path):
                    env.router.push(.fileView(
                        fullName: fullName, path: path.raw, readOnly: readOnly
                    ))
                    return .handled

                case let .directory(path):
                    // ⚠️ 点 README 里指向某个目录的链接 ⇒ 推**代码页**，且**从那一层开始看**
                    //    （用户期望的是"打开那个目录"，而不是"回到仓库根再自己找一遍"）。
                    //    这是 `Route.repoCode` 那个 `path` 参数存在的唯一理由。
                    env.router.push(.repoCode(
                        fullName: fullName, readOnly: readOnly, path: path.raw
                    ))
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
        // 走完 `if let` 都不成立 ⇒ README 确实不存在（或全空白）⇒ **什么都不画**。
        // ⚠️ 这里**不画空态文案**：README 不是"数据"，它是仓库自己写的东西 ——
        //    "这个仓库没写 README"不值得在首页占一行字（阅读体验上反而像出了错）。
    }

    // MARK: - 骨架

    /// 一小块骨架 —— **形状与真实内容对齐**（标题条 + 几行长短不一的正文条），
    /// 数据到达时整块不跳动。
    ///
    /// ⚠️ 高度与 `RepoTreeSkeleton` 同一套口味：不留空行（正文条之间只给 `s`），
    /// 因为 README 出现时是"接着往下长"，不是"替换一整屏"。
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            // 小节标题那一行（`SectionHeader` 的字号比正文矮一档）。
            SkeletonBar(height: 13, width: 84)
                .padding(.top, Theme.Spacing.l)

            // ⚠️ 骨架要**画白卡**（2026-10-15 走查第 76 条）：方案 A 把 README 翻回一张
            //    白卡 ⇒ 骨架不画卡的话，数据到达时会"卡突然出现"跳一下
            //    （第 75 条那句"不画"是白页面下正文无面板时的结论，本条已反转）。
            PanelBox {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SkeletonBar(height: 15)
                    SkeletonBar(height: 15)
                    SkeletonBar(height: 15, width: 240)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
