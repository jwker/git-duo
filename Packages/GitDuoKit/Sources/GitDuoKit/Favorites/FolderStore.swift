import Foundation

// MARK: - 三种变更的结果

/// 「把某个仓库放进某个收藏夹」的结果（TECH_SPEC §9.12 的归属表第 1、2 行）。
///
/// ## 为什么用类型而不是 `Bool`
///
/// 三种情形**在界面上要说不同的话**，而且其中一种是"什么都没发生"：
/// 已经在目标夹里再点一次（`unchanged`）说"已收藏到「X」"是对的，说"已移动"就是编的；
/// 目标夹不存在（`unknownFolder`）则是一次**本不该发生**的调用（界面只从现有列表里选），
/// 静默吞掉它会让那个仓库变成"显示已收藏、却在任何一个夹里都找不到"。
/// 用 `Bool` 表达不了这三种，调用方就只能靠猜。
public enum FolderMoveOutcome: Sendable, Equatable {

    /// 已经改好了。
    ///
    /// - Parameters:
    ///   - previous: 原先在哪个夹；`nil` = 这是**首次收藏**（§9.12 归属表第 1 行）。
    ///   - current: 现在在哪个夹。
    case moved(previous: String?, current: String)

    /// 本来就在这个夹里 ⇒ **一个字节都没改**。
    case unchanged(folder: String)

    /// 目标收藏夹不存在。**没有改任何东西**。
    case unknownFolder(String)
}

/// 「新建收藏夹」的结果。
public enum FolderCreationOutcome: Sendable, Equatable {

    case created(name: String)

    /// 同名夹已经存在。**没有创建**。
    ///
    /// ⚠️ 两个入口对它的处置**有意不同**（`TECH_SPEC §9.12`）：
    /// 管理页入口**只提示不创建**；仓库详情入口**提示并自动选中**（照样把仓库放进去）。
    /// 所以这里只回事实，说什么话由 `FolderCopy` 的两个常量分工 ——
    /// 把两句话合成一句（比如统一成"已存在，已为你选中"）会让管理页那一处
    /// 悄悄改变行为（用户以为建了一个新夹，其实没有）。
    case duplicate(name: String)

    /// 名字为空（或全是空白）。
    case emptyName
}

/// 「重命名收藏夹」的结果。
public enum FolderRenameOutcome: Sendable, Equatable {

    case renamed(from: String, to: String)

    /// 新名字与原名相同 ⇒ **直接关闭弹层、不给任何提示**（PRD §5.13 逐字）。
    ///
    /// 这一条单列出来是有原因的：它不是失败，是"用户按了保存但等于没改"。
    /// 如果把它并进 `renamed`，界面会说一句"已重命名为「X」"—— 对着一个没变过的名字
    /// 报一次成功，用户下一次就会怀疑别的提示也是假的。
    case unchanged(name: String)

    case emptyName

    /// 与**其它**收藏夹重名（与自己同名不算，那种情况是 `unchanged`）。
    case duplicate(name: String)

    /// 这个夹已经不在了（另一个入口刚删了它）。
    case notFound(name: String)

    /// 「默认收藏夹」不可重命名。
    ///
    /// ⚠️ 界面**不会**走到这里（那一行不给入口），它是逻辑层的第二道拦截
    /// （`TECH_SPEC §9.12`：「UI 不给入口 + 逻辑层二次拦截」）。
    /// PRD §4.19 页脚那行说明逐字写着「不可**重命名**或删除」——
    /// 所以重命名这一侧也要拦，不能只拦删除。
    case protectedDefault
}

/// 「删除收藏夹」的结果。
public enum FolderDeletionOutcome: Sendable, Equatable {

    /// 删掉了。`moved` = 有多少条收藏回落到默认夹
    /// （= 删之前这个夹的项目数，PRD §5.14 的提示文案要用它）。
    case deleted(name: String, moved: Int)

    /// 「默认收藏夹」不可删除（PRD §5.14：不会进入确认弹层，直接提示）。
    case protectedDefault

    case notFound(name: String)
}

/// 「新建收藏夹并收藏」（仓库详情那个入口）的结果。
///
/// ## 它与 `FolderCreationOutcome` 的区别就是两个入口的区别
///
/// 这个类型多出来的信息是"顺带收藏了没有"。两个入口的**有意不同**在这里成为类型差异：
/// 管理页入口根本没有这个返回值可选（它只有 `FolderCreationOutcome`），
/// 所以"管理页入口也把仓库收进去了"这种串味在类型上就不成立。
public enum FavoriteCreationOutcome: Sendable, Equatable {

