import Foundation
import GitHubAPI

/// PR 详情两屏的可见文案：PR 详情（PRD §4.11）· 合并弹层（§5.3）。
///
/// ## 文案来源（`AGENTS.md §1`：**原型 > TECH_SPEC > PRD**）
///
/// 绝大多数句子逐字取自 `scripts/08-pr.js`（`SCR.prDetail` / `prHeadNote` / `prSeg` /
/// `openMergeSheet` / `doMerge` / `closePr` / `reopenPr`）。少数几句原型给不出，
/// 按 PRD / §9.9 补 —— **每一处都在下面逐个注明了**。
///
/// ⚠️ **评论输入区的三句共用文案不在这里**（`先写点内容再发送` / `评论已发送` /
/// 发送失败提示条），它们在 `ConversationCopy` —— Issue 详情用的是同三句。
public enum PullCopy {

    // MARK: - §4.11 分区条

    /// 三个分区的标题（原型 `08-pr.js:15` 逐字，含英文大小写）。
    public static let conversationSegment = "对话"
    public static let commitsSegment = "Commits"

    /// 第三个分区的标题**带增删统计**：`文件 +842 −156`（原型 `${curPr.ds}`）。
    ///
    /// ⚠️ 那个统计**只有详情端点给**（列表端点不返回 ⇒ 决策 #58）——
    /// 所以这个标题在 PR 详情页一定拿得到，而在列表卡片上一定拿不到。
    public static func filesSegment(stats: String) -> String {
        "文件 \(stats)"
    }

    // MARK: - §4.11 头部

    /// 分支流向：`feature/repo-hub → main`（原型 `${pr.b}`，箭头两侧**有空格**）。
    public static func branchFlow(head: String, base: String) -> String {
        "\(head) → \(base)"
    }

    /// 头部元信息：`#57 · feature/repo-hub → main · 更新于 2 小时前`（原型逐字）。
    ///
    /// ⚠️ 拿不到 `updatedAt` 时**整段去掉**，不编时间（同 `IssueCopy.metaLabel` 的口径）。
    public static func metaLabel(
        number: Int,
        branchFlow: String,
        updatedAt: String? = nil
    ) -> String {
        var parts = ["#\(number)", branchFlow]
        if let updatedAt, !updatedAt.isEmpty {
            parts.append("更新于 \(updatedAt)")
        }
        return parts.joined(separator: " · ")
    }

    /// 状态说明第三句（开放，原型 `08-pr.js:27` 逐字）：
    /// `{作者} 请求合并到 {目标分支}`。
    public static func openNote(author: String, base: String) -> String {
        "\(author) 请求合并到 \(base)"
    }

    /// 状态说明第二句（已合并，原型逐字）：`已由 {作者} 合并进 {目标分支}`。
    public static func mergedNote(author: String, base: String) -> String {
        "已由 \(author) 合并进 \(base)"
    }

    /// 状态说明第一句（已关闭但未合并，原型逐字）。
    ///
    /// ⚠️ 它**不带任何变量**（不说谁关的、不说目标分支）—— 与另外两句有意不对称，
    /// 照抄原型，不要"补全"它。
    public static let closedNote = "已关闭，未合并"

    /// 已合并时对话分区顶部那条信息条（原型 `08-pr.js:48` 逐字）：
    /// `已由 {作者} 于 {时间} 合并进 {目标分支} · 讨论已锁定`。
    ///
    /// ⚠️ `mergedAt` 为 `nil`（服务端没给）时**整段去掉** `于 {时间}` 那一截，
    /// 而不是编一个时间 —— 拼出 `已由 X 于  合并进 main` 比少说一句更糟。
    public static func mergedBanner(author: String, mergedAt: String?, base: String) -> String {
        let head = mergedAt.map { "已由 \(author) 于 \($0) 合并进 \(base)" }
            ?? "已由 \(author) 合并进 \(base)"
        return head + " · 讨论已锁定"
    }

    /// 增删统计：`+842 −156`。
    ///
    /// ⚠️ 减号是 **U+2212 `−`**（原型逐字），不是 ASCII 的 `-`。
    /// 两者在屏幕上几乎一样，而换掉不会报错 —— `PullCopyTests` 正面钉住这一点。
    public static func statsLabel(additions: Int, deletions: Int) -> String {
        "+\(additions) −\(deletions)"
    }

