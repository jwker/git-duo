import Foundation
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 设置页的状态（PRD §4.20、TECH_SPEC §9.15；决策 #75）。
///
/// ## 这一页只有**一个**活数据，而它要小心取
///
/// 三个分区五行里，四行是常量（主题 / 账号 / 授权状态 / 版本），只有
/// 「清除缓存」右边那个大小是活的 —— 它来自 `HTTPResponseCache.totalByteCount`，
/// 而这个属性要**遍历磁盘目录**（决策 #75 末段）。
///
/// ⇒ 所以：**进页取一次、清完再取一次**，绝不在 `body` 里算。
/// 每帧算一次的后果不是"慢一点"，而是滚动 / 重绘都会被文件系统 IO 拖住。
///
/// ## ⚠️ 它只清接口缓存，**不动任何账号数据**
///
/// 决策 #75：保留 Keychain 凭据（登录状态不变）、保留最近访问 / 搜索历史 /
/// 分支记忆 / 评论草稿（它们不是缓存），**也不动 `LoadSearch` 的结果缓存**
/// （那是登出才清的东西）。所以本类型手里**只有** `HTTPResponseCache` 一个依赖 ——
/// 它没有能力去碰别的东西，这件事在类型上就成立了。
///
/// ## 登出**不在这里**
///
/// 那一步会换掉整个主界面（`authState` 回未认证 ⇒ `RootView` 二分），
/// 属于组合根 `AppEnvironment.signOut()`（§3.6 的四步）。本类型只负责
/// "把弹层收起来、把这件事交给组合根"。
@MainActor
@Observable
final class SettingsViewModel {

    /// 本页的弹层路由（目前只有一张：§5.11）。
    ///
    /// ⚠️ 仍然是枚举而不是布尔量：`SignOutConfirmSheet` 的确认按钮要**先关弹层、
    /// 再登出**，而那一步靠"把值写回 `nil`"表达（见 `SettingsView`）。
    enum SheetRoute: Identifiable, Hashable, Sendable {
        case signOut

        var id: String { "signOut" }
    }

    var sheet: SheetRoute?

    /// 接口缓存当前占用的字节；`nil` = 还没算过。
    ///
    /// ⚠️ `nil` 与 `0` **不是一回事**：`0` 是"确实没有缓存"（真机上常见，
    /// 因为本包不挂 `URLCache`、缓存全在自建的那份里），而 `nil` 是"还没量"。
    /// 视图靠 `nil` 决定**不画那个值**，而不是画一个 `0.0 MB` 的假数。
    private(set) var cacheBytes: Int?

    /// 清缓存在途（防连点）。
    private(set) var isClearing = false

    /// 账户分区那一行要的登录名（TECH_SPEC §9.15：取自 `authState`，**不再打一次 `/user`**）。
    let login: String

    /// 版本那一行的值（`{短版本} ({构建号})`，两个数都从 `Bundle` 现读）。
    let versionText: String

    private let cache: HTTPResponseCache
    private let toast: ToastCenter

    init(login: String, cache: HTTPResponseCache, toast: ToastCenter) {
        self.login = login
        self.cache = cache
        self.toast = toast
        self.versionText = Self.appVersionText
    }

    // MARK: - 缓存

    /// 进页 / 下拉刷新时量一次。
    func loadCacheSize() async {
        cacheBytes = await cache.totalByteCount
    }

    /// 清空 + 报告释放量。
    ///
    /// ⚠️ `removeAll()` 的**返回值就是释放的字节数**（它自己算的），
    /// 不是"清之前减清之后"—— 后者在两次读取之间会被别的请求写进来，
    /// 于是报出来的数可能是个负数。
    func clearCache() async {
        guard !isClearing else { return }
        isClearing = true
        defer { isClearing = false }

        let released = await cache.removeAll()
        // 清完再量一次，让那一行当场变成新值（§9.15）。
        await loadCacheSize()
        toast.show(ProfileCopy.cacheCleared(released: released))
    }

    // MARK: - 内部

    /// 版本串 `2.0 (1)`（原型逐字，**两个数都是活的**）。
    ///
    /// ⚠️ **不许硬编码**（PRD §4.20 走查单点名）：写死了每次发版都要改代码，
    /// 而漏改**不会报错**，只会一直在界面上显示旧版本。
    ///
    /// `—` 是取不到时的兜底 —— 它在本工程里不可达（`project.yml` 两个键都设了），
    /// 沿用 `RepositoryResultRow` 对空简介的处置（同一个字形、同一个意思：
    /// "这里有一个事实，但我读不到"）。
    private static var appVersionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return ProfileCopy.version(short: short, build: build)
    }
}
