import SwiftUI

/// 仓库图标块 —— 深底 + 白色字形（原型 `styles/03-components.css` 的 `.repo-avatar`）。
///
/// ## 三个尺寸档来自原型，不是随便定的
///
/// | 档 | 尺寸 / 圆角 / 字形 | 原型出处 |
/// |---|---|---|
/// | `.standard` | 34 / 9 / 19 | `.repo-avatar` 默认（仓库详情头部、趋势卡） |
/// | `.row` | 30 / 8 / 16 | `.recent-row .repo-avatar`（最近访问行） |
/// | `.compact` | 32 / 8 / 16 | `.sr-item .repo-avatar`（搜索结果行） |
///
/// ## ⚠️⚠️ 2026-10-15 起，**屏幕上不再画它**（走查第 72 条，用户裁定）
///
/// 所有仓库行 / 详情头的图标块都换成了 **owner 头像**（圆形、首字母兜底，走 `UserAvatar`）
/// —— 用户拍板「文件夹图标换成用户头像」。本类型**只剩骨架几何**这一个消费方：
/// 各骨架屏（`RepoCardSkeleton` 等）仍引用这里的 `diameter` / `cornerRadius` 常量，
/// 免得占位尺寸在两处各写一份。
///
/// ⚠️ 因此**别给本类型新增使用**；也别删 —— 删了骨架就没了尺寸的单一来源。
/// 真要收口，等某天骨架也改用别的形状时一并处理。
///
/// ## 为什么字形象征性地选了「文件夹」
///
/// 原型的 `I.repo` 路径是 `M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z`
/// —— **一个文件夹**，而不是 GitHub 网页端那种"书本"造型。原型是唯一可点验收依据，
/// 所以这里取 `folder.fill`。（2026-10-15 起字形也不再用 —— 留着只是记录出处。）
///
/// ## 它是内容层，所以是实色
///
/// 图标块属列表行 / 卡片的内容（§10.2 明确点名"仓库卡片"），**不得加 Liquid Glass**。
public struct RepoAvatar: View {

    public let diameter: CGFloat
    public let cornerRadius: CGFloat
    public let glyphSize: CGFloat

    /// 仓库详情头部 / 趋势卡片的默认档。
    public static let standard = RepoAvatar(diameter: 34, cornerRadius: 9, glyphSize: 19)
    /// 最近访问行。
    public static let row = RepoAvatar(diameter: 30, cornerRadius: 8, glyphSize: 16)
    /// 搜索结果行。
    public static let compact = RepoAvatar(diameter: 32, cornerRadius: 8, glyphSize: 16)

    public init(diameter: CGFloat, cornerRadius: CGFloat, glyphSize: CGFloat) {
        self.diameter = diameter
        self.cornerRadius = cornerRadius
        self.glyphSize = glyphSize
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Theme.Palette.repoAvatarSurface)
            .frame(width: diameter, height: diameter)
            .overlay(
                Image(systemName: "folder.fill")
                    .font(.system(size: glyphSize))
                    .foregroundStyle(Theme.Palette.surface)
            )
            // 装饰性：读屏该听到的是"仓库名"，而不是"文件夹图标"。
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: Theme.Spacing.l) {
        RepoAvatar.row
        RepoAvatar.compact
        RepoAvatar.standard
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
