import Foundation
import GitHubAPI
import GitDuoCore

/// 组合根 —— **唯一的依赖装配点**。
///
/// 依据：TECH_SPEC §2.4。
/// 铁律：View / ViewModel **不得自行构造客户端**，一律从 environment 取。
///
/// 本文件当前处于骨架阶段：只装配"已存在的东西"。
/// 各 Feature 的 Repository / ViewModel 在其对应垂直切片并入（顺序见 AGENTS.md）。
@MainActor
@Observable
final class AppEnvironment {

    /// 认证状态（驱动 `RootView` 的门禁二分）
    var authState: AuthState

    /// 凭据存储。生产实现应为 Keychain 版本；骨架期用内存实现以便跑通 UI。
    /// ⚠️ 切片 1（Auth）必须替换为 Keychain 实现 —— 见 REVIEW-CHECKLIST 前置条件 P4。
    let tokenStore: any TokenStore

    /// 每个 Tab 各自的导航栈
    let router = Router()

    init(
        authState: AuthState = .unauthenticated,
        tokenStore: any TokenStore = InMemoryTokenStore()
    ) {
        self.authState = authState
        self.tokenStore = tokenStore
    }

    /// 骨架期的"跳过登录"开关：仅供在登录切片落地前检视主界面。
    /// ⚠️ 切片 1 完成后必须删除（不得出现在任何发布构建里）。
    func debugBypassLogin() {
        authState = .authenticated(login: "jiangjiang")
    }
}

// MARK: - 骨架期占位类型说明

/// ⚠️ 以下类型是**契约占位**，将在对应切片被真实实现替换：
/// - `TokenStore`（GitDuoCore）：Keychain 实现 —— 切片 1
/// - `GitHubRESTClient` / `GitHubGraphQLClient`（GitHubAPI）：切片 2
/// 占位不是"以后再补"，而是**明确标注的待办**：任何以占位形式存在的类型都必须在此登记。
enum SkeletonPlaceholders {
    static let registry: [String] = [
        "TokenStore.Keychain 实现（切片 1）",
        "GitHubRESTClient / ETag 缓存 / 分页 / 限流（切片 2）",
        "GitHubGraphQLClient（切片 2）",
        "各 Feature 的 Repository 与 ViewModel（切片 3+）"
    ]
}
