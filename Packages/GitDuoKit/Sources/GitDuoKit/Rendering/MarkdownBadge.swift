import Foundation

/// 一个 **shields.io 徽章**（2026-10-14 新增，走查第 **65** 条）。
///
/// ## 为什么它值得单独一档
///
/// README 开头那排"许可证 / 构建状态"徽章是 SVG，而 `UIImage` 画不了矢量图
/// （见 `MarkdownImageBytes`）⇒ 它们在我们这里只可能是占位块。
/// 但这一类图片有一个别处没有的性质：**它的全部内容都写在自己的地址里** ——
///
///     https://img.shields.io/badge/<label>-<message>-<color>
///
/// ⇒ 不需要取字节、不需要渲染引擎、**不需要网络**，解析地址就能把它画出来。
/// 这比"真渲染 SVG"那条路省三样东西：不打请求（省配额）、无延迟、离线也看得见。
///
/// ## ⚠️ 它只覆盖"静态徽章"
///
/// shields.io 的地址分两类：
///
/// | 形状 | 例 | 内容在哪 |
/// |---|---|---|
/// | **静态** `/badge/…` | `/badge/license-MIT-12a58a` | **地址里写着** ⇒ 解得出来 |
/// | **动态** 其它 | `/github/stars/x/y` | **服务端算的** ⇒ 地址里一个字都没有 |
///
/// 动态那一档（star 数 / 版本号 / CI 状态）解不出内容 —— **用户裁定用作者的
/// `alt` 兜底**画成中性灰标签（`isFromAddress == false`），而不是回落成占位块：
/// 一排徽章里混着"真徽章 + 灰条"两种东西，比统一画成标签更难看。
/// ⚠️ 代价如实说：那时显示的是一句**描述**（`GitHub stars`），不是真实星数。
/// `alt` 也是空的 ⇒ 整条返回 `nil`，调用方回落成一张普通的图。
///
/// ## ⚠️ 它与 GitHub 上那张 SVG 不是像素级复刻
///
/// 我们按 shields 的规则把**文字与颜色解出来**，再用本 App 的字体与间距重画
/// （宽度、字距、阴影都不同）。这是有意的：要的是"一眼看得出这是个什么徽章"，
/// 不是逐像素对齐 —— 后者要求真渲染引擎，那是另一种量级的代价。
///
/// ## 解析规则的三条依据（都不是猜的）
///
/// - **`--` 是字面 `-` 的转义**：`MIT OR Apache--2.0` 里那个 `--` 表示一个真横线，
///   而单个 `-` 是**分隔符**。少了这一条，`license-MIT OR Apache-2.0-12a58a`
///   会切成四段。
/// - **`_` 与 `%20` 都是空格**（`%20` 在 `URL.path` 上已经解开）。
/// - **色名表照 `badge-maker/lib/color.js`**（shields 的实际渲染库）抄，
///   连"别名指向哪个基础色"一起。⚠️ 不是从记忆里写的 —— 那张表有版本，
///   换版本时要去核对，别顺手改一个数字。
public struct MarkdownBadge: Equatable, Hashable, Sendable {

    /// 徽章的**外观档** —— 由地址上的 `?style=` 决定（没写就是 `flat`）。
    ///
    /// ⚠️ 只影响观感（高度 / 圆角 / 是否大写），**不影响内容**。
    public enum Style: Equatable, Hashable, Sendable {
        /// 默认：圆角胶囊。
        case flat
        /// 直角。
        case flatSquare
        /// 大号：**更高、文字全大写**（`?style=for-the-badge`）。
        case forTheBadge
        /// 带质感那一档（我们按默认画 —— 它的差别是渐变，本 App 不用渐变）。
        case plastic
        /// GitHub 社交观感那一档（同样按默认画）。
        case social
    }

    /// 左半段的文字（灰底那一块）。
    ///
    /// ⚠️ **可以为 `nil`** —— 那时整条只有一个彩色段（`badge/Join%20us%20on%20Discord-5865F2`
    /// 就是这种，Discord 徽章在 GitHub 上也没有灰色左半段）。
    public let label: String?

