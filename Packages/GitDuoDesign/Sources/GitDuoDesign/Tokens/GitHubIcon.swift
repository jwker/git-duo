import Foundation

/// 通用图标的 SF Symbol 名（原型 `scripts/02-icons.js` 的 `I.*`）。
///
/// ## 为什么不各写各的
///
/// 同一个图标在页面上常出现两次（分支胶囊、分支行、面包屑里的分支…），
/// 名字各写一遍就会出现"同一件事两个图标"——例如一处 `arrow.triangle.branch`、
/// 另一处凭印象写成 `arrow.branch`（**这个符号不存在**）。
///
/// ## ⚠️ 与 `StateIcon` 同一条告诫：名字写错**不会**在任何环节报错
///
/// SF Symbols 里没有的名字，编译期与测试期都发现不了
/// （SwiftPM 测试跑在 macOS 上，拿不到 `UIImage(systemName:)`），
/// 界面上表现为**图标凭空消失** —— 那片空白没有任何提示。
/// **改这个文件里的任何一个名字，都要跑一次模拟器或真机看一眼。**
///
/// 状态图标（Issue / PR 的开放·已合并·已关闭）不在本表，见 `StateIcon`。
public enum GitHubIcon {

    /// **分支** —— 原型 `I.fork`（两个圆点在上、一个在下，中间连线）。
    ///
    /// ⚠️ **有意偏差（已登记）**：SF Symbols 里**没有**与原型同形的符号
    /// （原型画的是 GitHub 的 fork 形状；`arrow.triangle.branch` 是标准的 git-branch 形状）。
    /// 取语义最近的一个，而不是自绘一个 `Path` ——
    /// 自绘等于在代码里维护一份图标资源，而它没有设计稿可依。
    /// 与 `StateIcon.pullRequestOpen`（`arrow.triangle.pull`）**不是同一个符号**：
    /// 那是"提 PR"，这里是"分支"。
    public static let branch = "arrow.triangle.branch"
}
