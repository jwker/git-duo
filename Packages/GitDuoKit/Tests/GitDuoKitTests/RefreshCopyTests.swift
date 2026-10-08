import Testing

@testable import GitDuoKit

/// 「刷新失败」那一句轻提示（TECH_SPEC §8.5「刷新不遮挡已有内容」）。
///
/// ## 这组断言守的是一条**承诺**
///
/// 后半句 `下拉可重试` 是操作引导：它告诉用户"重试的入口还在原来那个手势上"。
/// 而这句话成立的前提是**页面上确实留了内容**（失败态没有把屏幕擦掉）——
/// 那一半在各自的 ViewModel 里（`hadContent` 那条分支），不在本类型里。
///
/// ## ⚠️ 本文件只守得住"正本长什么样"，守不住"没有别的副本"
///
/// 收口前那四份同值副本（首页 / 探索仓库详情 / 提交详情 / 仓库详情）**全在 App target**，
/// 本包看不见 ⇒ 它们有没有被删干净，只能靠 `grep -rn "刷新失败"` 归零来验证。
/// 这一条已写进 `RefreshCopy` 的类型说明，此处不重复造一个测不到的断言。
@Suite("刷新失败轻提示 · 唯一正本")
struct RefreshCopyTests {

    @Test("逐字：`刷新失败 · 下拉可重试`")
    func exactWording() {
        #expect(RefreshCopy.failed == "刷新失败 · 下拉可重试")
    }

    @Test("⚠️ 必须有「下拉可重试」那半句 —— 少了它，失败这件事就没有出口")
    func retryGuidanceIsPartOfThePromise() {
        #expect(RefreshCopy.failed.contains("下拉"))
        #expect(RefreshCopy.failed.contains("重试"))
    }

    @Test("⚠️ 它是一句**轻提示**，不是整页失败态：不带感叹号、不喊「错误」")
    func itReadsAsAToastNotAFailureScreen() {
        // §8.5 的要点正是"不遮挡已有内容" ⇒ 这句话不该长得像一个会把屏幕接管过去的错误。
        #expect(!RefreshCopy.failed.contains("!"))
        #expect(!RefreshCopy.failed.contains("！"))
        #expect(!RefreshCopy.failed.contains("错误"))
        // 同理它不该说"失败"之外的判断（比如"网络不可用"）——
        // 那个成因客户端分不出来（`GitHubError` 的归一化是另一条链路）。
        #expect(!RefreshCopy.failed.contains("网络"))
    }
}
