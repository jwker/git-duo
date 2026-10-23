import GitDuoDesign
import GitDuoKit
import SwiftUI
import UIKit

/// 主界面容器：4 个 Tab（首页 / 仓库 / 探索 / **搜索**），每个 Tab 一条独立导航栈。
///
/// 依据：TECH_SPEC §8.1。
/// 铁律：
/// 1. **未认证时不构建本视图**（由 `RootView` 决定，§3.8）。
/// 2. `TabView` 是系统组件 → Liquid Glass 自动生效，**不要自己给 Tab 栏加玻璃**（§10.2）。
/// 3. 各 Feature 的依赖**在这里（组合根的下游一格）经本视图传给根页** ——
///    根页自己不构造客户端（AGENTS.md §3）。
///
/// ## ⚠️ 2026-10-16：「我的」不再是根页（走查第 85 条）
///
/// 第 4 格从「我的」换成「搜索」，而「我的」改从**首页右上角那颗头像**进 ——
/// 它现在是一条普通推入页（`Route.profile`，由 `RouteView` 组装）。
/// 交换的理由与连带影响写在 `AppTab` 的类型说明里。
struct MainTabView: View {

    /// 登录名 —— ⚠️ 现在**只服务 `HomeView`**（它要拿它拼「管理」跳网页端那个地址）。
    ///
    /// 它从前还给 `ProfileView` 用（那时「我的」是本容器的根页之一）；
    /// 那一页成为推入页之后，它的 `login` 由 `RouteView` 从 `authState` 取
    /// —— 两处都取自同一个来源，不会出现"两个登录名"。
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
                        identity: env.profileOverview,
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
            // ⚠️ 2026-10-16：这一格从「我的」换成「搜索」（走查第 85 条）——
            //    理由写在 `AppTab` 的类型说明里。⚠️ `login` 这个参数**本 Tab 用不到**
            //    （它只服务 `HomeView`）；「我的」现在是**推入页**，由 `RouteView` 组装
            //    （那边的 `login` 取自 `authState`，同 `.settings`）。
            Tab(AppTab.search.title, systemImage: AppTab.search.systemImage, value: AppTab.search) {
                NavigationStack(path: $router.search) {
                    SearchView(loader: env.search, history: env.searchHistory)
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
        //    用布尔量的话第二条会“原地换字”，看起来像没反应。
        .animation(Toast.animation(reduceMotion: reduceMotion), value: env.toast.message)
        // ⚠️ **悬浮按钮挂在这层**（与 `Toast` 同一个通道）：它是**全局入口**
        //    （2026-10-23 定的口径：每个页面都常驻）⇒ 只能有**一个实例** ——
        //    每页各放一个的话，推入页上会多出一颗，而 tab 之间切换时那颗会跳位。
        .overlay(alignment: .bottomTrailing) {
            FloatingActionButton(
                systemImage: "photo.badge.plus",
                accessibilityLabel: UploadImageCopy.floatingButtonAccessibilityLabel
            ) {
                isUploadSheetPresented = true
            }
            // ⚠️ **键盘弹出时收起**：它浮在右下角，键盘一升起来就压住输入区 ——
            //    而那正是"在写东西"的时候。
            .opacity(isKeyboardVisible ? 0 : 1)
            .allowsHitTesting(!isKeyboardVisible)
            .padding(.trailing, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.l + 83)
        }
        .sheet(isPresented: $isUploadSheetPresented) {
            UploadImageSheet(
                repositories: env.repositories,
                detail: env.repoDetail,
                branches: env.branches,
                treeLoader: env.repoTree,
                saver: env.saveFile,
                intake: env.uploadIntake,
                memory: env.uploadTargetStore,
                context: env.uploadContext,
                toast: env.toast
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // ⚠️ 键盘的可见性用**系统通知**判：没有一条官方的"键盘是否在屏幕上"的环境值，
        //    而这个按钮的诉求就是“别挡着输入区”。
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }

    /// 上传弹层是否呈现。
    @State private var isUploadSheetPresented = false

    /// 键盘是否压着屏幕（悬浮按钮据此收起）。
    @State private var isKeyboardVisible = false
}

#Preview {
    MainTabView(login: "jiangjiang").environment(AppEnvironment())
}
