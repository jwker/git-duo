import SwiftUI

/// 单个用户头像 —— 圆形首字母兜底（**主色描边 + 白底 + 主色字母**）。
///
/// ```css
/// .avatar{width:34px;height:34px;border-radius:50%;display:flex;align-items:center;
///         justify-content:center;font-weight:700;color:#fff;font-size:13px}
/// ```
///
/// ⚠️ 上面这段原型 CSS 只剩"34×34 圆"这一处还有效（`.rowDiameter`）——
/// 它的 `color:#fff`（白字 + 实底色）已作废，见下面「兜底圆」一节。
///
/// ## 四处消费场景，四个尺寸档
///
/// | 档 | 直径 | 出处 |
/// |---|---|---|
/// | `.navigationDiameter` | 36 | 首页右上角那颗（走查第 85 条加，第 86 条由 30 放大） |
/// | `.rowDiameter` | 34 | `.sr-item .avatar`（搜索结果行 / 贡献者） |
/// | `.sheetDiameter` | 52 | §5.10 用户资料弹层（原型 `openUserSheet` 的 52×52） |
/// | `.profileDiameter` | 86 | §4.17「我的」页头部（原型 `.profile-head .big-avatar`，切片 9 加） |
///
/// ## ⚠️ 首字母字号**不跟直径联动**，是三个各写各的值
///
/// 原型三处的字号是 13 / 19 / 30px（对直径 34 / 52 / 86）——
/// 比值分别是 0.382 / 0.365 / 0.349，**不是一个比例**，
/// 所以"按直径乘一个系数"复现不出这三处（写 0.36 会让 34 那一档从 13 变成 12.2）。
/// 于是这里**不推导**：由调用方用 `initialFont` 传。
///
/// ⚠️ `initialFont` 默认 `nil` = 用 `Theme.Font.label`（`.caption` 11pt semibold）
/// ⇒ **34 / 52 两档的既有观感一个像素都不变**。这两档与原型（13 / 19）本来就差着，
/// 那是切片 4 / 5 已验收的样子，本片**不去动它**。
/// 要一次性收口就改这一个默认值 —— 但那是另一次决定，别在加第三档的时候顺手做。
///
/// ## ⚠️ 兜底圆：2026-10-17 起是「主色描边 + 白底 + 主色字母」
///
/// 原来它是**每人一色的实底圆 + 白字**：色由登录名的 djb2 哈希从
/// `Theme.Palette.avatarFallback` 那 8 色里挑一个（GitHub 网页端的做法）。
/// 主色统一为橙之后，那 8 色成了**与主色打架的第二套彩虹**
/// （其中第一档绿 `#1F883D` 尤其显眼 —— 它正是改色前主按钮的那支绿），
/// 用户裁定换成现在这一版：**白底 + 主色描边 + 主色字母**。
///
/// ⚠️ 连带**删掉**了三件东西（它们唯一的用途就是"每人一色"）：
/// `Theme.Palette.avatarFallback` 色表、`UserAvatar.colorIndex(for:)`、
/// 以及 `fallbackSeed` 这个入参（`AvatarStack` 曾用它给匿名条目错开颜色）。
/// **兜底圆如今对所有账号是同一个样子** —— 认人靠的是那个首字母，不再是颜色。
///
/// ⚠️ 因此那条"绝不能用 `hashValue`"的旧约束也随之作废：现在**没有任何颜色依赖哈希**了。
/// （那条约束当年是对的 —— Swift 字符串哈希每进程随机化，会让同一账号每次冷启动换色。）
///
/// ## 图片按显示尺寸降采样（2026-10-11 落地，`TECH_SPEC §5.3`）
///
/// GitHub 头像端点的原图约 460px 见方，而这里最大的用处是「我的」页那个 86pt 圆
/// —— `@3x` 也才 258px。不降采样的话，一个 28pt 的提交行头像也要先拖回一张 460px 的原图，
/// 再缩到 28pt 去画；屏幕上看到的就是"先闪一个首字母块、过一会儿才换成真图"。
/// 所以请求前把 `?s=<像素>` 追上去。
///
/// ⚠️ **收口在本类型**，而不是三处调用点各改一遍 —— 带 `avatarURL` 的三处
/// （「我的」页 86pt / 提交行 28pt / 贡献者堆叠 34pt）**全都经过本件**，
/// 而 `diameter` 就是各自的真实展示尺寸、`displayScale` 由环境给。
/// 这样"同一个头像在两处走两种 URL"不会发生 —— `ProfileMapper.avatarURL(from:)`
/// 那条注释当初担心的正是这个，它因此**没有**在领域层单方面补尺寸。
///
/// ⚠️ **只对 `githubusercontent.com` 的 host 追加**：那是 `§5.3` 点名"支持 `?s=`"的端点。
/// 别的 host（将来若换了图床）**原样请求** —— 不给它塞一个它不认识的参数。
///
/// ## 图片可空，缺了也不消失
///
/// `avatarURL` 为 `nil`（或取不到）时画首字母兜底圆 —— 而不是让那个位置空一块。
/// 匿名用户（`login` 为 `nil`）画 `?`：让人一眼看出"这条没有名字"，
/// 而不是画个空白圆圈让人以为图片还在加载。
///
/// ## 它是内容层
///
/// 头像属内容（§10.2），**实色，不加 Liquid Glass**。
public struct UserAvatar: View {

