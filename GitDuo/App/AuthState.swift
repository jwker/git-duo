import Foundation

/// 认证状态 —— `RootView` 依据它做**门禁二分**。
///
/// 依据：TECH_SPEC §3.8 / §8.1。
/// 铁律：**未认证时不构建 `TabView`**。登录流程是门禁，不是普通页面，不占任何 Tab 的导航栈。
enum AuthState: Equatable, Sendable {

    /// 未登录 —— 展示登录页（§4.0.1）
    case unauthenticated

    /// 已完成授权跳转、等待回调 / 换令牌 —— 展示授权等待态（§4.0.2）
    case authenticating

    /// 已登录。`login` 是本地数据的命名空间键（§7.2，为将来多账号预留）
    case authenticated(login: String)

    var login: String? {
        if case let .authenticated(login) = self { return login }
        return nil
    }
}