    /// 右半段的文字（彩色底那一块）。**恒非空**。
    public let message: String

    /// 右半段的底色。
    ///
    /// ⚠️ 为 `nil` 只出现在**动态徽章**上（地址里没有颜色信息）⇒ 用中性灰。
    /// 静态徽章恒有一个值 —— 作者没写时照 shields 的默认（`lightgrey`）。
    public let color: MarkdownBadgeColor?

    /// 左半段的底色。照 shields 默认是 `grey`（可被 `?labelColor=` 改）。
    public let labelColor: MarkdownBadgeColor

    /// 外观档（`?style=`）。
    public let style: Style

    /// 内容是从**地址里解出来的**（静态徽章）还是**拿 `alt` 兜的**（动态徽章）。
    ///
    /// ⚠️ 它决定了 `message` 是什么性质：`true` = 徽章真正要说的那两句话；
    /// `false` = 作者写的一句**描述**（比如 `GitHub stars`，而不是真实星数）。
    /// 视图层据此选中性色 —— 别让一句描述看起来像真数据。
    public let isFromAddress: Bool
}

// MARK: - 解析

extension MarkdownBadge {

    /// 这个地址上的徽章，SHIELDS 专有。
    ///
    /// - Returns: 解不出来（不是 shields.io / 路径为空 / 动态徽章且 `alt` 也空）时 `nil`
    ///   —— 调用方**回落成一张普通的图**（那条路有它自己的一整套占位块）。
    public static func parse(url: URL, alt: String) -> MarkdownBadge? {
        guard let host = url.host?.lowercased(), host == hostName else { return nil }

        let style = style(in: url)

        guard url.path.hasPrefix(badgePath) else {
            // 动态徽章：内容由服务端算（star 数 / 版本号 / CI 状态），地址里一个字都没有。
            let fallback = alt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fallback.isEmpty else { return nil }
            return MarkdownBadge(
                label: nil,
                message: fallback,
                color: nil,
                labelColor: .defaultLabel,
                style: style,
                isFromAddress: false
            )
        }

        let parts = segments(of: String(url.path.dropFirst(badgePath.count)))
        guard !parts.isEmpty else { return nil }

        // 颜色最后剥：末段"看起来像颜色"才是颜色，否则它是 message 的一部分。
        // ⚠️ **先剥路径末段、再让 `?color=` 覆盖** —— 顺序反过来（先看 query、
        //    query 有值就不剥末段）的话，`badge/foo-bar-green?color=blue` 会把
        //    `green` 留在 message 里，屏幕上变成「bar-green」。
        var trailing = parts
        var color: MarkdownBadgeColor?
        if let last = trailing.last, let named = MarkdownBadgeColor(parsing: last) {
            color = named
            trailing.removeLast()
        }
        color = query(in: url, named: "color").flatMap(MarkdownBadgeColor.init(parsing:)) ?? color
        guard !trailing.isEmpty else { return nil }

        // ⚠️ **只剩一段时它就是 message、label 为空** —— 不是"label 与 message 同值"。
        //    真实例子：`badge/Join%20us%20on%20Discord-5865F2`（剥掉颜色后只剩一段），
        //    GitHub 上那枚 Discord 徽章也**没有**灰色左半段。写成同值的话屏幕上
        //    会出现两段一模一样的文字，而那看起来像作者写错了。
        let label = trailing.count >= 2 ? stripped(trailing[0]) : nil
        let message = trailing.count >= 2
            ? trailing.dropFirst().joined(separator: "-")
            : trailing[0]
        guard !message.isEmpty else { return nil }

        return MarkdownBadge(
            label: label,
            message: message,
            // 静态徽章总有颜色 —— 作者没写时照 shields 的默认（`lightgrey`）。
            color: color ?? MarkdownBadgeColor(parsing: "lightgrey"),
            labelColor: query(in: url, named: "labelColor").flatMap(MarkdownBadgeColor.init(parsing:))
                ?? .defaultLabel,
            style: style,
            isFromAddress: true
        )
    }