    /// 首页右上角那颗的直径（2026-10-16 走查第 85 条加；**第 86 条由 30 放大到 36**）。
    ///
    /// ⚠️ **这个数没有原型出处** —— 原型（已删）里从来没有
    /// "导航栏头像"这一件；它来自本次改版的参照物 App Store 的 Today 页，量出来约 30pt。
    /// ⚠️ 30 上线后用户第 86 条目视判「太小」⇒ 放大到 **36**（顶栏净高约 54pt，
    ///    36 还剩上下各 9pt 余量，与顶栏那颗 26pt 标题垂直居中对齐）。
    /// ⚠️ 别再往上加：它是**一颗按钮**不是插画；超过 40 就开始吃顶栏的高度预算，
    ///    并且会与那颗 26pt 标题抢视觉重量 —— 顶栏的主角是标题，不是头像。
    public static let navigationDiameter: CGFloat = 36

    /// `navigationDiameter` 那一档的首字母字号（11pt 挂在 36pt 圆上会显空）。
    ///
    /// ⚠️ 与 `profileInitialFont` 同款的做法：**字号跟档位走，不按直径乘系数**
    ///    （类型说明里那三条比值 0.382 / 0.365 / 0.349 已经证明系数法不成立）。
    ///    这里取 14pt / `.bold`：36pt 圆的直径比 34 那一档只大 2pt，
    ///    但它是**顶栏里唯一一颗图**，兜底时看得很清楚 ⇒ 值得单独一档。
    public static let navigationInitialFont: Font = .system(size: 14, weight: .bold)

    /// 列表行 / 搜索结果行的直径（原型 `.avatar` = 34×34）。
    public static let rowDiameter: CGFloat = 34

    /// §5.10 用户资料弹层的直径（原型 `openUserSheet` 的 52×52）。
    public static let sheetDiameter: CGFloat = 52

    /// §4.17「我的」页头部的直径（原型 `.profile-head .big-avatar{width:86px}`，切片 9 加）。
    public static let profileDiameter: CGFloat = 86

    /// `.profileDiameter` 那一档的首字母字号（原型 `.big-avatar{font-size:30px;font-weight:800}`）。
    ///
    /// ⚠️ 权重是 **`.heavy`（800）**，不是另外两档的 `.bold` —— 原型那里写的就是 800，
    /// 而它挂在 86pt 的圆上（比 `sheetDiameter` 大一倍多），字重差一档是看得出来的。
    public static let profileInitialFont: Font = .system(size: 30, weight: .heavy)

    /// 兜底圆的描边宽度（**2pt**，沿 `ColorSwatch.borderWidth` 的既有档）。
    ///
    /// ⚠️ 它挂在 34 / 36 / 52 / 86 四个直径上：2pt 在最小那档已经清楚，
    /// 在 86pt 那档偏细但仍是"一圈环"而不是"一条线"。要加粗就改这一个数。
    public static let borderWidth: CGFloat = 2

    /// 登录名。**可空** —— 匿名贡献者没有。
    public let login: String?

    /// 头像地址。**可空** —— 取不到就画首字母兜底。
    public let avatarURL: URL?

    public let diameter: CGFloat

    /// 首字母的字号。`nil` = `Theme.Font.label`（既有两档的行为，见类型说明）。
    public let initialFont: Font?

    /// 屏幕缩放（`@2x` / `@3x`）—— 只用来算请求头像的像素边长。
    ///
    /// 走环境而不是写死 3：本项目是纯 iPhone（决策 #2），但预览与将来的外接屏
    /// 不必为这个假设背锅，而读环境是零成本。
    @Environment(\.displayScale) private var displayScale

    public init(
        login: String?,
        avatarURL: URL? = nil,
        diameter: CGFloat = UserAvatar.rowDiameter,
        initialFont: Font? = nil
    ) {
        self.login = login
        self.avatarURL = avatarURL
        self.diameter = diameter
        self.initialFont = initialFont
    }

