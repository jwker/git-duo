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
        ///
        /// 实现委派给 `UserAvatar.initial(for:)` —— 单个头像与头像排共用同一份规则，
        /// 免得"匿名画 `?`"这件事在两处各写一遍、然后其中一处忘了处理空名字。
        public var initial: String { UserAvatar.initial(for: login) }
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
        let shown = Array(members.prefix(visibleLimit))

        HStack(spacing: 6) {
            ForEach(shown.indices, id: \.self) { index in
                // 逐个复用 `UserAvatar` —— 首字母与兜底色算法**只有那一份实现**
                // （它原本是本文件私有的，切片 5 把它提到了 `UserAvatar` 上）。
                // 匿名条目传 `anonymous-<下标>` 当种子：一排没有登录名的头像
                // 若都用同一个种子会得到同一个颜色、糊成一块。
                UserAvatar(
                    login: shown[index].login,
                    avatarURL: shown[index].avatarURL,
                    diameter: diameter,
                    fallbackSeed: shown[index].login ?? "anonymous-\(index)"
                )
            }
        }
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