    /// 新建了夹，并把仓库放了进去。
    case created(name: String)

    /// 同名夹已经存在 ⇒ 提示一句"已存在，已为你选中"，**照样把仓库放进去**
    /// （PRD §5.6：`重名 → 提示已存在并自动选中`）。
    case reused(name: String)

    case emptyName
}

// MARK: - 存储协议

/// 收藏夹与收藏归属的存储（TECH_SPEC §9.12、PRD §4.19）。
///
/// ## 单一数据源：`favMap`
///
/// 内部只有两样东西 —— **收藏夹列表**与**归属映射**（仓库全名 → 夹名）。
/// 项目数、某个仓库属于哪个夹、"这个夹空不空"，**全部从映射现算**。
/// 本协议因此**不提供任何"加一 / 减一"的入口**：`TECH_SPEC §9.12` 的原话是
/// 「不存在"手工 +1/−1"的调用点」—— 独立计数器在"换夹 / 取消 / 删夹回落"
/// 三种情况下必然漏减，而漏减不会报错（原型第一版即踩此坑）。
///
/// ## ⚠️ 它是**账号绑定数据**：`signOut()` 必须 `clear()`
///
/// 收藏夹里有用户自己起的名字（"以后再看"、"给老板看的"），
/// 留着它换个账号登进来还能读到，是一次真实的泄露（`TECH_SPEC §3.6` 第 ③ 步）。
///
/// ## ⚠️ 与前几个 store 一样，**落盘实现在 App 组合根**，不在本包
///
/// 本包只定义"该是什么行为"（外加一份内存参照实现供测试与预览）。
/// 理由见 `RecentVisitStore` 的类型说明。
///
/// ## ⚠️ 整个 App 只能有**一个实例**
///
/// 「我的收藏」管理页与仓库详情页的「选择收藏列表」弹层读的是**同一份数据**
/// （`TECH_SPEC §9.12` 末段：靠 `@Observable` 发布变更让两边自动刷新）。
/// 两个页面各建一份的表现是"在一边建了夹、另一边看不见"，
/// 而两边看起来都正常 —— 同 `branchMemory` 那条先例。
public protocol FolderStore: Sendable {

    /// 内置默认收藏夹的名字（`FolderDefaults.name` 的转发，免得调用方多 import 一层概念）。
    static var defaultFolderName: String { get }

    /// 全部收藏夹 + 各自的项目数，**顺序即展示顺序**（默认夹恒在第一位）。
    func summaries() async -> [FolderSummary]

    /// 全部收藏夹名，**顺序同上**。
    ///
    /// 与 `summaries()` 并存是因为「选择收藏列表」弹层要画一份**带勾选态**的列表，
    /// 它的勾选态来自"当前仓库的归属"，而与项目数无关 ——
    /// 拿一份不含项目数的清单，那一处就不必被动地跟着计数变化重绘。
    func folderNames() async -> [String]

    /// 这个仓库现在属于哪个收藏夹；`nil` = 没收藏过。
    func folder(ofRepo fullName: String) async -> String?

    /// 某个收藏夹的项目数（派生值）。
    func count(in folderName: String) async -> Int

    /// 收藏 / 换夹。**只改归属，计数自动跟随**（§9.12 归属表第 1、2 行）。
    ///
    /// - Returns: 见 `FolderMoveOutcome` —— 注意首藏与换夹是**同一个动作**
    ///   （原型 `favSet` 也只有一条路径），区别只在返回值里的 `previous` 是不是 `nil`。
    func move(repo fullName: String, to folderName: String) async -> FolderMoveOutcome

    /// 取消收藏（§9.12 归属表第 3 行：只删归属，所属夹自动 −1）。
    ///
    /// - Returns: 原来是否收藏过。`false` = 它本来就没收藏，**什么都没发生**
    ///   （不是错误 —— 但调用方据此不该说"已从收藏移除"）。
    @discardableResult
    func remove(repo fullName: String) async -> Bool

    /// 新建收藏夹（管理页入口）。**不改变任何仓库的收藏状态**（PRD §4.19）。
    func create(name rawName: String) async -> FolderCreationOutcome

