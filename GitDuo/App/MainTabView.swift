import SwiftUI

/// 主界面容器：4 个 Tab，每个 Tab 一条独立导航栈。
///
/// 依据：TECH_SPEC §8.1。
/// 铁律：
/// 1. **未认证时不构建本视图**（由 `RootView` 决定，§3.8）。
/// 2. `TabView` 是系统组件 → Liquid Glass 自动生效，**不要自己给 Tab 栏加玻璃**（§10.2）。
struct MainTabView: View {

    let login: String

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        @Bindable var router = env.router

        TabView(selection: $router.selection) {
            Tab(AppTab.home.title, systemImage: AppTab.home.systemImage, value: AppTab.home) {
                NavigationStack(path: $router.home) {
                    HomeView(login: login)
                        .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
            Tab(AppTab.repos.title, systemImage: AppTab.repos.systemImage, value: AppTab.repos) {
                NavigationStack(path: $router.repos) {
                    ReposView()
                        .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
            Tab(AppTab.explore.title, systemImage: AppTab.explore.systemImage, value: AppTab.explore) {
                NavigationStack(path: $router.explore) {
                    ExploreView()
                        .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
            Tab(AppTab.profile.title, systemImage: AppTab.profile.systemImage, value: AppTab.profile) {
                NavigationStack(path: $router.profile) {
                    ProfileView()
                        .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
            }
        }
    }
}

#Preview {
    MainTabView(login: "jiangjiang").environment(AppEnvironment())
}
