import SwiftUI

/// 四个底部 Tab。
/// 依据：PRD §1（首页 / 仓库 / 探索 / 我的）。**通知本期不做**（决策 → Tab 由 5 减为 4）。
///
/// ## ⚠️ 2026-10-16 起第 4 格是「搜索」而不是「我的」（走查第 85 条）
///
/// 用户要求：**「我的」让位给「搜索」**，而「我的」改从**首页右上角那颗头像**进
/// （`Route.profile` —— 它现在是一条推入页，不再是根页）。
///
/// 为什么这个交换说得通：搜索是**高频入口**，而它从前挂在三个根页右上角那颗放大镜上
/// —— 三处重复、且都不是"可以在任何地方按下去"的位置；「我的」相反，是低频页。
/// 交换之后搜索拿到了底部一格（任何 Tab 下都够得到），「我的」保留一个**看得见头像**的入口。
/// App Store 的 Today 页用的正是这个形状（大标题 + 右上角头像，搜索在底部一格）。
///
/// ⚠️ 连带的一条：`Route.search` **已删除** —— 三个放大镜没有了，
/// 搜索页现在只由本 Tab 呈现，它不再需要一条路由。
enum AppTab: String, Hashable, Sendable, CaseIterable, Identifiable {
    case home
    case repos
    case explore
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .repos: "仓库"
        case .explore: "探索"
        case .search: "搜索"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .repos: "folder"
        case .explore: "safari"
        case .search: "magnifyingglass"
        }
    }
}

/// 导航栈管理。
///
/// 依据：TECH_SPEC §8.1。
/// 铁律：**每个 Tab 各持一条独立栈**，切 Tab 保留各自层级。
///
/// ⚠️ 两条纪律（原型阶段都踩过）：
/// 1. 所有**路由逻辑**（push / pop / reset）一律经 `path(for:)` 按 `selection` 取栈，
///    **禁止**在逻辑里写死某一个 Tab 的栈。
/// 2. 视图层为每个 Tab 绑定时，只允许 `$router.home` 这种"各绑各的"写法——
///    这是 Binding 的类型要求，不代表逻辑可以写死 Tab。
@MainActor
@Observable
final class Router {

    // 每 Tab 一条栈（视图层各自 `NavigationStack(path:)` 绑定）
    var home = NavigationPath()
    var repos = NavigationPath()
    var explore = NavigationPath()
    var search = NavigationPath()

    /// 当前选中的 Tab
    var selection: AppTab = .home

    /// 按 Tab 取栈（所有路由逻辑的唯一入口）
    func path(for tab: AppTab) -> NavigationPath {
        switch tab {
        case .home: home
        case .repos: repos
        case .explore: explore
        case .search: search
        }
    }

    func setPath(_ newPath: NavigationPath, for tab: AppTab) {
        switch tab {
        case .home: home = newPath
        case .repos: repos = newPath
        case .explore: explore = newPath
        case .search: search = newPath
        }
    }

    /// 推入一个页面（作用于**当前选中的 Tab**）
    func push(_ route: Route) {
        var target = path(for: selection)
        target.append(route)
        setPath(target, for: selection)
    }

    /// 出栈一层（作用于当前选中的 Tab）
    func pop() {
        var target = path(for: selection)
        guard !target.isEmpty else { return }
        target.removeLast()
        setPath(target, for: selection)
    }

    /// 回到某个 Tab 的根页
    func popToRoot(_ tab: AppTab) {
        setPath(NavigationPath(), for: tab)
    }

    /// 退出登录 / 切换账号：**重置全部栈与 Tab 选中项**（§3.5 登出清理范围）
    func resetAll() {
        home = NavigationPath()
        repos = NavigationPath()
        explore = NavigationPath()
        search = NavigationPath()
        selection = .home
    }
}
