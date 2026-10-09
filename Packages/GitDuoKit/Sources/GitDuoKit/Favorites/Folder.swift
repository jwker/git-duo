import Foundation

/// 一个收藏夹（TECH_SPEC §9.12、PRD §4.19）。
///
/// ## ⚠️ 它是本 App **唯一的纯本地业务对象**
///
/// 收藏夹是 GitDuo 自己的概念，**GitHub 没有对应资源** —— 连读接口都没有
/// （对照：置顶仓库有只读接口、没有写接口，§4.6.1）。所以它的数据既不在服务端、
/// 也没有任何"以服务端为准"的对账机会 ⇒ **本机那份就是唯一真相**，
/// 这也正是它必须被单测钉死的原因（App target 没有测试 target，见决策 #34）。
///
/// ## ⚠️ `isDefault` 是**算出来的**，不是一个可以随便传的开关
///
/// 它等于 `name == FolderDefaults.name`。理由不是洁癖，而是：
/// **默认夹是靠名字标识的** —— 归属映射（`favMap`）的"值"存的就是夹名，
/// 而"新收藏总有着落"这条语义要求有一个**恒定的落点名字**（`TECH_SPEC §9.12`）。
///
/// 如果把它做成一个**存储字段**，下面两种坏状态都能构造出来，
/// 而且都**不会报错**：
/// ① 一个叫「默认收藏夹」但 `isDefault == false` 的夹 —— 新收藏掉进一个
///    界面上没有「默认」标记的夹里；
/// ② 一个不叫「默认收藏夹」却 `isDefault == true` 的夹 —— 那个「默认」标记
///    指向一个**可以被删掉**的夹，删完就没有落点了。
///
/// 做成计算属性之后，这两种状态**在类型上就不存在**；顺带还解决了一个更隐蔽的问题：
/// `Codable` 的合成实现会**绕过自定义 `init`** 直接写存储属性，
/// 所以"存下来的 `isDefault` 与名字脱钩"这种脏数据本来能一路读到界面上。
/// 现在磁盘上只有 `name` 一个字段，脱钩无从谈起。
///
/// 那为什么不让界面自己比字符串？——因为界面需要判断"这一行要不要画「默认」标记、
/// 要不要给动作"，让它去比一个常量字符串，等于把领域规则散进视图（`AGENTS.md §5`）。
public struct Folder: Sendable, Hashable, Identifiable, Codable {

    /// 收藏夹名。**唯一**（同一个名字只能有一个夹），也是所有归属关系的"值"。
    public let name: String

    /// 是不是内置的「默认收藏夹」。见类型说明：它由 `name` 决定。
    public var isDefault: Bool { name == FolderDefaults.name }

    /// `ForEach` 的键。
    ///
    /// ⚠️ **用名字当身份，不用 UUID**（同 `AuthorDTO` 不带 `id` 的判据）：
    /// 映射里存的值就是名字，再造一个 UUID 身份必然出现"两个身份谁说了算"。
    /// 代价很具体且可接受：**重命名会改变这一行的 `id`**，于是 `ForEach` 把它当成
    /// "删一行 + 插一行"（视觉上该行会被重建）—— 而这恰好与事实相符
    /// （它确实换了个名字），比"沿用同一个身份、只改字"更不容易骗到动画与 diff。
    public var id: String { name }

    public init(name: String) {
        self.name = name
    }
}

/// 收藏夹相关的**固定值**。
public enum FolderDefaults {

    /// 内置默认收藏夹的名字（原型 `11-favorites.js` 的 `DEFAULT_FOLDER` 逐字）。
    ///
    /// ⚠️ 它同时是**新收藏的落点**与**删除收藏夹时那些条目的回落处**，
    /// 所以这个名字会大量出现在归属映射的"值"里 —— 改它等于把已有数据全部指向虚空
    /// （而且不会有任何报错）。真要改，得同时写一次数据迁移。
    public static let name = "默认收藏夹"
}

/// 一个收藏夹 + 它的**派生**项目数 —— 「我的收藏」页与「选择收藏列表」弹层渲染用的形状。
///
/// ## 为什么要有这个类型（而不是让调用方各取 `Folder` 与 `count` 再自己拼）
///
/// 因为"某个夹有几项"在展示侧**必须与夹同行出现**（原型那两处都是
/// `${f.n} … ${favTotal(f.n)} 项`）。两处调用点各自 `await` 两次再拼，
/// 就有机会拼出"名称是新的、数量还是旧的"这种半截状态；一次 `await` 拿回一个
/// 已经配套的快照，这种中间态在类型上就不存在。
///
/// ⚠️ `itemCount` **永远是算出来的**（归属映射中值等于该夹名的条目数），
/// **不是存下来的**。这条纪律在原型上踩过一次：第一版用独立计数器，
/// 于是"删除收藏夹时把里面的项搬去默认夹"这一步会让默认夹那一格**纹丝不动**
/// （见 `TECH_SPEC §9.12`）。
public struct FolderSummary: Sendable, Hashable, Identifiable {

    public let folder: Folder

    /// 项目数 —— 归属在这个夹里的仓库数。
    public let itemCount: Int

    public var id: String { folder.name }

    public var name: String { folder.name }

    public var isDefault: Bool { folder.isDefault }

    public init(folder: Folder, itemCount: Int) {
        self.folder = folder
        self.itemCount = itemCount
    }
}
