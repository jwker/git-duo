import SwiftUI

/// 「我的」页的个人资料头部 —— 大头像 + 昵称 + `@登录名` + 简介
/// （PRD §4.17 第 2 条、TECH_SPEC §9.14）。
///
/// ```css
/// .profile-head{display:flex;flex-direction:column;align-items:center;padding:10px 0 4px}
/// .profile-head .big-avatar{width:86px;height:86px;…;margin-bottom:10px}
/// .profile-head h2{font-size:20px;font-weight:750}
/// .profile-head .login{font-size:14px;color:var(--text2);margin-bottom:8px}
/// .profile-head .bio{font-size:13px;color:var(--text2);text-align:center;
///                    max-width:280px;line-height:1.5}
/// ```
///
/// ## ⚠️ 头像：真实图片 + **同一个首字母块**兜底（2026-10-09 起）
///
/// 原型画的是一块首字母方块（`<div class="big-avatar" style="…">J</div>`），
/// 而真实头像是 `GET /user` 的 `avatar_url` ⇒ 这里把它交给 `UserAvatar` 的
/// `avatarURL` 那一档，**边界条件一个字都没变**：
///
/// | 情形 | 画什么 |
/// |---|---|
/// | 地址有值、图取回来了 | 那张图（圆形裁切） |
/// | 地址有值、**还在加载** | 首字母块（`AsyncImage` 的 `default` 分支） |
/// | 地址有值、**加载失败** | 同上（**不给失败提示**：一个头像取不到不该打断整页） |
/// | 地址是 `nil` | 同上 |
///
/// 所以"头像取不到"这件事在界面上**没有独立的失败态** —— 四种情形收敛到两种观感，
/// 而这两种都不需要用户做什么（`ViewerProfile.avatarURL` 同口径）。
///
/// ## ⚠️ 昵称与简介：`nil` ⇒ **整行不渲染**
///
/// PRD §4.17 第 2 条逐字：「昵称与简介取不到时**整行不渲染** —— 不留空行、也不显示占位
/// （"没有"与"空字符串"不是一回事）」。
///
/// 本件把 `name` / `bio` 声明成 **Optional** 就是为了让"不渲染"成为**必须处理的**分支
/// （若声明成 `String` 再填 `""`，视图照着画只会得到一个空行 —— 屏幕上像排版坏了，
/// 而真相是这个人没填）。
///
/// ⚠️ **空串与 `nil` 同处置**（都整行不渲染）：`Text("")` 虽然画不出字，
/// 却照样占掉一个行高（那正是"留空行"），所以两者在**渲染层**归成一件事。
/// 这不与 `ViewerProfile` 那条「`nil` 不是空串」矛盾 —— 那条说的是**语义**
/// （"没有"与"为空"要能区分），这条说的是**排版**（一行没有内容就不该占位置）。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
public struct ProfileHeader: View {

    /// 登录名。**不可空** —— 它是头像兜底块与 `@…` 那一行的唯一来源，也永远拿得到
    /// （取自 `authState`，连 `/user` 那条路失败时都在）。
    public let login: String

    /// 昵称。`nil`（或空串）⇒ 那一行不渲染。
    public let name: String?

    /// 简介。`nil`（或空串）⇒ 那一行不渲染，连它上面那 8pt 一起不留。
    public let bio: String?

    /// 头像地址。`nil` ⇒ 回落成首字母块（见类型说明）。
    public let avatarURL: URL?

    public init(
        login: String,
        name: String? = nil,
        bio: String? = nil,
        avatarURL: URL? = nil
    ) {
        self.login = login
        self.name = name
        self.bio = bio
        self.avatarURL = avatarURL
    }

    /// 简介的最大宽度（原型 `.bio{max-width:280px}`）。
    ///
    /// 原型写死 280 是为了**限制每行的长度**（超宽的屏上一行 60 个字很难读），
    /// 不是"必须这么宽"。保持在 280：它是原型逐字，而它有明确用途。
    static let bioMaxWidth: CGFloat = 280

    public var body: some View {
        VStack(spacing: 0) {
            // 86pt 那一档，连首字母字号一起（原型 `font-size:30px;font-weight:800`）。
            // ⚠️ 不传 `initialFont` 的话这里是一个 86pt 的圆里放一个 11pt 的字。
            // `avatarURL` 有值时画真实图片，加载中 / 失败 / 为 `nil` 都落回同一个首字母块
            // —— 那两个字号参数在两种情形下都要传，否则"图片没回来"那一瞬间会出现
            // 一个 11pt 的字在那个 86pt 的圆里（同一个头像两种观感的唯一来源）。
            UserAvatar(
                login: login,
                avatarURL: avatarURL,
                diameter: UserAvatar.profileDiameter,
                initialFont: UserAvatar.profileInitialFont
            )
            // 原型 `.big-avatar{margin-bottom:10px}`（10 不在 4pt 阶里 ⇒ 写原值）。
            .padding(.bottom, 10)

            if let name = Self.nonEmpty(name) {
                // 原型 `h2{font-size:20px;font-weight:750}` ⇒ `title`（`.title3` 20 + semibold）。
                // 750 与 600 之间没有更近的一档（`.bold` 是 700，但那是另一档语义的令牌）。
                Text(name)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center)
            }

            // `@登录名` 永远在（原型 `.login{font-size:14px;margin-bottom:8px}`）。
            Text("@\(login)")
                // 原型 14px ⇒ 最近的一档是 `rowTitle`（`.subheadline` 15），
                // 与 `SheetField` 把 14px 映到 `rowTitle` 同一个判据。
                .font(Theme.Font.rowTitle)
                .foregroundStyle(Theme.Palette.textSecondary)
                .padding(.bottom, Self.nonEmpty(bio) == nil ? 0 : Theme.Spacing.s)

            if let bio = Self.nonEmpty(bio) {
                Text(bio)
                    // 原型 13px ⇒ `footnote`（`.footnote` 13）。
                    .font(Theme.Font.footnote)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    // 原型 `line-height:1.5` ⇒ 13 × 1.5 ≈ 19.5，而 SwiftUI 的字号行高约 15.6
                    // ⇒ 补 4pt（`Spacing.xs`）。
                    .lineSpacing(Theme.Spacing.xs)
                    .frame(maxWidth: Self.bioMaxWidth)
            }
        }
        .frame(maxWidth: .infinity)
        // 原型 `.profile-head{padding:10px 0 4px}`。
        .padding(.top, 10)
        .padding(.bottom, Theme.Spacing.xs)
    }

    /// 空白串也算"没有" —— 见类型说明。
    ///
    /// 先 `trimmingCharacters` 再判空：`"   "` 这种"看着有、其实没有"的简介
    /// 若直接画，会在头像下面留出一块空白（连字数都数不出来）。
    static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.xl) {
        // 齐全
        ProfileHeader(
            login: "jiangjiang",
            name: "Jiang Jiang",
            bio: "iOS / SwiftUI 开发者。在做 GitHub 客户端 GitDuo。"
        )
        // 没填简介 ⇒ 只剩头像、昵称与 `@登录名`（`.login` 下面那 8pt 也不留）
        ProfileHeader(login: "jiangjiang", name: "Jiang Jiang")
        // 只拿得到登录名（`/user` 那一路失败时的样子）—— 头像回落成首字母块
        ProfileHeader(login: "jiangjiang")
        // 空白串当没有：`name` 与 `bio` 那两行都不出现
        ProfileHeader(login: "jiangjiang", name: "   ", bio: "")
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
