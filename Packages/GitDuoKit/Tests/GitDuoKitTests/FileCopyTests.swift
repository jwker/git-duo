import Foundation
import Testing

@testable import GitDuoKit

/// 文件查看页（§4.5）那颗「⋯」菜单的文案 —— 2026-10-12 按用户要求新增。
///
/// ## 为什么单独一个文件
///
/// 与 `RepoCopyTests` 同一条理由：这一屏有**同类动作挨在一起**
/// （`复制路径` / `复制文件名` / `复制原文` 三项都复制，区别全在**字**上；
/// 加上 `编辑` / `重命名` / `删除文件` 一共六项同住一个菜单）——
/// 写岔了不会有任何报错，界面上也不会有任何异常，只有用户粘一次才知道。
///
/// ⚠️ 那三条通道**算出来的值**（`RepoPath.raw` / `RepoPath.displayName` / 正文）
/// 钉在 `RepoPathTests.rawAndDisplayNameAreDifferentThings()` 等处 —— 这里只管字。
///
/// ⚠️ **2026-10-13 改过一次住处**（走查第 62 条）：这六项从"底部操作行 + 面包屑右端那颗"
/// 搬进了**右上角那颗「⋯」**（用户要求）⇒ 菜单标签与旧的 `crumbMenuAccessibilityLabel`
/// 是两码事，下面第三节把这两条的差别钉住。
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
    /// 这一屏三颗"复制"（`复制原文` / 路径 / 文件名）落在同一个提示条上 ——
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

    /// ⚠️ **六项的字两两不同**（2026-10-13 新增）。
    ///
    /// 它们同住一个菜单，撞字就是"两个不同的动作长得一模一样" ——
    /// 尤其 `复制路径` / `复制文件名` / `复制原文` 三项差着两个字，
    /// 正是那种"改一处、另一处忘了"最容易发生的形状。
    ///
    /// ⚠️ 这里**只收菜单项**：`取消` / `删除文件`（确认层那颗）是别处的字，
    /// 与菜单项同字是允许的（不同屏、不并排）。
    @Test("⚠️ 菜单六项的字两两不同 —— 同住一个菜单，撞字就是两个动作长得一样")
    func menuItemsAreMutuallyDistinct() {
        let items = [
            FileCopy.editAction,
            FileCopy.renameAction,
            FileCopy.copyPathAction,
            FileCopy.copyFileNameAction,
            FileCopy.rawAction,
            FileCopy.deleteAction,
        ]

        #expect(Set(items).count == items.count)
        // 最容易混的一对：一个给整条路径、一个只给最后一段。
        #expect(FileCopy.copyPathAction != FileCopy.copyFileNameAction)
        // 2026-10-13 从 `Raw` 改成中文动宾短语 —— 三个"复制"并排时才是一套语言。
        #expect(FileCopy.rawAction == "复制原文")
    }

    /// ⚠️ 菜单标签说的是**菜单**，不是里面某一项的动作。
    ///
    /// 这一屏的菜单里躺着**六个**动作（编辑 / 重命名 / 删除 + 三个复制），
    /// 标签若写成其中任何一项的字，读屏用户听到的是"复制路径"、按下去却弹出六项。
    ///
    /// ⚠️ **2026-10-13 它的名字与职责一起变了**（走查第 62 条）：上一版叫
    /// `文件路径操作菜单` —— 那时菜单里确实只有路径那两件，而它挂在**面包屑行右端**；
    /// 现在一屏只剩右上角那一颗、里面是这一屏的全部操作 ⇒ 名字必须跟上
    /// （读屏用户听到"路径操作"、里面却躺着删除，是比不说更糟的）。
    @Test("⚠️ 「⋯」的读屏标签点明是**文件操作菜单**，且不等于菜单里任何一项的动作名")
    func menuLabelIsAboutTheMenu() {
        let items = [
            FileCopy.editAction,
            FileCopy.renameAction,
            FileCopy.copyPathAction,
            FileCopy.copyFileNameAction,
            FileCopy.rawAction,
            FileCopy.deleteAction,
        ]

        #expect(FileCopy.operationsMenuAccessibilityLabel == "文件操作菜单")
        #expect(!items.contains(FileCopy.operationsMenuAccessibilityLabel))

        // ⚠️ 与代码页那颗**有意不同名**：两颗菜单现在**位置与控件逐字相同**
        //    （都是导航栏右上角 + 系统原生 `Menu`），差别只剩管的**对象** ——
        //    一颗管这个文件、一颗管这一层目录（`复制路径` / `添加文件`）。
        //    所以两个标签可以同构，但**不能同值**：读屏里两颗若读成同一句，
        //    用户在"文件页"和"代码页"之间就分不出自己站在哪一页。
        #expect(FileCopy.operationsMenuAccessibilityLabel
                != RepoCopy.operationsMenuAccessibilityLabel)
    }
}
