import Foundation
import GitHubAPI
import GitDuoDesign
import GitDuoKit

/// 新建 Issue 页（PRD §4.10）的状态。
///
/// ## 它几乎没有状态，那正是重点
///
/// 这一页**不发任何取数请求** —— 目标仓库、标题、正文、标签全部来自用户输入
/// 与路由参数。所以本类型里没有 `LoadState`、没有骨架期、没有"取失败"那一档。
///
/// 三条规则仍然收在这里而不是散进视图（`NewIssueDraft` 的类型说明写了为什么）：
/// 标题为空用占位标题、正文的"空"与非空、已选标签的增删与顺序。
/// 它们是**发出去的内容**，不是界面上的话。
///
/// ## ⚠️ 进页面即空草稿（PRD §4.10「进入页面时重置已选标签并渲染标签行」）
///
/// 这一条**没有单独的方法**：`draft` 的初值就是 `NewIssueDraft.empty`，
/// 而每次推入这一页都会造一个新的 `NewIssueViewModel`（组合根 → `RouteView`），
/// 所以"进页面时是空的"是构造出来的，不依赖某个 `start()` 被记得调用。
/// 加一个 `start()` 反而多一个"忘了调用就带着上一页内容"的分支。
///
/// ## ⚠️ 没有"内容为空则禁用提交"
///
/// 原型与 PRD §4.10 都**没有**这一档：标题空 ⇒ 用占位标题（`新 Issue`）照发，
/// 正文空 ⇒ 不带 `body` 字段照发。GitHub 允许一条只有占位标题的 Issue，
/// 而"按钮灰着 + 没有解释"是比"发出去一条标题为「新 Issue」的"更坏的体验。
/// 所以这里**不设** `canSubmit` —— 加了它就是一个替用户拍板的产品决定。
@MainActor
@Observable
final class NewIssueViewModel {

    let fullName: String

    /// 页面上那份草稿（标题 / 正文 / 已选标签）。
    ///
    /// ⚠️ 整体是一个 `NewIssueDraft` 而不是三个字段：三条规则都在那个类型里，
    /// 拆开就等于把它们复制到本类型。视图用 `$model.draft.title` 直接绑两个输入框。
    var draft: NewIssueDraft = .empty

    /// 提交在途（按钮内联 loading + 禁用，防重复提交 —— §8.5「操作类」）。
    private(set) var isSubmitting = false

    private let creator: CreateIssue
    private let toast: ToastCenter

    init(
        fullName: String,
        creator: CreateIssue,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.creator = creator
        self.toast = toast
    }

    // MARK: - 标签

    /// 弹层里点一行 —— 增还是删由领域层的 `NewIssueDraft.toggle` 决定
    /// （"有就去掉、没有就追加"，顺序 = 选中的先后顺序）。
    func toggleLabel(_ label: Label) {
        draft.toggle(label)
    }

    /// 点掉标签行上的一颗胶囊。
    ///
    /// ⚠️ 它**只做删除**，与 `toggleLabel` 分开：胶囊行上那颗一定是已选的，
    /// 走 `toggle` 也能得到同一个结果，但语义上"点这颗"与"切一下"是两件事 ——
    /// 而 `toggle` 的语义若将来变了（比如加一个"最多选 N 个"的约束），
    /// 胶囊行不会跟着变成"点了没反应"。
    func removeLabel(_ label: Label) {
        draft.labels.removeAll { $0.name == label.name }
    }

    /// 这颗标签选上了没有（标签行与弹层两处共用同一个判据 —— 在草稿里）。
    func isSelected(_ label: Label) -> Bool {
        draft.isSelected(label)
    }

    // MARK: - 提交

    /// 点「提交 Issue」。
    ///
    /// 三条路径（PRD §4.10）：
    /// - **成功** ⇒ 给一句带编号与标签数的提示（`CreatedIssue.toastMessage`，
    ///   原型 `07-issues.js:71` 逐字），并**返回那条 Issue** —— 由视图决定"返回上一页"
    ///   （导航是视图的事，见下）；
    /// - **失败** ⇒ 一句通用提示（`ActionCopy.failed`）、**页面留在原地**：
    ///   用户刚写完的标题与正文一个字都不该丢，而重试就是把按钮再点一次；
    /// - **在途** ⇒ 直接返回 `nil`（重入守卫，与 `IssueDetailViewModel.send` 同一形状）。
    ///
    /// ## ⚠️ 为什么"返回上一页"不在这里
    ///
    /// 提示属于**这次操作的结果**（本类型知道结果），而"退出这一页"属于导航。
    /// 导航由视图用 `@Environment(\.dismiss)` 完成 —— 它不必假设自己在哪一条栈上，
    /// 而 `Router.pop()` 作用的是**当前选中的 Tab**（`Router` 的说明），
    /// 在这一层用它是把"这一页在哪条栈里"变成一条隐含假设。
    ///
    /// - Returns: 服务端建成的那条 Issue；失败或被守卫挡住时为 `nil`。
    func submit() async -> CreatedIssue? {
        guard !isSubmitting else { return nil }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let created = try await creator.submit(fullName: fullName, draft: draft)
            toast.show(created.toastMessage)
            return created
        } catch {
            // ⚠️ 那句提示**不声称是网络问题**：`ActionCopy.failed` 只说"操作失败 · 请重试"。
            //    这里可能的成因不止网络（`fullName` 形状不对、服务端 422 / 403），
            //    而客户端分不出来 —— 编一句"网络不可用"会给用户错误的引导
            //    （同决策 #33 对令牌出口的要求）。
            toast.show(ActionCopy.failed)
            return nil
        }
    }
}
