import Foundation
import Testing

@testable import GitDuoDesign

/// `ToastCenter` —— 单通道 + 倒计时取消。
///
/// ## 为什么这个套件必须存在
///
/// §8.4 把"连续 `show(_:)` 必须取消上一条倒计时"写成了一条**纪律**，
/// 而违反它的表现是"提示一闪而过" —— 看起来像动画没调好、像渲染卡了，
/// 唯独不像"两处代码各写各的都对，但合起来是错的"。
/// 这类缺陷只有靠时序断言才捉得住，点一百次也未必撞上。
///
/// ⚠️ 时长全部注入（默认 2.4 秒）—— 用默认值的话这个套件要跑十秒以上，
/// 而"跑得慢的测试"迟早会被跳过。
@MainActor
@Suite("ToastCenter · 单通道与倒计时取消")
struct ToastCenterTests {

    @Test("初始不显示")
    func startsHidden() {
        let center = ToastCenter()
        #expect(center.isShowing == false)
        #expect(center.message == nil)
    }

    @Test("show 立刻显示，并且是**替换**而不是排队")
    func showDisplaysImmediately() {
        let center = ToastCenter(duration: .seconds(5))
        center.show("已 Star · 公开星标，仓库计数 +1")
        #expect(center.message == "已 Star · 公开星标，仓库计数 +1")

        center.show("已取消 Star · 仓库计数 −1")
        #expect(center.message == "已取消 Star · 仓库计数 −1", "排队会让用户先看到一条已经过期的消息")
        #expect(center.isShowing)
    }

    @Test("⚠️ 连续 show：先弹的那条不得把后弹的提前抹掉")
    func consecutiveShowDoesNotTruncateTheNewerOne() async throws {
        let center = ToastCenter(duration: .milliseconds(300))

        center.show("第一条")
        // 等掉第一条倒计时的大半。
        try await Task.sleep(for: .milliseconds(220))
        center.show("第二条")

        // 再等 150ms —— 此刻距"第一条"已过 370ms，超出它 300ms 的倒计时。
        // 若 `show` 没有先 `cancel()`，第一条的闹钟会在这里把 message 清成 nil。
        try await Task.sleep(for: .milliseconds(150))
        #expect(center.message == "第二条", "第二条被上一条的倒计时抹掉了 —— show() 必须先 cancel")

        // 第二条自己的倒计时走完，正常消失。
        try await Task.sleep(for: .milliseconds(350))
        #expect(center.message == nil)
    }

    @Test("到时间自动消失")
    func autoDismisses() async throws {
        let center = ToastCenter(duration: .milliseconds(80))
        center.show("已清除最近访问记录")
        #expect(center.isShowing)

        try await Task.sleep(for: .milliseconds(300))
        #expect(center.isShowing == false)
    }

    @Test("dismiss 立即收起，且停掉倒计时（不会延迟把新提示抹掉）")
    func dismissCancelsPendingTimer() async throws {
        let center = ToastCenter(duration: .milliseconds(200))
        center.show("已取消 Star · 仓库计数 −1")
        center.dismiss()
        #expect(center.message == nil)

        // 停掉之后紧接着来一条新的：旧倒计时不该在半路把它清掉。
        center.show("已 Star · 公开星标，仓库计数 +1")
        try await Task.sleep(for: .milliseconds(120))
        #expect(center.message == "已 Star · 公开星标，仓库计数 +1")
    }
}