    public var body: some View {
        Group {
            if let requestURL {
                AsyncImage(url: requestURL) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    default:
                        // 加载中与失败走同一个兜底圆 —— 失败时也不需要额外提示：
                        // 一个头像取不到不该打断整页（与 `AvatarStack` 同一条取舍）。
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .accessibilityLabel(login ?? "匿名贡献者")
    }

    /// 真正拿去请求的地址 —— `avatarURL` 按本件的展示尺寸降采样之后的结果。
    ///
    /// ⚠️ 它必须**稳定**：`AsyncImage` 的缓存键就是这个 URL，若它每次都变
    /// （比如把某个会抖的量算进了像素数），头像会陷入反复重下。
    /// `diameter` 与 `displayScale` 在同一台设备上都不变 ⇒ 同一个头像永远是同一个 URL。
    private var requestURL: URL? {
        guard let avatarURL else { return nil }
        return Self.downsampled(
            avatarURL,
            pixels: Self.pixelSize(for: diameter, scale: displayScale)
        )
    }

    private var fallback: some View {
        ZStack {
            Circle().fill(Theme.Palette.surface)
            Circle().strokeBorder(Theme.Palette.accent, lineWidth: Self.borderWidth)
            Text(Self.initial(for: login))
                .font(initialFont ?? Theme.Font.label)
                // 首字母压在白底上：`accent` 浅色档是 5.18:1，达正文 AA。
                .foregroundStyle(Theme.Palette.accent)
        }
    }

    // MARK: - 纯函数（可单测）

    /// 兜底圆里那个字符。缺名字 / 空名字 ⇒ `?`。
    ///
    /// 先 `trimmingCharacters` 再取首字符：`"   "` 这种"看着有、其实没有"的登录名
    /// 若直接取 `first` 会得到一个空格 —— 屏幕上就是**一个空圆**。
    ///
    /// `nonisolated`：它不碰任何 UI 状态，而 `View` 的成员默认继承主 actor 隔离 ——
    /// 不标的话，`AvatarStack.Member.initial`（非隔离的计算属性）调它就会得到一条
    /// actor 隔离告警。那条告警本身无害，但它会训练人忽略告警，
    /// 而下一个真告警就不会被看见了。
    public nonisolated static func initial(for login: String?) -> String {
        guard let first = login?.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "?"
        }
        return String(first).uppercased()
    }

    // MARK: - 纯函数：降采样（可单测）

    /// 一个边长 `diameter`（pt）的头像，在 `scale` 倍屏上要请求多少像素。
    ///
    /// `28pt @3x = 84`、`86pt @3x = 258`。**向上取整**：宁可多要一个像素，
    /// 也不要因为 `28 × 2.75 = 77` 取整成 77 而让圆的边缘糊掉一点。
    ///
    /// `nonisolated` 的理由同 `initial(for:)` —— 它不碰任何 UI 状态。
    public nonisolated static func pixelSize(for diameter: CGFloat, scale: CGFloat) -> Int {
        max(1, Int((diameter * max(scale, 1)).rounded(.up)))
    }

    /// 给 GitHub 头像地址追一个 `?s=<pixels>`（`TECH_SPEC §5.3`）。
    ///
    /// 四条规矩，每条都有一个具体理由：
    ///
    /// 1. **已有 `s` ⇒ 覆盖**。服务端偶尔会带一个自己的默认尺寸，不覆盖等于白算。
    /// 2. **其余 query 原样保留**（`v=4` 那类）—— 它是 CDN 的缓存键的一部分，丢掉它会拿到旧图。
    /// 3. **只认 `githubusercontent.com` 的子域** ⇒ 别的地址**原样返回**，
    ///    不给它塞一个它不认识的参数（那会让某些图床返回 400，比慢更糟）。
    ///    ⚠️ 判据写 `.githubusercontent.com`（**带前导点**）而不是裸串：
    ///    后者会把 `evil-githubusercontent.com` 这种拼法一起放过去。
    /// 4. **拼不回去就原样返回**：宁可不降采样，也不要一个自己拼坏的 URL。
    public nonisolated static func downsampled(_ url: URL, pixels: Int) -> URL {
        guard url.host?.hasSuffix(".githubusercontent.com") == true,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }

        var items = components.queryItems ?? []
        items.removeAll { $0.name == "s" }
        items.append(URLQueryItem(name: "s", value: String(pixels)))
        components.queryItems = items
        return components.url ?? url
    }
}

#Preview {
    HStack(spacing: Theme.Spacing.l) {
        UserAvatar(login: "jiangjiang")
        UserAvatar(login: "dev-k")
        UserAvatar(login: "yyx990803")
        UserAvatar(login: "jiangjiang", diameter: UserAvatar.sheetDiameter)
        // 切片 9 那一档：86pt 圆 + 30pt/800 的首字母（不传 `initialFont` 会是 11pt —— 一个空圆）。
        UserAvatar(
            login: "jiangjiang",
            diameter: UserAvatar.profileDiameter,
            initialFont: UserAvatar.profileInitialFont
        )
        UserAvatar(login: nil)
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
