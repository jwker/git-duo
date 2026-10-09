import GitDuoDesign
import SwiftUI

/// 主界面容器：4 个 Tab，每个 Tab 一条独立导航栈。
///
/// 依据：TECH_SPEC §8.1。
/// 铁律：
/// 1. **未认证时不构建本视图**（由 `RootView` 决定，§3.8）。
/// 2. `TabView` 是系统组件 → Liquid Glass 自动生效，**不要自己给 Tab 栏加玻璃**（§10.2）。
/// 3. 各 Feature 的依赖**在这里（组合根的下游一格）经本视图传给根页** ——
///    根页自己不构造客户端（AGENTS.md §3）。
struct MainTabView: View {

    let login: String

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var router = env.router

        TabView(selection: $router.selection) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                NavigationStack(path: $router.home) {
                    HomeView(
                        login: login,
                        pinned: env.pinnedRepositories,
                        visits: env.recentVisits,
                        toast: env.toast
                    )
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
            Tab(AppTab.repos.title, systemImage: AppTab.repos.systemImage, value: AppTab.repos) {
                NavigationStack(path: $router.repos) {
                    // 依赖从组合根**经本视图**传下去：`ReposView` 自己不构造客户端。
                    ReposView(loader: env.repositories)
                        .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
            Tab(AppTab.explore.title, systemImage: AppTab.explore.systemImage, value: AppTab.explore) {
                NavigationStack(path: $router.explore) {
                    ExploreView(loader: env.trending)
                        .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
            Tab(AppTab.profile.title, systemImage: AppTab.profile.systemImage, value: AppTab.profile) {
                NavigationStack(path: $router.profile) {
                    // ⚠️ `login` 这个参数是切片 9.4 补上的：本页要画大头像与 `@登录名`，
                    //    而它们**不从网络来**（本机由登录名画出来）⇒ 拿的就是这里这个值。
                    //    它同时是 `ProfileView` 里"昵称 / 简介"之外的**唯一不可失败项**。
                    ProfileView(login: login, overview: env.profileOverview)
                        .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
        }
        // ⚠️ 提示层挂**这里**、不是挂在每个页面上：四个 Tab、七条导航栈共用一个通道
        //    （`ToastCenter` 的类型说明写了漏掉会怎样）。overlay 在 TabView 之上，
        //    所以推入的详情页也盖得住。
        .overlay(alignment: .bottom) {
            if let message = env.toast.message {
                Toast(message: message)
                    .transition(Toast.transition(reduceMotion: reduceMotion))
            }
        }
        // ⚠️ `value:` 用**文案本身**（不是 `isShowing`）：连着两条不同文案之间也要重播动画，
        //    用布尔量的话第二条会"原地换字"，看起来像没反应。
        .animation(Toast.animation(reduceMotion: reduceMotion), value: env.toast.message)
    }
}

#Preview {
    MainTabView(login: "jiangjiang").environment(AppEnvironment())
}
