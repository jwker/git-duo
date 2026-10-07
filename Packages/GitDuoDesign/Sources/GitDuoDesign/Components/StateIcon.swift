import Foundation

/// Issue / PR 状态图标的 SF Symbol 名（原型 `scripts/02-icons.js` 的 `I.issueO` / `I.issueC` / `I.pr` / `I.merge`）。
///
/// ## 为什么符号名要收在一处
///
/// 4.3 踩过一次：`arrow.triangle.branch` **没有 `.fill` 变体**，而当时打算"给名字追加 `.fill`"
/// 来推导激活态图标 ⇒ 会静默拿到一个**不存在的符号名**，界面上表现为**图标凭空消失**
/// （不报错、不警告，只是那一片空白）。
///
/// 状态图标有同样的形状问题（4 个状态 × 两种列表），所以名字只写在这里一次。
/// 颜色不走这里 —— 它们是 `Theme.Palette.stateOpenIcon` / `stateCompletedIcon`
/// （⚠️ 与状态**胶囊**用的 `stateOpen` / `stateMerged` 不是同一个值，见那里的说明）。
///
/// ## ⚠️ 改名字要用真机或模拟器看一眼
///
/// SF Symbols 里没有的符号名**不会**在编译期或测试期被发现（SwiftPM 测试跑在 macOS 上，
/// 拿不到 `UIKit` 的 `UIImage(systemName:)`），只能在界面上看出来。改完请跑一次模拟器。
public enum StateIcon {

    /// 开放的 Issue —— 圆圈套实心点（原型 `I.issueO`）。
    public static let issueOpen = "smallcircle.filled.circle"

    /// 已关闭的 Issue —— 圆圈套对勾（原型 `I.issueC`）。
    ///
    /// ⚠️ 它在**探索 Issues 列表里用不到**（决策 #38 只列开放式），
    /// 但「我的仓库」四分区（切片 7）要看已关闭的，届时直接取用。
    public static let issueClosed = "checkmark.circle.fill"

    /// 开放的 Pull Request —— 分叉箭头（原型 `I.pr`）。
    public static let pullRequestOpen = "arrow.triangle.pull"

    /// 已合并的 Pull Request —— 汇合箭头（原型 `I.merge`）。
    public static let pullRequestMerged = "arrow.triangle.merge"
}
