import Foundation

/// 占比条上的一段（TECH_SPEC §9.11 / 决策 #42）。
///
/// - `language == nil` 表示**「其他」段**（把落在具名语言之外的字节合并而成）。
///   它不是一个语言，所以**没有语言色** —— 呈现层给它中性灰（`Theme.Palette.shareNeutral`）。
public struct LanguageShare: Sendable, Hashable, Identifiable {

    /// 语言名；`nil` = 「其他」段。
    public let language: String?

    /// 该段的原始字节数（来自 `GET /repos/{o}/{r}/languages`）。
    public let bytes: Int

    /// 整数百分比。**所有段的 `percent` 之和恒为 100**（见 `LanguageComposition.shares(from:)`）。
    public let percent: Int

    public init(language: String?, bytes: Int, percent: Int) {
        self.language = language
        self.bytes = bytes
        self.percent = percent
    }

    /// `ForEach` 的稳定标识。
    ///
    /// ⚠️ **不直接用 `label`**：理论上存在名叫「其他」的语言（或将来改文案时撞名），
    /// 那样两段会拿到同一个 `id`，SwiftUI 会静默渲染错乱。加前缀把两个命名空间分开。
    public var id: String { language.map { "lang:\($0)" } ?? "other" }

    /// 图例上的名称。
    public var label: String { language ?? LanguageComposition.otherLabel }

    /// 图例上的百分比，如 `72%`。
    public var percentLabel: String { "\(percent)%" }
}

/// `GET …/languages` 的 `{语言: 字节数}` → 占比条要的若干段（TECH_SPEC §9.11）。
///
/// ## 为什么这个换算在本地做
///
/// GitHub 的 `/languages` 只给**字节数**、不给百分比，且响应是一个 **JSON 对象** ⇒
/// `Dictionary` 的迭代顺序不确定。若不排序，同一次响应的两次解析可能得到
/// **两根顺序不同的占比条**；而排序 + 换算都在本地做，就能被单测钉死。
///
/// ## 分段口径（决策 #42，用户 2026-10-06 拍板）
///
/// 按字节数降序取 **前 2 个语言**，其余全部合并为 **「其他」** ⇒ **最多 3 段**。
/// 段数由 `maxNamedLanguages` 一个常量决定，改口径只需改这一处。
///
/// ## 为什么各段百分比之和必须恰为 100
///
/// 三段各自四舍五入会得到 `33 / 33 / 33 = 99` 或 `67 / 33 / 33 = 133` ——
/// 而"占比加起来不是 100%"是用户**一眼就能看出来**的错，且会让人怀疑整个页面。
/// 故用**最大余数法**：先取下整，再把差出来的那几个百分点补给小数部分最大者。
///
/// ## 为什么它放在 `GitDuoCore` 而不是 `GitDuoKit`
///
/// 因为**唯一的消费方是设计包里的 `LanguageBar`**，而依赖铁律规定
/// `GitDuoDesign → GitDuoCore`、**`GitDuoDesign` 不得依赖 `GitDuoKit`**（§3）。
/// 把它放领域层，设计包就取不到，只能由每个调用点各转一次
/// —— 而那正是"同一件事有两处实现"的开端。它与 `CompactNumber` / `RelativeTime`
/// 同属"把服务端数据翻成给人看的形式"，落在同一目录也是这个道理。
public enum LanguageComposition {

    /// 「其他」段的名称。**也被原型的图例逐字用到**（`scripts/10-explore-repo.js`）。
    public static let otherLabel = "其他"

    /// 「其他」之前最多保留几个具名语言（决策 #42 = 2，合计最多 3 段）。
    public static let maxNamedLanguages = 2

    /// 把字节数换算成占比条的各段。
    ///
    /// - Parameter byteCounts: `{"Swift": 12345, "Shell": 2345}`。
    /// - Returns: 按占比从大到小排列的段；**空输入返回空数组**
    ///   （调用方据此渲染空态，而不是一根全灰的条 —— 见 PRD §4.13）。
    public static func shares(from byteCounts: [String: Int]) -> [LanguageShare] {

        // ① 清洗：丢掉空名字与非正字节数。
        //    `bytes > 0` 而不是 `>= 0`：零字节的条目在饼里占不到宽度，
        //    却会在图例里多出一行 `Foo 0%` —— 纯噪声。
        let cleaned: [(name: String, bytes: Int)] = byteCounts.compactMap { name, bytes in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, bytes > 0 else { return nil }
            return (trimmed, bytes)
        }
        guard !cleaned.isEmpty else { return [] }

        // ② 确定性排序：字节降序；**字节相同时按名字升序**。
        //    少了后半句，同字节的两个语言会随字典哈希顺序抖动 ⇒ 占比条两次渲染颜色互换。
        let ranked = cleaned.sorted { lhs, rhs in
            lhs.bytes == rhs.bytes ? lhs.name < rhs.name : lhs.bytes > rhs.bytes
        }

        // ③ 切分：前 N 个具名，其余合并成「其他」。
        var buckets: [(language: String?, bytes: Int)] = ranked
            .prefix(maxNamedLanguages)
            .map { (Optional($0.name), $0.bytes) }

        let othersBytes = ranked.dropFirst(maxNamedLanguages).reduce(0) { $0 + $1.bytes }
        // 只有"确实还有剩下的"才追加「其他」。
        // 一个只有两种语言的仓库应当显示两个语言名，而不是 `Swift / 其他`。
        if othersBytes > 0 { buckets.append((nil, othersBytes)) }

        let total = buckets.reduce(0) { $0 + $1.bytes }
        guard total > 0 else { return [] }

        let percents = wholePercents(bytes: buckets.map(\.bytes), total: total)
        return zip(buckets, percents).map { bucket, percent in
            LanguageShare(language: bucket.language, bytes: bucket.bytes, percent: percent)
        }
    }

    /// 最大余数法：整数百分比，且**和恰为 100**。
    ///
    /// 下界是安全的：各段 `floor` 之和不可能超过 100，故 `deficit ∈ [0, 段数)`。
    private static func wholePercents(bytes: [Int], total: Int) -> [Int] {
        let exact = bytes.map { Double($0) * 100 / Double(total) }
        var whole = exact.map { Int($0.rounded(.down)) }

        let deficit = 100 - whole.reduce(0, +)
        guard deficit > 0 else { return whole }

        // 余数大的先补；平手时按原序（已是字节降序）——
        // `sorted(by:)` 不保证稳定，靠下标裁决才能让同一输入永远得到同一输出。
        let order = exact.indices.sorted { lhs, rhs in
            let left = exact[lhs] - Double(whole[lhs])
            let right = exact[rhs] - Double(whole[rhs])
            return left == right ? lhs < rhs : left > right
        }
        for index in order.prefix(deficit) { whole[index] += 1 }
        return whole
    }
}
