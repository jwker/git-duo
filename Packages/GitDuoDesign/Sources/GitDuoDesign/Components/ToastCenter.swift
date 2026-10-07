import Foundation
import Observation

/// 轻提示的**唯一通道**（TECH_SPEC §8.4）。
///
/// ## 为什么不是每个页面自己管一个 Toast
///
/// 由 `AppEnvironment.toast` 唯一持有、挂在 `MainTabView` 上 ⇒ 四个 Tab、七条导航栈
/// **共用一个提示通道**。否则"详情页点完 Star 立刻切回列表"会看到两个提示同时挂着，
/// 或者更糟：新页面的提示把上一条顶掉、上一条的倒计时却还在跑着。
///
/// ## 连续 `show(_:)` 必须取消上一条的倒计时
///
/// ⚠️ 这条是**必须**的，而且漏掉它的表现很隐蔽：
///
/// ```
/// t=0.0s  show("第一条")   → 倒计时 2.4s，预计 t=2.4s 清空
/// t=0.1s  show("第二条")   → 文案换成第二条
/// t=2.4s  第一条的倒计时到点 → 把 message 清成 nil
/// ```
///
/// 于是第二条**只显示了 0.1 秒就消失**，用户看到提示"一闪而过"，
/// 而代码里两处都写得没错。所以每次 `show` 都先 `cancel()` 上一条。
/// 这条由 `ToastCenterTests` 钉住。
///
/// ## 为什么时长可注入
///
/// 默认 2.4 秒（§8.4）。测试里传 300ms —— 否则这个套件要跑两秒多，
/// 而"跑得慢的测试"迟早会被跳过。
@MainActor
@Observable
public final class ToastCenter {

    /// 默认停留时长（§8.4：2.4 秒自动消失）。
    public static let defaultDuration: Duration = .milliseconds(2_400)

    /// 当前该显示的文案；`nil` = 不显示。
    public private(set) var message: String?

    /// 当前是否正在显示。
    public var isShowing: Bool { message != nil }

    private let duration: Duration

    /// 下一条提示的自动消失任务。
    private var dismissal: Task<Void, Never>?

    public init(duration: Duration = ToastCenter.defaultDuration) {
        self.duration = duration
    }

    /// 显示一条提示。
    ///
    /// 已在显示时**直接替换**（不排队）：提示是"刚才那件事的结果"，
    /// 而排队的语义是"按顺序播报"，那会让用户看到一条**已经过期**的消息
    /// —— 比如他已经点了两次 Star，却先看到"已 Star"再看到"已取消"。
    public func show(_ text: String) {
        // ⚠️ 先取消上一条（见类型说明里那段时序）。
        dismissal?.cancel()
        message = text

        dismissal = Task { [weak self, duration] in
            try? await Task.sleep(for: duration)
            // `cancel()` 会让 `sleep` 立刻抛出，所以这里再确认一次：
            // 否则被取消的那条会把**新**提示一起抹掉。
            guard !Task.isCancelled, let self else { return }
            self.message = nil
            self.dismissal = nil
        }
    }

    /// 立即收起（用户跳走了、或要显示别的东西）。
    public func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        message = nil
    }
}