    // MARK: - §4.11 操作区

    /// 操作分区标题（原型逐字）。
    public static let operationsSectionTitle = "操作"

    /// 合并按钮（原型逐字）。
    ///
    /// ⚠️ 原型那里前面还有一个内联 SVG（`${svg(I.merge)}`）—— 图标**不在这个常量里**：
    /// 它是一枚图形而不是一个字，由视图与图标一起排（同 `RepoDetailHero` 的做法）。
    public static let mergeAction = "合并 Pull Request"

    /// 关闭按钮（原型逐字）。
    public static let closeAction = "关闭 Pull Request"

    /// 重新打开按钮（原型逐字）。
    public static let reopenAction = "重新打开 Pull Request"

    /// 他人仓库的提示（原型 `08-pr.js:50` 逐字）。
    ///
    /// ⚠️ 它与探索 PR 列表的页脚（`PullListIndicator.footer`）**是两句不同的话**：
    /// 那句说"这个列表能做什么"，这句说"这一页的操作区为什么没有按钮"。
    /// 两者都有存在的理由，不要合并。
    ///
    /// ⚠️ Issue 详情页也有一句同位置的（`IssueCopy.readOnlyHint`，2026-10-09 补）——
    /// 那边**同样不复用**它自己的列表页脚，处置与这一处逐字相同。
    public static let readOnlyHint = "他人仓库 · 可评论 Review，合并 / 关闭需维护者权限"

    // MARK: - §4.11 评论输入区

    /// 输入框占位（原型 `08-pr.js:59` 逐字）。
    ///
    /// ⚠️ 与 Issue 详情的 `写评论… (Markdown 支持)` **不同**（原型两处就是不同的），
    /// 别统一。
    public static let commentPlaceholder = "写评论…"

    // MARK: - §4.11 文件分区

    /// 文件分区顶部提示：`12 个文件 · 点击文件卡片展开 diff`（原型 `08-pr.js:72` 逐字）。
    ///
    /// ⚠️ 那个数**必须用 `PullDetail.changedFiles`**，不能用文件数组的长度 ——
    /// 文件端点分页（`per_page=100`），大 PR 的第一页装不下全部。
    /// 两者都是"文件数"，读错不会报错、只会显示一个偏小的数（`PullDetailDTO` 写了理由）。
    public static func filesHint(count: Int) -> String {
        "\(count) 个文件 · 点击文件卡片展开 diff"
    }

    // MARK: - §5.3 合并弹层

    /// 弹层标题：`合并 · feature/repo-hub → main`（原型 `08-pr.js:111` 逐字）。
    public static func mergeSheetTitle(branchFlow: String) -> String {
        "合并 · \(branchFlow)"
    }

    /// 确认按钮：`确认合并进 main`（原型逐字）。
    ///
    /// ⚠️ 它用的是**目标分支名**（`main`），不是整条分支流向 —— 别顺手把
    /// `branchFlow` 传进来。
    public static func mergeConfirmAction(base: String) -> String {
        "确认合并进 \(base)"
    }

    /// 弹层底部提示（原型 `08-pr.js:121` 逐字）。
    ///
    /// ⚠️ 它也含一句承诺：`分支有冲突时引导到网页端处理` —— 成立的前提是
    /// 409 / 405 那两档真的各有一句提示（`mergeConflictToast` / `mergeNotMergeableToast`）。
    public static let mergeSheetHint = "Merge 走 API · 分支有冲突时引导到网页端处理"

    // MARK: - 提示

    /// 合并成功的提示：`已用 Squash 合并 #57 进 main`（原型 `08-pr.js:130-133` 逐字）。
    ///
    /// ⚠️ 三种方式的**短名**是原型给的、与单选标题**不一样**：
    /// `merge → Merge commit`、`squash → **Squash**`（不是 `Squash and merge`）、
    /// `rebase → **Rebase**`。照抄 —— 这是原型的 `{merge:'Merge commit',squash:'Squash',
    /// rebase:'Rebase'}` 那张表。
    public static func mergedToast(method: PullMergeMethod, number: Int, base: String) -> String {
        "已用 \(mergeMethodName(method)) 合并 #\(number) 进 \(base)"
    }