    /// 重命名收藏夹。**项目数不变**（§9.12 归属表第 5 行）——
    /// 实现必须把映射里的"值"一起改掉，否则那批收藏会指向一个不存在的夹。
    func rename(from oldName: String, to rawName: String) async -> FolderRenameOutcome

    /// 删除收藏夹。其中的收藏**先回落到默认夹、再删夹**（§9.12 归属表第 6 行），
    /// 不留"收藏到一个已不存在的列表"的悬空归属。
    func delete(name rawName: String) async -> FolderDeletionOutcome

    /// 清空全部（登出时随其余账号数据一并清理，§3.6 ③）。
    ///
    /// 清空之后**默认收藏夹要回来**（它不是一个用户数据，而是"新收藏总有着落"这条语义的载体）。
    func clear() async
}

extension FolderStore {

    public static var defaultFolderName: String { FolderDefaults.name }

    /// **仓库详情入口**的"创建并收藏"（PRD §5.6 前半）。
    ///
    /// ## 它为什么是协议扩展里的默认实现
    ///
    /// 因为两个入口"用同一份校验、但重名处置不同"这件事**必须只有一处实现**：
    /// 如果让每个实现自己写一遍，早晚会有一处把重名当成失败、
    /// 或者忘了在重名时照样把仓库放进去 —— 而这两处的差别在界面上只差一句提示，
    /// 评审时极难发现（`TECH_SPEC §9.12` 把这条写成"有意不同"，正是因为它太容易被抹平）。
    ///
    /// 于是分工是：**校验与"建 + 放"这套动作**在这里（一份），
    /// **说哪句话**由 `FolderCopy` 的两个常量分工（仓库入口用 `duplicateInRepository`）。
    public func createAndFavorite(
        name rawName: String,
        repo fullName: String
    ) async -> FavoriteCreationOutcome {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyName }

        switch await create(name: trimmed) {
        case let .created(name):
            _ = await move(repo: fullName, to: name)
            return .created(name: name)

        case let .duplicate(name):
            // ⚠️ 重名**不是失败**：照样把仓库放进那个已存在的夹里（PRD §5.6）。
            //    与上面的 `.created` 分支只差返回值 —— 而那个差别正是两句话的差别。
            _ = await move(repo: fullName, to: name)
            return .reused(name: name)

        case .emptyName:
            // 上面已经 trim 过一次，理论上到不了这里（`create` 自己也 trim）。
            // 保留分支是为了不靠"两处 trim 的实现一致"来保证正确。
            return .emptyName
        }
    }
}

// MARK: - 内存实现

