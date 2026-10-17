import SwiftUI

/// 导航行 —— 图标 + 标题 + 副标题 + 右侧尖角（原型 `styles/04-screens.css` 的 `.file-row`）。
///
/// ```css
/// .file-row{display:flex;align-items:center;gap:11px;padding:11px 4px;
///           border-bottom:1px solid var(--border-soft)}
/// .file-row:last-child{border-bottom:none}
/// .file-row svg{width:17px;height:17px;stroke:var(--text3)}
/// .file-row .fname{font-size:14.5px;font-weight:550}
/// .file-row .fmsg{font-size:11.5px;color:var(--text3);margin-top:2px}
/// ```
///
/// ## 它的两个消费场景与原型同一个类
///
/// 原型里 `.file-row` 同时用在**文件树的目录 / 文件行**（切片 6）与
/// **探索详情的「参与协作」两行**（本切片）。两处的视觉完全一致，所以是同一个组件；
/// 区别只在图标与去向上，而那是调用方的事。
///
/// ## 它**既坐 `List` 也坐 `CardBox`**，谁给内边距 / 分隔线看场景
///
/// | 场景 | 谁给内边距 | 谁给分隔线 |
/// |---|---|---|
/// | `List`（例如早先的探索仓库详情） | `List` 行 | 系统 |
/// | `CardBox`（2026-10-16 起探索仓库详情回到 `ScrollView`） | 本件自己（`11px 4px`） | 本件自己（`showsSeparator`） |
///
/// ⚠️ 2026-10-16 一度为了 `List` 把这两条删了，让系统全包；但探索仓库详情同日报
/// 回 `ScrollView`（与 §4.4 仓库首页同构，根因是 `List` 行把"自带白面圆角的块"压窄、
/// 且富内容块把段距撑爆——见 `ExploreRepoDetailView` 的类型说明）。坐回 `CardBox` 后
/// 这两条又加回来，与 `RepoFileRow`（`05-repo.js` 同族 `.file-row`）同构。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
public struct LinkRow: View {

    public let systemImage: String

    /// 图标颜色。默认第三级文字（原型的 `stroke:var(--text3)`）——
    /// 状态类图标（开放 Issue / PR）可以传 `Theme.Palette.stateOpenIcon` 之类。
    public let iconTint: Color

    public let title: String

    /// 副标题（原型 `.fmsg`）；`nil` = 不渲染。
    public let subtitle: String?

    public let action: () -> Void

    /// 画不画底部分隔线；末行传 `false`（原型 `.file-row:last-child{border-bottom:none}`）。
    ///
    /// - 坐 `List` 行：传 `false`（系统给分隔线，本件再画就是双线）。
    /// - 坐 `CardBox(vertical:0, horizontal:0)`：按"首行不画"传 `index > 0`。
    public let showsSeparator: Bool

    public init(
        systemImage: String,
        iconTint: Color = Theme.Palette.textTertiary,
        title: String,
        subtitle: String? = nil,
        showsSeparator: Bool = true,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.showsSeparator = showsSeparator
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: systemImage)
                    .font(.system(size: 17))
                    .foregroundStyle(iconTint)
                    // 图标不参与压缩：挤掉它这一行就只剩文字，认不出是什么类型的条目。
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Font.rowTitle)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 尖角是"这一行能进去"的唯一视觉信号 —— 少了它，整张卡看起来只是信息展示。
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            // ⚠️ 坐 `CardBox` 时由本件自己给原型原值 `11px 4px`（坐 `List` 时这层被
            //   系统行内边距覆盖，多一层只是无害的同向留白）⇒ 分隔线右缘贴卡边、左缘对齐文字。
            .padding(.vertical, 11)
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 读屏把整行念成一句，而不是"图像、Issues、浏览与参与讨论…、图像"。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle.map { "\(title)，\($0)" } ?? title)
        .accessibilityAddTraits(.isButton)
        // 底部 hairline（坐 `CardBox` 时由本件画；坐 `List` 传 `false` 交系统）。
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(Theme.Palette.borderSoft)
                    .frame(height: 1)
            }
        }
    }
}

#Preview {
    // ⚠️ **`CardBox` 里看**（本件在 `ScrollView` 页里坐 `CardBox(vertical:0, horizontal:0)`，
    //    自己画 `11px 4px` 内边距与底部分隔线）。`showsSeparator` 按"首行不画"传。
    ScrollView {
        CardBox(vertical: 0, horizontal: 0) {
            LinkRow(
                systemImage: "smallcircle.filled.circle",
                title: "Issues",
                subtitle: "浏览与参与讨论 · 无关闭权限",
                showsSeparator: true
            ) {}
            LinkRow(
                systemImage: "arrow.triangle.pull",
                title: "Pull Requests",
                subtitle: "查看他人贡献 · 可评论不可合并",
                showsSeparator: false
            ) {}
        }
        .padding(Theme.Spacing.page)
    }
    .background(Theme.Palette.background)
}
