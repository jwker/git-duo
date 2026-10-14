import GitDuoDesign
import GitDuoKit
import SwiftUI

/// markdown 正文里的一个 **shields.io 徽章**（2026-10-14 新增，`REVIEW-CHECKLIST` **第 65 条**）。
///
/// ## 它为什么要自己画
///
/// 徽章在 GitHub 上是一张 SVG，而 `UIImage` 画不了矢量图（见 `MarkdownImageBytes`）
/// ⇒ 走"取字节 + 占位块"那条路只能是几块灰条，而这正是用户 2026-10-14 报回的问题。
/// 但徽章的**全部内容都写在地址里**（`MarkdownBadge` 已经解出来了）⇒
/// 这里用本 App 的字体与圆角把它**按同样的结构重画一遍**：左灰右彩、两段文字。
///
/// ⚠️ 于是它**不取字节、不打请求、离线也在** —— 比"真渲染 SVG"那条路省三样东西。
///
/// ## ⚠️ 两个高度是从 shields 抄的，不是本 App 的设计令牌
///
/// | 档 | 高度 | 文字 |
/// |---|---|---|
/// | 默认（`flat` / `flat-square` / `plastic` / `social`） | 20 | 原样 |
/// | `for-the-badge` | 28 | **全大写** |
///
/// ⚠️ 这两个高度**刻意不套 `Theme.Spacing`**：它们是"徽章长什么样"的一部分
/// （GitHub 上就是 20 与 28），换成 16 或 24 就不像徽章了。28 与我实测的 shields
/// 输出对得上（`?style=for-the-badge` 那枚 Discord 回的是 `189.5×28`）。
/// 字号落在 `Theme.Font.tag`（11pt semibold）—— 与 shields 的 11px 同值，不是新数。
///
/// ## ⚠️ 它不是 GitHub 上那张 SVG 的像素级复刻
///
/// 宽度、字距、阴影都不同（见 `MarkdownBadge` 那段说明）。有意的：
/// 要的是"一眼看得出这是个什么徽章"。
struct MarkdownBadgeView: View {

    let badge: MarkdownBadge

    var body: some View {
        HStack(spacing: 0) {
            if let label = badge.label {
                segment(label, background: badge.labelColor)
            }
            segment(badge.message, background: badge.color ?? .neutral)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            MarkdownCopy.badgeAccessibilityLabel(label: badge.label, message: badge.message)
        )
    }

    /// 一个色块（左灰右彩，形状一样、只有底色与文字不同）。
    private func segment(_ text: String, background: MarkdownBadgeColor) -> some View {
        Text(isUppercased ? text.uppercased() : text)
            .font(Theme.Font.tag)
            .foregroundStyle(background.prefersDarkText ? Theme.Palette.textPrimary : Color.white)
            .lineLimit(1)
            .padding(.horizontal, Self.horizontalPadding)
            .frame(height: height)
            .background(Color(red: background.red, green: background.green, blue: background.blue))
    }

    private var isUppercased: Bool { badge.style == .forTheBadge }

    private var height: CGFloat { isUppercased ? Self.tallHeight : Self.normalHeight }

    /// ⚠️ `flat-square` 的圆角**正好是 0** —— 那一档就叫"直角"。
    private var cornerRadius: CGFloat { badge.style == .flatSquare ? 0 : Self.cornerRadius }

    /// 默认档的高度（shields 的 `flat` 就是 20px）。
    private static let normalHeight: CGFloat = 20

    /// `for-the-badge` 档的高度（shields 也是 28）。
    private static let tallHeight: CGFloat = 28

    /// 胶囊圆角（shields 的 `flat` 是 3px）。
    private static let cornerRadius: CGFloat = 3

    /// 每一段文字两侧的留白。
    ///
    /// ⚠️ 真实宽度由 shields 按字体量出来（所以我们复刻不了一像素不差），
    /// 这里只给一个"看起来不挤"的定值 —— 与 `Theme.Spacing.xs`(4) 同一量级，
    /// 但**不套那个令牌**：它是内部留白，不是两件东西之间的距离。
    private static let horizontalPadding: CGFloat = 6
}