/// 内存实现 —— 供单测与预览使用。
///
/// 落盘实现（`UserDefaults` + JSON）按 `RecentVisitStore` 的先例放在 App 组合根。
public actor InMemoryFolderStore: FolderStore {

    /// 收藏夹，**顺序即展示顺序**。默认夹恒在第一位（构造时归一化保证）。
    private var folders: [Folder]

    /// 归属映射 —— **单一数据源**。仓库全名 → 夹名。
    private var favorites: [String: String]

    /// - Parameters:
    ///   - seed: 预置收藏夹（测试与预览用）。通常只传自建的那几个 ——
    ///     默认夹由本初始化器补齐，传了也会去重。
    ///   - favorites: 预置归属（仓库全名 → 夹名）。
    ///
    /// ## 归一化：把三种"存坏了"的状态在入口处修好
    ///
    /// 与 `InMemorySearchHistoryStore.init(seed:)` 同一取向（"不假设有序、也不假设干净"），
    /// 但这里要修的是**不变量**，因为后面每条规则都建立在它们之上：
    ///
    /// 1. **默认夹一定存在、且一定在第一位** —— 否则"新收藏总有着落"当场不成立；
    /// 2. **同名夹只留一个**（保留先出现的那个）—— 否则"重名判定"会自相矛盾；
    /// 3. **归属指向的夹一定存在**，指向不存在的夹的条目**回落到默认夹** ——
    ///    这与"删除收藏夹时回落"是同一条规则（§9.12 归属表第 6 行），
    ///    在这里再兜一次是因为磁盘上的旧数据可能来自一个删了一半的版本。
    ///
    /// ⚠️ 为什么"回落"而不是"丢掉那条归属"：丢掉会让那个仓库**在界面上变成没收藏过**
    /// （用户看到的是一夜之间收藏少了几条），而回落至少保住了"它还被收藏着"这个事实。
    public init(seed: [Folder] = [], favorites: [String: String] = [:]) {
        var ordered: [Folder] = []
        var seen = Set<String>()

        for folder in seed {
            let name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            ordered.append(Folder(name: name))
        }

        // 默认夹：不在就补到最前，在就挪到最前（顺序是展示顺序，默认夹必须在首位）。
        if let index = ordered.firstIndex(where: \.isDefault) {
            ordered.insert(ordered.remove(at: index), at: 0)
        } else {
            ordered.insert(Folder(name: FolderDefaults.name), at: 0)
        }

        let known = Set(ordered.map(\.name))
        self.folders = ordered
        // 悬空归属一律回落到默认夹（见上面的第 3 条）。
        self.favorites = favorites.mapValues { known.contains($0) ? $0 : FolderDefaults.name }
    }

    // MARK: 读

    public func summaries() async -> [FolderSummary] {
        // 一次遍历算出全部计数，而不是每个夹扫一遍 `favorites`。
        // 写成"每个夹过滤一次"在四个夹时看不出差别，但它是 O(夹数 × 归属数)——
        // 而每次重绘都会走这里（管理页与弹层都在读它）。
        var counts: [String: Int] = [:]
        for folderName in favorites.values {
            counts[folderName, default: 0] += 1
        }
        return folders.map { FolderSummary(folder: $0, itemCount: counts[$0.name] ?? 0) }
    }

    public func folderNames() async -> [String] { folders.map(\.name) }

    public func folder(ofRepo fullName: String) async -> String? { favorites[fullName] }

    public func count(in folderName: String) async -> Int {
        favorites.values.count { $0 == folderName }
    }

    // MARK: 收藏 / 取消

    public func move(repo fullName: String, to folderName: String) async -> FolderMoveOutcome {
        guard folders.contains(where: { $0.name == folderName }) else {
            return .unknownFolder(folderName)
        }

        let previous = favorites[fullName]
        // 已在目标夹 ⇒ 一个字节都不改（原型 `favSet` 的第一句就是它）。
        // 不早返回的后果不是"多写一次"，而是返回值会告诉界面"移动成功了"，
        // 于是用户点已选中的那个夹会收到一句"已收藏到「X」"，听起来像换了个夹。
        if previous == folderName { return .unchanged(folder: folderName) }

        favorites[fullName] = folderName
        return .moved(previous: previous, current: folderName)
    }

    @discardableResult
    public func remove(repo fullName: String) async -> Bool {
        favorites.removeValue(forKey: fullName) != nil
    }

    // MARK: 收藏夹的增删改

    public func create(name rawName: String) async -> FolderCreationOutcome {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .emptyName }

        guard !folders.contains(where: { $0.name == name }) else {
            return .duplicate(name: name)
        }

        // 追加到末尾 —— 默认夹在首位、自建的按创建顺序排在后面（原型 `FOLDERS.push`）。
        folders.append(Folder(name: name))
        return .created(name: name)
    }

    public func rename(from oldName: String, to rawName: String) async -> FolderRenameOutcome {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .emptyName }

        guard let index = folders.firstIndex(where: { $0.name == oldName }) else {
            return .notFound(name: oldName)
        }
        // 默认夹不可重命名（PRD §4.19 页脚逐字：「不可重命名或删除」）。
        guard !folders[index].isDefault else { return .protectedDefault }

        // 与原名相同 ⇒ 直接关闭、不提示（PRD §5.13）。
        // ⚠️ 顺序很重要：**它必须排在同名检查之前**。反过来的话，
        //    "把夹名改成它自己"会撞上"已有同名收藏夹"—— 而序列里明明只有它自己一个。
        guard name != oldName else { return .unchanged(name: name) }

        // 与**其它**夹重名才拦（PRD §5.13 的"其它"两个字就是这一句）。
        guard !folders.contains(where: { $0.name == name }) else {
            return .duplicate(name: name)
        }

        folders[index] = Folder(name: name)

        // ⚠️⚠️ **映射的"值"必须跟着改名**（§9.12 归属表第 5 行）。
        //    漏掉这一句的表现是：项目数当场变成 0，但那批仓库仍显示"已收藏"
        //    （它们指向一个已经不存在的夹名）—— 而收藏夹列表里一个空夹都不多，
        //    所以只改一半时屏幕上看起来只是"收藏被清空了"。
        for repo in favorites.keys where favorites[repo] == oldName {
            favorites[repo] = name
        }

        return .renamed(from: oldName, to: name)
    }

    public func delete(name rawName: String) async -> FolderDeletionOutcome {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let index = folders.firstIndex(where: { $0.name == name }) else {
            return .notFound(name: name)
        }
        guard !folders[index].isDefault else { return .protectedDefault }

        // ⚠️ **先回落、再删夹**（§9.12 归属表第 6 行）。
        //    顺序反了的后果是"删夹之后那批仓库的归属指向一个不存在的夹名"——
        //    而因为计数是派生的，屏幕上表现为"项目数没变但那一行没了"，
        //    那批仓库仍显示已收藏、却不在任何一个夹里。
        let moved = favorites.values.count { $0 == name }
        for repo in favorites.keys where favorites[repo] == name {
            favorites[repo] = FolderDefaults.name
        }
        folders.remove(at: index)

        return .deleted(name: name, moved: moved)
    }

    public func clear() async {
        favorites = [:]
        folders = [Folder(name: FolderDefaults.name)]
    }
}