    /// `/badge/` 之后的正文按 shields 的规则切段。
    ///
    /// ⚠️ 顺序不能换：**先把 `--` 换成占位符，再按 `-` 切，最后把占位符换回来**。
    /// 反过来的话 `Apache--2.0` 已经被切成两段了，再换也没有意义。
    /// 占位符取 `\u{1}`：控制字符不可能出现在 URL 路径里。
    private static func segments(of body: String) -> [String] {
        var text = body
        if let dot = text.lastIndex(of: "."), text[text.index(after: dot)...].lowercased() == "svg" {
            text = String(text[..<dot])
        }

        let escaped = "\u{1}"
        return text
            .replacingOccurrences(of: "--", with: escaped)
            .components(separatedBy: "-")
            .map {
                $0.replacingOccurrences(of: escaped, with: "-")
                    .replacingOccurrences(of: "_", with: " ")
                    .trimmingCharacters(in: .whitespaces)
            }
    }

    /// 空串一律化成 `nil` —— `badge/-bar-green`（作者没写 label）切出来的第一段是空串，
    /// 那时该是"没有左半段"，而不是"左半段是一块空白"。
    private static func stripped(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        return text
    }

    private static func style(in url: URL) -> Style {
        switch query(in: url, named: "style")?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "flat-square": .flatSquare
        case "for-the-badge": .forTheBadge
        case "plastic": .plastic
        case "social": .social
        default: .flat
        }
    }

    /// 取一个 query 参数 —— **名字大小写不敏感**（shields 写的是 `labelColor` 这种驼峰，
    /// 而作者手写时经常拼成 `labelcolor`）。
    private static func query(in url: URL, named name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.lowercased() == name.lowercased() }?
            .value
    }

    /// shields.io 的 host。⚠️ 只认这一个 —— 别的徽章服务（`badgen.net` 等）
    /// 地址规则不同，混进来的话**解析出来的内容是错的**（比不解析更糟）。
    private static let hostName = "img.shields.io"

    private static let badgePath = "/badge/"
}

// MARK: - 颜色

/// 徽章底色（一个不依赖任何 UI 框架的 RGB 值）。
///
/// ## ⚠️ 领域层不认识 `Color`
///
/// `GitDuoKit` **不得 import SwiftUI**（`AGENTS.md §1` 依赖铁律）⇒ 这里只出
/// `0…1` 的三个分量，由视图层拼成 `Color`。同 `MarkdownBlock` 出结构、
/// `MarkdownBody` 出画法的分法。
public struct MarkdownBadgeColor: Equatable, Hashable, Sendable {

    public let red: Double
    public let green: Double
    public let blue: Double

    /// 直接给三个分量（各 `0…1`）。
    ///
    /// ⚠️ 必须显式写出来：本结构体自己声明了 `init?(parsing:)` ⇒ Swift 不再合成
    /// 逐一成员构造器（那个规则是"只要在**类型体内**声明了任何 init，
    /// memberwise init 就不再合成"）。
    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// 这个底色上该配**深色**字还是白字。
    ///
    /// ## ⚠️ 阈值 0.69 照 shields 自己那份实现
    ///
    /// 加权亮度 `0.299r + 0.587g + 0.114b` 超过 0.69 ⇒ 用深字
    /// （`#d8b800` 那个"黄"正好压在临界附近，shields 上它也是白字）。
    /// 不引相对亮度那套（要对分量做伽马变换）—— 这里只求"跟 shields 一致"。
    public var prefersDarkText: Bool {
        0.299 * red + 0.587 * green + 0.114 * blue > 0.69
    }