    /// 合并方式的**短名**（只在 `mergedToast` 里用；弹层上是 `mergeMethodOptions` 的标题）。
    public static func mergeMethodName(_ method: PullMergeMethod) -> String {
        switch method {
        case .merge: "Merge commit"
        case .squash: "Squash"
        case .rebase: "Rebase"
        }
    }

    /// 关闭成功的提示（原型 `08-pr.js:137` 逐字）。
    public static let closedToast = "已关闭 Pull Request，未合并"

    /// 重新打开成功的提示（原型 `08-pr.js:141` 逐字）。
    public static let reopenedToast = "已重新打开 Pull Request"

    /// **这个 PR 现在不能被合并**（405，或 200 但响应体的 `merged` 是 `false`）。
    ///
    /// ⚠️ **自拟（规格未给）**。§9.9 明写三种结局"必须分开说、不能折成一句『合并失败』"，
    /// 但 PRD 与原型都没给这两句的原文（原型的 `doMerge` 永远成功）。
    /// 这一句的措辞取自两处**已有**的写法：
    /// §9.9 对这一档的定性（「这个 PR 不能被合并」）+
    /// §5.3 的引导（`分支有冲突时引导到网页端处理`）。
    ///
    /// ⚠️ 它**不细分成因**（已合过 / draft / 有冲突）：客户端分不出来 ——
    /// `mergeable` 那个字段可能已过期故不取（`PullDetailDTO` 写了理由），
    /// 编一个成因就是猜。
    public static let mergeNotMergeableToast = "这个 PR 现在无法合并 · 请到 GitHub 网页端查看"

    /// **合并有冲突**（409）。
    ///
    /// ⚠️ **自拟（规格未给）**，同上：§9.9 要求 409 单独有一句，但没给原文。
    /// 与上一句的差别是"可以修"：冲突在网页端处理完再回来合并即可 ——
    /// 折成同一句会让用户以为这个 PR 就此不能合了。
    public static let mergeConflictToast = "合并有冲突 · 请到 GitHub 网页端处理后再试"
}

/// 合并弹层里那一行单选（PRD §5.3 三种方式，默认第一项）。
///
/// ## 为什么把"选项"做成数据而不是让视图写三遍
///
/// §5.3 的三行各自有标题 + 说明，而"默认选中第一项"是原型的行为
/// （`i===0 ? '<b class="mk">✓</b>' : ''`）。
/// 三行散在视图里时，"默认哪一项"就变成了一句 `index == 0` 的魔法判断；
/// 收成数组之后它是 `mergeMethodOptions[0]`，而**顺序**本身是那个默认可信的唯一理由。
public struct MergeMethodOption: Sendable, Hashable, Identifiable {

    public let method: PullMergeMethod

    /// 单选行的标题（§5.3 逐字）。
    public let title: String

    /// 标题下面那行灰字（§5.3 逐字）。
    public let detail: String

    public var id: String { method.rawValue }
}

extension PullCopy {

    /// 三种合并方式 —— **顺序即弹层里的顺序，也决定默认选中项**。
    ///
    /// 用的是 `.allCases` 的顺序（`merge` → `squash` → `rebase`），
    /// 与 §5.3 的书写顺序、原型的数组顺序**逐位一致**。
    ///
    /// ⚠️ 三种标题与说明**逐字**取自 §5.3 与原型 `08-pr.js:113`（两边完全一致）。
    public static let mergeMethodOptions: [MergeMethodOption] = PullMergeMethod.allCases.map { method in
        switch method {
        case .merge:
            MergeMethodOption(
                method: .merge,
                title: "Merge commit",
                detail: "保留全部分支提交历史"
            )
        case .squash:
            MergeMethodOption(
                method: .squash,
                title: "Squash and merge",
                detail: "压成一个提交，历史更干净"
            )
        case .rebase:
            MergeMethodOption(
                method: .rebase,
                title: "Rebase and merge",
                detail: "线性历史，不含合并节点"
            )
        }
    }

    /// 弹层打开时默认选中的方式 —— **第一项**（原型 `i===0`）。
    ///
    /// 写成 `mergeMethodOptions[0].method` 而不是 `.merge`：让"默认"与"顺序"
    /// 是同一件事。写成 `.merge` 的话，哪天把 `rebase` 挪到第一位，
    /// 弹层里亮着的仍然是 `Merge commit` —— 而它已经不在第一行了。
    public static var defaultMergeMethod: PullMergeMethod { mergeMethodOptions[0].method }
}
