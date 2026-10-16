import GitHubAPI
import GitDuoDesign
import SwiftUI

/// **整页失败块** —— 首屏拿不到，屏幕上除了它没有别的东西（PRD §1 设计原则 4）。
///
/// ## 它与 `SectionFailure` 的分工
///
/// | | `PageFailure`（本件） | `SectionFailure` |
/// |---|---|---|
/// | 什么时候 | 整页的主数据没出来 | 页面里**某一块**没出来 |
/// | 文案 | `加载失败` | `这一块加载失败` |
/// | 别的部分画不画 | 不画（分段条也不画） | 照画 |
/// | 字号 | `body`(17) + 图标 30 | `footnote`(13)，没有图标 |
///
/// 两者的读屏 hint **共用同一张表**（`SectionFailure.hint(for:)`）——
/// 失败原因说的是同一件事，两处各写一张表的下场是其中一处改了口径。
///
/// ## ⚠️ 为什么现在才把它提出来
///
/// 切片 7.4 之前，这个形状在仓里已经有**六份**（`RepoDetailView` / `CommitDetailView` /
/// `BranchesView` / `ExploreRepoDetailView` / `ExploreIssueListView` / `ExplorePRListView`，
/// `HomeView` 另有一份形态不同的）。本节要新写两个详情页 ⇒ 会变成第八、第九份。
///
/// **本次收口了 `Features/Repo/Views/` 下的三处**（它们与本件逐字相同）。
/// ⚠️ `Features/Explore/` 下的三处**仍然是各自的私有实现**，没有合并 ——
/// 它们的标题走 `ExploreRepoCopy.failureTitle`（领域层给的文案），
/// 收口要给本件加一个 `title` 参数并动三个别的 Feature 的文件。
/// 那是一次独立的整理，**已登记为欠账**，不在切片 7.4 里顺手做。
///
/// ## 判据 #43
///
/// 只收 `GitHubError`（数据层的错误类型，不是领域模型）+ 一个闭包 ⇒ 不认识业务。
/// 与 `SectionFailure` 一样**先留在 Feature**（"跨 Feature 才搬进设计包"）。
///
/// ## ⚠️ 2026-10-16 起它**用官方 `ContentUnavailableView` 画**（NATIVE-MIGRATION P1）
///
/// 从前是"30pt 警告三角 + 标题 + 重试"那一套手摆的 `VStack`。换成官方件之后：
/// 图标与标题的间距、标题与说明的字号层级、按钮的位置、`padding`、
/// 深浅两档配色、Dynamic Type —— **全部由系统给出**。
///
/// 收进 `actions:` 的重试按钮**必须留**（PRD §1 设计原则 4：任何失败都有出口）
/// —— 官方件正是"空态 / 失败态 + 一个出口"这个完整形状，
/// 从前那种"自己再摆一个按钮"的做法才是把它拆成了两件。
struct PageFailure: View {

    let error: GitHubError

    /// 重试。**必须留这个出口**（PRD §1 设计原则 4：任何失败都有出口）。
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(Self.title, systemImage: Self.symbol(for: error))
        } description: {
            Text(SectionFailure.hint(for: error))
        } actions: {
            Button(Self.retry, action: onRetry)
        }
        // 失败原因**只说确定的那一件事**：404 与无权限被 GitHub 混同（§4.3），
        // 不得替用户断定是"它不存在"还是"你没权限"。
        //
        // ⚠️ 这句 hint **仍然要手工给**：系统不知道 `GitHubError` 是什么，
        // 而"断网"与"被限流"对读屏用户是两句不同的引导。
        .accessibilityHint(SectionFailure.hint(for: error))
    }

    /// 整页失败的标题。
    ///
    /// ⚠️ 与 `SectionFailure.title`（`这一块加载失败`）**不是同一句**：
    /// 整页失败时屏幕上已经没有别的块了。
    static let title = "加载失败"

    /// 重试按钮。
    static let retry = "重试"

    /// **失败图标随原因变** —— 官方空态是"图标 + 标题"这个组合，图标就该说同一件事。
    ///
    /// ⚠️ 四个名字都**在宿主机上验过存在**（`NSImage(systemSymbolName:)`）；
    ///    见 `GitHubIcon` 抬头那条告诫 —— 名字写错不会报错，只在界面上凭空消失。
    static func symbol(for error: GitHubError) -> String {
        switch error {
        case .transport: "wifi.exclamationmark"
        case .rateLimited: "clock.badge.exclamationmark"
        case .unauthorized: "person.badge.key"
        default: "exclamationmark.triangle"
        }
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.xl) {
        PageFailure(error: .transport(URLError(.notConnectedToInternet))) {}
        PageFailure(error: .rateLimited(resetAt: .now.addingTimeInterval(600), isSecondary: false)) {}
        PageFailure(error: .notFound) {}
    }
    .padding(.horizontal, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