    /// 认两种写法：**3 / 6 位 hex**（可带 `#`）与**色名**。
    ///
    /// ⚠️ `#` 可带可不带、**只收 3 位与 6 位** —— 这不是宽容度问题，
    /// 而是 shields 的 `isHexColor` 正则就是这么写的（`^([\da-f]{3}){1,2}$`）。
    /// 放宽到 4 / 8 位的话，`badge/foo-bar-1234` 里那个 `1234` 会被当成颜色，
    /// 而 shields 认为它是 message 的一部分。
    public init?(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        // ⚠️ 位数**只收 3 与 6** —— 这不是宽容度问题，而是 shields 的
        //    `isHexColor` 正则就是这么写的（`^([\da-f]{3}){1,2}$`）。
        //    放宽到 4 / 8 位的话，`badge/foo-bar-1234` 里那个 `1234` 会被当成颜色，
        //    而 shields 认为它是 message 的一部分。
        guard (digits.count == 3 || digits.count == 6), digits.allSatisfy(\.isHexDigit) else {
            guard let named = Self.names[trimmed] else { return nil }
            self = named
            return
        }

        self = MarkdownBadgeColor(hex: digits)
    }

    /// 直接给 hex（**不走色名表**）—— 3 位写法按"每一位重复一次"展开
    /// （shields 的 `brightgreen` 写的就是 `#4b0` ⇒ `#44bb00`）。
    ///
    /// ⚠️ 它与 `init?(parsing:)` **必须分开**：色名表 `names` 自己就是用
    /// 这个 init 建的，若表里的项改调 `init?(parsing:)`，那一句会在
    /// 建表过程中回头读 `names` ⇒ 静态初始化自引用（运行时直接崩，
    /// 而崩的位置看起来与"颜色"毫无关系）。
    private init(hex: String) {
        let full = hex.count == 3 ? hex.map { "\($0)\($0)" }.joined() : hex
        let value = UInt32(full, radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// 左半段的默认底色。**照 shields 的默认 `grey`**（`#555`）。
    public static let defaultLabel = MarkdownBadgeColor(hex: "555")

    /// **动态徽章**（地址里没有任何颜色）用的中性底色。
    ///
    /// ⚠️ 取 shields 的默认 `lightgrey`，但**理由不是"跟 shields 一致"** ——
    /// 那种地址 shields 根本不画。取浅灰是为了**别让一句描述看起来像真数据**：
    /// 彩色底会被读成"这是一个结论"，浅灰底读成"这里本来有个东西"。
    public static let neutral = MarkdownBadgeColor(hex: "939393")

    /// shields 的色名表 —— **照 `badge-maker/lib/color.js` 抄**（含别名指向）。
    ///
    /// ⚠️ 这张表**有版本**。核对方式是看那个文件的 `namedColors` 与
    /// `resolvedAliases` 两个对象，别凭印象改数字。
    /// ⚠️ 表里没有的色名 ⇒ `init(parsing:)` 返回 `nil` ⇒ 那一段**不算颜色**、
    /// 会被当 message 的一部分。**这是有意的**：宁可显示成文字，也别猜一个色。
    private static let names: [String: MarkdownBadgeColor] = [
        "brightgreen": MarkdownBadgeColor(hex: "4b0"),
        "green": MarkdownBadgeColor(hex: "67ac09"),
        "yellow": MarkdownBadgeColor(hex: "d8b800"),
        "yellowgreen": MarkdownBadgeColor(hex: "95991a"),
        "orange": MarkdownBadgeColor(hex: "ea7233"),
        "red": MarkdownBadgeColor(hex: "dd4343"),
        "blue": MarkdownBadgeColor(hex: "007ec6"),
        "grey": MarkdownBadgeColor(hex: "555"),
        "gray": MarkdownBadgeColor(hex: "555"),
        "lightgrey": MarkdownBadgeColor(hex: "939393"),
        "lightgray": MarkdownBadgeColor(hex: "939393"),
        "success": MarkdownBadgeColor(hex: "4b0"),
        "important": MarkdownBadgeColor(hex: "ea7233"),
        "critical": MarkdownBadgeColor(hex: "dd4343"),
        "informational": MarkdownBadgeColor(hex: "007ec6"),
        "inactive": MarkdownBadgeColor(hex: "939393"),
    ]
}
