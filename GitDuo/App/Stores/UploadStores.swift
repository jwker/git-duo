import Foundation
import GitDuoKit

/// 上传目标的**落盘实现**（`UserDefaults` + 字典）。
///
/// ## 分工
///
/// 行为在领域包（`UploadTargetStore` 协议 + `InMemoryUploadTargetStore` 的参照实现），
/// 本类型只管存取 —— 与 `UserDefaultsBranchMemoryStore` 同一分工。
/// 落盘实现**没有测试**（App target 的测试 target 刚在 T1 计划里建起来，
/// 但这一层不值得单独开一个 App 层测试），所以它**不重写任何语义**。
///
/// ## 存储形状
///
/// `UserDefaults` 的原生字典（plist 支持字符串字典）—— 不走 JSON：
/// 三个字段都是字符串，中间加一层编解码只会多一处能出错的地方。
///
/// ⚠️ 它是**账号绑定数据**：仓库全名与目录路径会暴露私有仓库的结构
/// ⇒ 登出时必须 `clear()`（`AppEnvironment.signOut()` 里那条）。
actor UserDefaultsUploadTargetStore: UploadTargetStore {

    static let keyPrefix = "GitDuo.uploadTarget"

    private let defaults: UserDefaults
    private let key: String

    /// - Parameter namespace: 账号命名空间（多账号预留，同 `UserDefaultsBranchMemoryStore`）。
    init(defaults: UserDefaults = .standard, namespace: String = "default") {
        self.defaults = defaults
        self.key = "\(Self.keyPrefix).\(namespace)"
    }

    /// 用一个**独立的 suite** 造（测试用）。
    ///
    /// ## ⚠️ 为什么要有这一条，而不是让测试自己造 `UserDefaults` 传进来
    ///
    /// `UserDefaults` **不是 `Sendable`** ⇒ Swift 6 严格并发下，
    /// 从一个隔离上下文把它传进 actor 的初始化会被编译器拦下
    /// （"sending … risks causing data races"）。
    /// 让 actor **自己**按 suite 名造这份 `UserDefaults`，那个值就从不跨隔离边界。
    ///
    /// - Parameter suiteName: suite 名（测试里给一个每次都不一样的）。
    init(suiteName: String, namespace: String = "default") {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.key = "\(Self.keyPrefix).\(namespace)"
    }

    func target() async -> UploadTarget? {
        guard let raw = defaults.dictionary(forKey: key) as? [String: String] else { return nil }
        guard let fullName = raw["fullName"], let branch = raw["branch"] else { return nil }
        return UploadTarget(
            fullName: fullName,
            directory: RepoPath(path: raw["directory"] ?? ""),
            branch: branch
        )
    }

    func remember(_ target: UploadTarget) async {
        defaults.set(
            [
                "fullName": target.fullName,
                "directory": target.directory.raw,
                "branch": target.branch
            ],
            forKey: key
        )
    }

    func clear() async {
        // 与另外几个 store 一样删键而不是留一份空字典：读取端分辨不出这两者，
        // 能不落痕就不落痕。
        defaults.removeObject(forKey: key)
    }
}

/// 「当前所在」的上下文 —— **用户正站在哪个仓库的哪个目录里**。
///
/// ## 它为什么存在
///
/// 2026-10-23 定的口径：**上下文优先**（`.ai/memory.md` §4）。
/// 悬浮按钮是**全局**的，而上传目标是**记忆**的 ——
/// 站在 A 仓库的代码页点开按钮，若拿的是记忆里的 B 仓库，就会把图传到 B 去。
/// 于是需要一个"我现在在哪儿"的来源：仓库页把当前位置写进来，
/// 离开时清掉；上传弹层据此决定默认目标。
///
/// ## ⚠️ 它是**瞬时状态**，不是记忆
///
/// 记忆是"上次用的目标"（跨会话、落盘）；上下文是"这一秒站在哪"（不落盘）。
/// 两者混在一起会出现"关掉 App 再打开，还站在昨天的目录里"的错觉。
actor UploadContextStore {

    private var target: UploadTarget?

    /// 写当前上下文（`nil` = 不在任何仓库里）。
    func set(_ target: UploadTarget?) {
        self.target = target
    }

    /// 读当前上下文。
    func current() -> UploadTarget? {
        target
    }

    /// **只当"当前值还是我写的那份"时**才清掉。
    ///
    /// ## ⚠️ 为什么不能直接 `set(nil)`
    ///
    /// 页面离开的时机与下一个页面写入的时机**没有顺序保证** ——
    /// 若 A 页的 `onDisappear`（清空）晚于 B 页的 `onAppear`（写入），
    /// 就会把 B 页刚写的上下文抹掉 ⇒ 上传的默认目标变成"没有"。
    /// 而"没有上下文"的表现是**静默**的（退回记忆），很难归因。
    ///
    /// ⇒ 清空时带上自己写的那份，对不上就不动（那说明已经有更新的值了）。
    func clear(ifCurrentIs target: UploadTarget?) {
        guard self.target == target else { return }
        self.target = nil
    }
}