// MARK: - 落盘编解码

/// 收藏夹的落盘编解码（TECH_SPEC §7.1：**UserDefaults + JSON**）。
///
/// ## 为什么它也要放进领域层
///
/// 与 `SearchHistoryCoding` 同源：App target **没有测试 target**，而"存进去取不回来"
/// 是最安静的一类故障 —— 不报错、不崩溃，只是每次冷启动后「我的收藏」空着。
///
/// ## ⚠️ 它是一份**两段**数据，不是一列
///
/// 前面的 store（最近访问 / 搜索历史 / 草稿）都只有一列，这里**有两样东西**：
/// 收藏夹列表（**有序**，顺序就是展示顺序）与归属映射（无序）。
/// 两样都必须在**同一份负载**里：分两个键存的话，"建了夹但归属还没写"或反过来
/// 会成为一个真实可达的中间态，而它出现在磁盘上的样子是**默认夹之外多一个空夹**
/// 或**一条指向不存在夹的归属** —— 两者都要靠加载时归一化去猜。
public enum FolderCoding {

    /// 一次落盘的全部内容。
    public struct Payload: Sendable, Equatable, Codable {

        /// 收藏夹，**顺序即展示顺序**。
        public var folders: [Folder]

        /// 归属表，**已按仓库全名排序**。
        ///
        /// ⚠️ 排序不是洁癖：`Dictionary` 的迭代顺序**每次运行都可能不同**
        /// （同 `InMemoryStarSnapshotStore.allSnapshots` 的说明），
        /// 直接把字典写出去会让"同一份收藏两次落盘得到两个不同字节序列"。
        public var favorites: [Favorite]

        /// 一条归属。
        public struct Favorite: Sendable, Equatable, Codable {
            public let repo: String
            public let folder: String

            public init(repo: String, folder: String) {
                self.repo = repo
                self.folder = folder
            }
        }

        public init(folders: [Folder], favorites: [Favorite]) {
            self.folders = folders
            self.favorites = favorites
        }

        /// 从"两样东西"拼一份负载，顺带把归属排好序。
        public init(folders: [Folder], mapping: [String: String]) {
            self.init(
                folders: folders,
                favorites: mapping
                    .map { Favorite(repo: $0.key, folder: $0.value) }
                    .sorted { $0.repo < $1.repo }
            )
        }

        /// 归属表还原成字典（加载时用）。
        public var mapping: [String: String] {
            Dictionary(favorites.map { ($0.repo, $0.folder) }, uniquingKeysWith: { _, last in last })
        }
    }

    public static func encode(_ payload: Payload) -> Data? {
        try? JSONEncoder().encode(payload)
    }

    /// **解不出就返回 `nil`**，不抛错。
    ///
    /// 与 `SearchHistoryCoding.decode` 的差别在"解不出之后怎么办"：
    /// 那边返回空数组（一个空态），这边返回 `nil` 让调用方**回落成"只有默认夹"**——
    /// 而不是"零个收藏夹"。零个收藏夹是一个**不合法**的状态（没有落点），
    /// 让 `nil` 与"合法但空"在类型上分开，加载路径就不可能漏掉这一步。
    public static func decode(from data: Data) -> Payload? {
        try? JSONDecoder().decode(Payload.self, from: data)
    }
}
