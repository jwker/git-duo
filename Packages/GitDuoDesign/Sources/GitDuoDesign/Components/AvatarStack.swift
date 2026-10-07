import SwiftUI

/// 头像堆叠 —— 贡献者概览那一排圆形头像（原型 `scripts/10-explore-repo.js`、PRD §4.13 第 8 条）。
///
/// ## 只画头像，不画"以及另外 N 位贡献者"
///
/// 那行文案在原型里是**独立于头像排的一行**（头像排下方），而且它的数字取决于
/// "总数比显示出来的多多少"这个业务口径（决策 #40 的 `per_page=100` 一页取回）。
/// 组件只回答"最多画几个、每个长什么样"；文案由调用方按领域层给的口径渲染。
/// 混在一起会让"到底显示了几个"变成两处各自算一次，而那正是最容易对不上的地方。
///
/// ## 匿名贡献者必须能渲染
///
/// GitHub 只把前 500 个邮箱关联到账号，其余贡献者**没有 `login`、没有头像**
/// （§9.11 / 决策 #40）。所以 `login` 与 `avatarURL` **都可空**，
/// 缺名字就用 `?` 占位、缺图片就用确定性的兜底色 —— 而不是让整块区域消失。
///
/// ## 它是内容层
///
/// 头像属内容（§10.2），**实色，不加 Liquid Glass**。
public struct AvatarStack: View {

    /// 一位贡献者。
    public struct Member: Sendable, Hashable {

        /// 登录名。**可空** —— 匿名贡献者没有。
        public let login: String?

        /// 头像地址。**可空** —— 匿名贡献者没有。
        public let avatarURL: URL?

        public init(login: String?, avatarURL: URL?) {
            self.login = login
            self.avatarURL = avatarURL
        }

        /// 图片取不到时画在圆里的那个字符。匿名 → `?`（让人一眼看出"这条没有名字"，
        /// 而不是画个空白圆圈让人以为是图片还在加载）。
        public var initial: String {
            guard let first = login?.trimmingCharacters(in: .whitespacesAndNewlines).first else {
                return "?"
            }
            return String(first).uppercased()
        }
    }

    public let members: [Member]

    /// 头像直径。原型 `.avatar` = 34×34，圆角即半径（正圆）。
    public let diameter: CGFloat

    /// 最多画几个 —— 超出的部分由调用方用"以及另外 N 位"那行文案交代。
    ///
    /// 原型画 **8** 个；8 个 34pt 头像加 6pt 间隙约 314pt，正好铺满一行手机宽度、
    /// 不至于挤到第二行。
    public let visibleLimit: Int

    public static let defaultVisibleLimit = 8

    public init(
        members: [Member],
        diameter: CGFloat = 34,
        visibleLimit: Int = AvatarStack.defaultVisibleLimit
    ) {
        self.members = members
        self.diameter = diameter
        self.visibleLimit = visibleLimit
    }

    public var body: some View {
        // 用 `indices` 而不是 `Array(members.enumerated())`：后者要靠"元组 keypath"（`\.offset`）
        // 取 id，那种写法在 Swift 里是条灰色地带；下标索引谁也歧义不了。
        // 匿名成员没有稳定标识，因此下标本就是它的唯一身份 —— 兜底色也随之确定。
        let shown = Array(members.prefix(visibleLimit))

        HStack(spacing: 6) {
            ForEach(shown.indices, id: \.self) { index in
                avatar(for: shown[index], offset: index)
            }
        }
    }

    private func avatar(for member: Member, offset: Int) -> some View {
        Group {
            if let url = member.avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFill()
                    default:
                        // 加载中与失败走同一个兜底圆 ——
                        // 失败时也不需要额外提示：一个头像取不到不该打断整页。
                        fallback(for: member, offset: offset)
                    }
                }
            } else {
                fallback(for: member, offset: offset)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .accessibilityLabel(member.login ?? "匿名贡献者")
    }

    private func fallback(for member: Member, offset: Int) -> some View {
        ZStack {
            Circle().fill(Theme.Palette.avatarFallback[colorIndex(for: member, offset: offset)])
            Text(member.initial)
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Palette.surface)
        }
    }

    /// 兜底色下标。
    ///
    /// ⚠️ **不能用 `hashValue`** —— Swift 的字符串哈希每个进程带随机种子，
    /// 同一账号会在每次冷启动后换一个颜色（严重时在一次会话里因列表重绘而换色），
    /// 而"头像颜色"是用户用来认人的视觉线索。这里用 djb2，跨进程稳定。
    private func colorIndex(for member: Member, offset: Int) -> Int {
        let seed = member.login ?? "anonymous-\(offset)"
        var hash: UInt64 = 5_381
        for byte in seed.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return Int(hash % UInt64(Theme.Palette.avatarFallback.count))
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
        AvatarStack(members: [
            .init(login: "jiangjiang", avatarURL: nil),
            .init(login: "reviewer-a", avatarURL: nil),
            .init(login: nil, avatarURL: nil),
            .init(login: "dev-k", avatarURL: nil),
        ])
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
