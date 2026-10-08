import Testing

@testable import GitDuoKit

/// 「操作失败 · 请重试」—— 写操作失败后的那一句通用提示（TECH_SPEC §8.5「操作类」）。
///
/// ## 这组断言守的是一条**引导**
///
/// 后半句 `请重试` 与 §8.5 的另一半承诺绑在一起：失败之后"按钮恢复可点"。
/// 少了这句话，一个转回原样的按钮看起来就像"点了没反应"。
///
/// ## ⚠️ 本文件只守得住"正本长什么样"，守不住"没有别的副本"
///
/// 收口前那三份同值副本（分支页 / 仓库详情 / 探索仓库详情）**全在 App target**，
/// 本包看不见 ⇒ 它们有没有被删干净，只能靠 `grep -rn "操作失败"` 归零来验证。
/// 这一条已写进 `ActionCopy` 的类型说明，此处不重复造一个测不到的断言。
@Suite("操作失败提示 · 唯一正本")
struct ActionCopyTests {

    @Test("逐字：`操作失败 · 请重试`")
    func exactWording() {
        #expect(ActionCopy.failed == "操作失败 · 请重试")
    }

    @Test("⚠️ 必须有「请重试」那半句 —— 少了它，失败的按钮就没有下一步")
    func retryGuidanceIsPartOfThePromise() {
        #expect(ActionCopy.failed.contains("重试"))
    }

    @Test("""
        ⚠️ 它**不声称成因** —— 不带"网络"这类客户端分不出来的判断
        （编一个成因会给用户错误的引导，同决策 #33 对令牌出口的要求）
        """)
    func itDoesNotInventACause() {
        // 可能的成因不止网络：`fullName` 形状不对、服务端 422 / 403、冲突 …
        // 而"具体是哪一档"各操作自己说得更准（那几句在各自的 `…Copy` 里，
        // 见 `ActionCopy` 的类型说明）⇒ 这一句只在没有更准的话可说时兜底。
        #expect(!ActionCopy.failed.contains("网络"))
        #expect(!ActionCopy.failed.contains("超时"))
        #expect(!ActionCopy.failed.contains("权限"))
    }

    @Test("⚠️ 它与「刷新失败」那一句**不是**同一句（两件事、两个出口）")
    func itIsNotTheRefreshToast() {
        // 刷新失败是"屏幕上有内容、这次没更新上"；操作失败是"我刚点的那个动作没成"。
        // 合成一句的后果：下拉刷新失败会告诉用户"操作失败"（他没操作什么），
        // 而 Star / 提交失败会说"下拉可重试"（那根本不是这次失败的重试方式）。
        #expect(ActionCopy.failed != RefreshCopy.failed)
        #expect(!ActionCopy.failed.contains("下拉"))
        #expect(!RefreshCopy.failed.contains("操作"))
    }
}
