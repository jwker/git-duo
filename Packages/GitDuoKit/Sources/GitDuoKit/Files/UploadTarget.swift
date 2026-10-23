import Foundation

/// 「上传图片」的**目标**：写进哪个仓库的哪个目录、哪条分支。
///
/// ## ⚠️ 它为什么是**一个**类型而不是三个散落的参数
///
/// 目标天然是**一整份**：仓库 + 目录 + 分支。拆成三个参数传，
/// 就会出现"仓库换了、目录没换"（写到别的仓库的同名单目录里）这种组合 ——
/// 而那正是**写操作**里最不该出现的一种状态。
/// 于是它是一个值类型，整体传、整体比、整体记。
///
/// ## 记忆的形状
///
/// 2026-10-23 定：目标**只问一次**（`.ai/memory.md` §4）。
/// 第一次让用户选，之后每次都拿上次的当默认 ⇒ 记忆里存的就是**这一整份**。
public struct UploadTarget: Equatable, Sendable, Hashable {

    /// 仓库全名（`owner/repo`）。
    public let fullName: String

    /// 仓库内的**目录**（不是文件路径）—— 根目录是 `RepoPath.root`。
    public let directory: RepoPath

    /// 写在哪条分支上。
    public let branch: String

    public init(fullName: String, directory: RepoPath, branch: String) {
        self.fullName = fullName
        self.directory = directory
        self.branch = branch
    }

    /// 目标目录的显示文本（根目录显示仓库全名，与面包屑的口径一致）。
    public var directoryDisplay: String {
        directory.isRoot ? fullName : directory.raw
    }

    /// 一行摘要（仓库 + 目录 + 分支）—— 目标摘要行与提示文案都用它。
    public var summary: String {
        "\(fullName) · \(directory.isRoot ? "/" : directory.raw) · \(branch)"
    }
}

/// 上传目标的**记忆**（协议在领域层，落盘实现与上下文实现在 App 层）。
///
/// ## ⚠️ 与 `BranchMemoryStore` 同一分工
///
/// 协议在领域包、落盘实现在 App 组合根（"该是什么行为"与"存在哪"分开）；
/// 且**写入不触发任何回调 / 观察** —— 记忆的写入发生在弹层里，
/// 若写入立刻通知重绘，就成了一条「写入 → 重绘 → 再写入」的循环。
///
/// ⚠️ 它是**账号绑定数据**：仓库名与目录路径会暴露私有仓库的结构
/// ⇒ 登出时必须 `clear()`。
public protocol UploadTargetStore: Sendable {

    /// 上次用的目标；从未记过则为 `nil`。
    func target() async -> UploadTarget?

    /// 记下这次用的目标（用户改了目标、或上传成功时写）。
    func remember(_ target: UploadTarget) async

    /// 清空（登出）。
    func clear() async
}

/// 内存实现 —— 单测与预览用；App 层用落盘实现。
public actor InMemoryUploadTargetStore: UploadTargetStore {

    private var storage: UploadTarget?

    /// - Parameter seed: 预置记忆（测试与预览用）。
    public init(seed: UploadTarget? = nil) {
        self.storage = seed
    }

    public func target() async -> UploadTarget? {
        storage
    }

    public func remember(_ target: UploadTarget) async {
        storage = target
    }

    public func clear() async {
        storage = nil
    }
}

/// 目标回落时的**已知事实**（网络侧查出来的那几件）。
///
/// ## ⚠️ 为什么把「查得到没有」与「怎么回落」分开
///
/// 「仓库还在不在」「目录还在不在」「分支还在不在」是**网络事实**，
/// 而「失效了怎么办」是**产品口径**。把两者混在一个类型里，
/// 网络那一层就得知道产品口径（数据层不得引用领域层的规则，反过来也一样）。
/// 于是这里只带事实，口径全在 `UploadTargetResolver`。
public struct UploadTargetFacts: Sendable, Equatable {

    /// 那个仓库还在不在（改名 / 删库 ⇒ `false`）。
    public var repositoryExists: Bool

    /// 那个目录还在不在（被删 ⇒ `false`）。
    public var directoryExists: Bool

    /// 那条分支还在不在（被删 ⇒ `false`）。
    public var branchExists: Bool

    /// 该仓库当前的默认分支（回落时用它）。
    public var defaultBranch: String

    public init(
        repositoryExists: Bool,
        directoryExists: Bool,
        branchExists: Bool,
        defaultBranch: String
    ) {
        self.repositoryExists = repositoryExists
        self.directoryExists = directoryExists
        self.branchExists = branchExists
        self.defaultBranch = defaultBranch
    }
}

/// 上传目标的**回落规则**（纯函数 —— 铁律 #14：判据写进领域层，不写进 ViewModel）。
///
/// ## 规则（2026-10-23 定的口径）
///
/// 1. **上下文优先**：用户正站在某个仓库 / 目录里时，默认目标 = 当前仓库 + 当前目录，
///    **不拿记忆**。（全局入口 + 记忆默认 ⇒ 站在 A 仓库却传到 B 仓库是真实会发生的误传。）
/// 2. **仓库没了 ⇒ 回落成"还没选"**（`nil`）：不猜、不静默换一个仓库 ——
///    猜出来的目标比没有目标更危险。
/// 3. **目录没了 ⇒ 落到仓库根**。
/// 4. **分支没了 ⇒ 落到默认分支**。
/// 5. 回落**一律静默**：不提示、不报错（用户看到的是一个仍然能用的目标，
///    而不是一条看不懂的警告）。
public enum UploadTargetResolver {

    /// 按上面五条规则解出本次该用的目标；`nil` = 还没选目标。
    public static func resolve(
        remembered: UploadTarget?,
        context: UploadTarget?,
        facts: UploadTargetFacts
    ) -> UploadTarget? {
        // ① 上下文优先
        if let context {
            return context
        }
        guard let remembered else { return nil }

        // ② 仓库没了 ⇒ 当作没选
        guard facts.repositoryExists else { return nil }

        // ③④ 目录 / 分支各自回落
        return UploadTarget(
            fullName: remembered.fullName,
            directory: facts.directoryExists ? remembered.directory : .root,
            branch: facts.branchExists ? remembered.branch : facts.defaultBranch
        )
    }
}

/// 上传成功后**复制出去**的那串路径。
///
/// ## ⚠️ 它与 `RepoCopy.clipboardPath` **不是一回事**（2026-10-23 定）
///
/// 那边复制的是**仓库内路径**（`assets/photos`，根目录时才给仓库全名）——
/// 那是代码浏览页里"告诉别人我在哪个目录"。
/// 这边要的是**带仓库名**的：`owner/repo/assets/photos/x.jpg` ——
/// 贴到别的仓库的 README 里时，GitHub 按 `owner/repo/路径` 解析跨仓库图片，
/// 少了 owner 就显示不出来。
///
/// ⇒ 所以这里是**新函数**，不要去改旧的（改了会让代码浏览页复制出来的路径多出一截）。
public enum UploadTargetPath {

    /// 拼出要复制的那串路径：`owner/repo/目录/文件名`。
    ///
    /// - Parameters:
    ///   - fullName: 仓库全名（`owner/repo`）。
    ///   - directory: 仓库内目录（根目录给 `.root`）。
    ///   - fileName: 文件名（不含目录）。
    public static func displayPath(
        fullName: String,
        directory: RepoPath,
        fileName: String
    ) -> String {
        if directory.isRoot {
            return "\(fullName)/\(fileName)"
        }
        return "\(fullName)/\(directory.raw)/\(fileName)"
    }
}
