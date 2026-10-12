import Foundation
import Testing

@testable import GitDuoKit

/// 仓库详情页（§4.4）里那条**会算出一个值**的规则 —— 目前只有一条：
/// 「复制路径」写进剪贴板的内容。
///
/// ## 为什么单独一个文件
///
/// `RepoCopy` 绝大多数成员是**纯文案**（写错了眼睛能看出来、`grep` 也查得到），
/// 不值得逐条断言。这里只钉住那条**算出来的**规则 ——
/// 它写错的样子不是"文案别扭"，而是"用户粘出来一片空白"，而且没有任何提示。
@Suite("仓库页规则 · 复制路径（§4.4，2026-10-12 按用户要求新增）")
struct RepoCopyTests {

    /// `REVIEW-CHECKLIST` 第 56 条：用户要求给面包屑路径加复制按钮。
    ///
    /// ⚠️ 这一条钉的是**根目录那个兜底** —— 它是一次"用户明知形态不统一仍要"的裁定，
    /// 最容易在下次重构时被"统一"掉（统一成空串 = 复制出一片空白）。
    @Test("⚠️ 复制的是**仓库内相对路径**；根目录回落到**仓库全名**（不是空串）")
    func clipboardPathFallsBackToFullNameAtRoot() {
        let fullName = "my-git/gitduo"

        #expect(RepoCopy.clipboardPath(for: .root, fullName: fullName) == fullName)
        #expect(RepoCopy.clipboardPath(for: RepoPath(path: "docs"), fullName: fullName) == "docs")
        #expect(
            RepoCopy.clipboardPath(
                for: RepoPath(path: "Packages/GitDuoKit/Sources"), fullName: fullName
            ) == "Packages/GitDuoKit/Sources"
        )

        // ⚠️ 子目录那一档**不带仓库全名** —— 带前缀的方案（`my-git/gitduo/docs`）
        //    在三个候选里，用户选的是"仓库内相对路径"。
        #expect(
            !RepoCopy.clipboardPath(for: RepoPath(path: "docs"), fullName: fullName)
                .contains(fullName)
        )
    }

    @Test("⚠️ 根目录那一档**永远不是空串** —— 那正是兜底存在的理由")
    func rootIsNeverEmpty() {
        #expect(!RepoCopy.clipboardPath(for: .root, fullName: "my-git/gitduo").isEmpty)
        // 只钉"非空"。校验仓库全名的形状（`owner/repo`）是上游的事，
        // 不是这条规则的职责 —— 把两件事混一起，改一处会撞另一处。
        #expect(!RepoCopy.clipboardPath(for: .root, fullName: "a/b").isEmpty)
    }

    @Test("两条文案：动作名与 toast")
    func copyPathCopy() {
        #expect(RepoCopy.copyPathAction == "复制路径")
        #expect(RepoCopy.pathCopiedToast == "已复制路径")
    }

    /// ⚠️ 两页**同一个词、两个落点**（沿 `FileCopy.cancelAction` 的处置：不跨命名空间引用）。
    ///
    /// 既然是两处各写一遍，就必然有"只改了一处"的风险 —— 而这两句话在两个页面上
    /// 指的是同一件事，写岔了不会有任何报错。这条断言是唯一能钉住它的东西。
    @Test("⚠️ 与文件页那两句**逐字相同**（两处复制出来的都是路径）")
    func copyPathCopyMatchesFileView() {
        #expect(RepoCopy.copyPathAction == FileCopy.copyPathAction)
        #expect(RepoCopy.pathCopiedToast == FileCopy.pathCopiedToast)
    }
}
