import Testing

@testable import GitDuoKit

/// **对话区共用文案**（`ConversationCopy`）的断言 —— §4.9 / §4.11 两个页面共用那一族。
///
/// ## 为什么单独一个文件
///
/// `ConversationCopy` 是 7.1 为了"两页共用的话语只写一遍"专门立起来的类型，
/// 但**它此前一条断言都没有**（同一批的 `IssueCopyLabelSheetTests` 是 7.4 才补的）。
/// 一个"专门用来防止两处不一致"的类型，自己却没人看着 —— 那正是它会被慢慢掏空的方式。
///
/// 沿 `IssueCopyLabelSheetTests` 的同一条纪律：**文案是契约，逐字钉住**。
@Suite("对话区共用文案（§4.9 / §4.11）")
struct ConversationCopyTests {

    @Test("四句逐字（PRD §7 与原型两处逐字）")
    func copyIsVerbatim() {
        #expect(ConversationCopy.emptyCommentToast == "先写点内容再发送")
        #expect(ConversationCopy.commentSentToast == "评论已发送")
        #expect(ConversationCopy.sendAction == "发送")
        #expect(ConversationCopy.sendFailureNotice == "⚠ 发送失败：网络不可用。草稿已保留，可重试。")
    }

    @Test("⚠️ 失败提示条那句**必须同时含** `⚠` 与那半个承诺（草稿已保留 · 可重试）")
    func failureNoticeKeepsItsPromise() {
        // 这句是**一句承诺**：成立的唯一前提是草稿真的落了盘（决策 #59 / `CommentDraftStore`）。
        // 把"草稿已保留"那半句删掉，文案与实现就脱钩了 —— 而它们必须同时成立。
        // 用 `contains` 而不是整串相等：这一条管的是"那句承诺有没有被删掉"，
        // 整串逐字的活儿由上一条负责（两条各管一件事，改措辞时不会同时报警）。
        #expect(ConversationCopy.sendFailureNotice.contains("⚠"))
        #expect(ConversationCopy.sendFailureNotice.contains("草稿已保留"))
        #expect(ConversationCopy.sendFailureNotice.contains("可重试"))
    }

    @Test("⚠️ 「发送」住在共用文案里 —— 两页用的是同一个词（原型两处逐字相同）")
    func sendActionIsShared() {
        // 它原先在 `IssueCopy`（7.1 按"§4.9 的评论输入区"归的类），而 PR 页用的是同一个词。
        // 这一条把它的新位置钉住：谁把它挪回 `IssueCopy`，这里当场编译不过。
        #expect(ConversationCopy.sendAction == "发送")
    }

    @Test("⚠️ 两处输入框占位**有意不同**（原型逐字如此）⇒ 它们**不在**共用文案里")
    func placeholdersDifferByDesign() {
        // 「哪些该上提、哪些该留在页面」这条分工，就是靠这一条显示的：
        // 占位两页不同 ⇒ 留在各自的页面文案；「发送」「评论已发送」两页相同 ⇒ 上提共用。
        #expect(IssueCopy.commentPlaceholder == "写评论… (Markdown 支持)")
        #expect(PullCopy.commentPlaceholder == "写评论…")
        #expect(IssueCopy.commentPlaceholder != PullCopy.commentPlaceholder)
    }
}
