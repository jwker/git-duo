import Foundation

/// 登录页展示的权限预告 —— **唯一一份定义**。
///
/// 依据：TECH_SPEC §3.4（权限清单）、§3.8、`GITHUB-APP-SETUP.md` §1。
///
/// 为什么放在领域包里而不是视图里：这六项不是"界面文案"，而是**App 向 GitHub 声明的权限**
/// 这一事实的本地表述。放在这里，它就能被单测守住；放在 SwiftUI 视图里，就只能靠肉眼。
///
/// ⚠️ 改它必须**三处同步**：① 本文件；② GitHub App 设置页的勾选；③ `TECH_SPEC.md` §3.4 的表。
///    只改一处就会出现"登录页承诺的权限 ≠ 授权页实际要的权限"——
///    原型里靠一条回归断言（两处文本逐条相同）守着；Swift 侧没有授权页可对照
///    （那是 GitHub 渲染的），因此只能靠这条注释 + 文档一致性来守。
public struct AuthPermission: Identifiable, Hashable, Sendable {

    public let title: String
    public let detail: String
    public let symbol: String

    public var id: String { title }

    public init(title: String, detail: String, symbol: String) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
    }

    /// 六项，不多不少（【已定】只勾这六项，其余全部不勾，最大化用户信任）。
    /// 后两项是**账号级**权限：缺了 Star / 关注会直接 403（2026-10-05 核实）。
    public static let all: [AuthPermission] = [
        AuthPermission(
            title: "仓库内容",
            detail: "读取代码 / 文件树；提交、新建、上传文件（读写）",
            symbol: "folder"
        ),
        AuthPermission(
            title: "Issues",
            detail: "查看、创建、评论、开关（读写）",
            symbol: "checkmark.circle"
        ),
        AuthPermission(
            title: "Pull Requests",
            detail: "查看、创建、评论、合并（读写）",
            symbol: "arrow.triangle.pull"
        ),
        AuthPermission(
            title: "Star 收藏",
            detail: "Star / 取消 Star 仓库，读取 Starred 列表（读写）",
            symbol: "star"
        ),
        AuthPermission(
            title: "关注关系",
            detail: "关注 / 取关用户（读写）",
            symbol: "person.2"
        ),
        AuthPermission(
            title: "账号基本信息",
            detail: "读取公开资料、贡献数据与关注列表（只读）",
            symbol: "person.crop.circle"
        )
    ]
}
