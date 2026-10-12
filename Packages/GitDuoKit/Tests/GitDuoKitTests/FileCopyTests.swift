import Foundation
import Testing

@testable import GitDuoKit

/// 文件查看页（§4.5）那颗「⋯」菜单的文案 —— 2026-10-12 按用户要求新增。
///
/// ## 为什么单独一个文件
///
/// 与 `RepoCopyTests` 同一条理由：这一屏有**同类动作挨在一起**（`Raw` 复制内容、
/// 菜单复制路径 / 复制文件名），而它们的区别全在**字**上 ——
/// 写岔了不会有任何报错，界面上也不会有任何异常，只有用户粘一次才知道。
///
/// ⚠️ 那两条通道**算出来的值**（`RepoPath.raw` / `RepoPath.displayName`）
/// 钉在 `RepoPathTests.rawAndDisplayNameAreDifferentThings()` —— 这里只管字。
@Suite("文件页规则 · 复制（§4.5，2026-10-12 按用户要求新增）")
struct FileCopyTests {

    /// `REVIEW-CHECKLIST` 第 56 条：用户要求给文件页也加复制按钮，
    /// 并把菜单做成两项（复制路径 / 复制文件名）。
    @Test("菜单两项：动作名与 toast")
    func copyMenuItemCopy() {
        #expect(FileCopy.copyPathAction == "复制路径")
        #expect(FileCopy.copyFileNameAction == "复制文件名")
        #expect(FileCopy.pathCopiedToast == "已复制路径")
        #expect(FileCopy.fileNameCopiedToast == "已复制文件名")
    }

    /// ⚠️ 三句 toast **两两不同**。
    ///
    /// 这一屏三颗"复制"（`Raw` / 路径 / 文件名）落在同一个提示条上 ——
    /// 若有两句写成了同一串字，用户按下第二项之后**没法从提示里知道**
    /// 剪贴板里躺的是哪一样（"已复制路径"与"已复制文件名"差着一整条目录）。
    @Test("⚠️ 三句 toast 两两不同 —— 同一句会让用户分不出复制了什么")
    func toastsStayDistinct() {
        let toasts = [
            FileCopy.rawCopiedToast,
            FileCopy.pathCopiedToast,
            FileCopy.fileNameCopiedToast
        ]

        #expect(Set(toasts).count == toasts.count)
        // 最容易被"顺手统一"掉的一对：两项都在同一个菜单里、都给路径。
        #expect(FileCopy.pathCopiedToast != FileCopy.fileNameCopiedToast)
    }

    /// ⚠️ 菜单标签说的是**菜单**，不是里面那一项的动作。
    ///
    /// 它必须能与同屏那颗 `Raw`（复制内容）分开 —— 读屏里两颗都读成"复制"
    /// 就分不出哪一颗是哪一颗了（同 `RepoCopy.breadcrumbMenuAccessibilityLabel` 的处置）。
    @Test("⚠️ 「⋯」的读屏标签点明是**路径**、且不等于菜单里那一项的动作名")
    func menuLabelIsAboutTheMenu() {
        #expect(FileCopy.crumbMenuAccessibilityLabel != FileCopy.copyPathAction)
        #expect(FileCopy.crumbMenuAccessibilityLabel != FileCopy.copyFileNameAction)
        // 点名"路径"这两个字 —— 它与 `Raw` 的区别正是这一点。
        #expect(FileCopy.crumbMenuAccessibilityLabel.contains("路径"))
    }
}
