import Foundation

/// 文件查看页（§4.5）的可见文案。
///
/// 与 `SearchCopy` 同源：可见契约放领域层，才能被单测钉住。
public enum FileCopy {

    // MARK: - 操作菜单（右上角那颗「⋯」，2026-10-13 由底部操作行搬来 —— 走查第 62 条）

    /// 自己的仓库：`编辑`（→ 编辑器 §4.6）。
    ///
    /// ⚠️ **切片 8.4 起可点**。仍然不可点的只剩两档，且理由是**不同的两句话**
    /// （`EditorCopy.editHint(for:)` 是唯一落点）：
    /// - 文本**超过 1MB** —— 能看（走 raw）但不能改（决策 #54 的边界、偏差 32）；
    /// - **图片** —— 编辑器是文本编辑器。
    ///
    /// ⚠️ **2026-10-13 起这两档的形态是"菜单里的灰项"**，不再是"画出来但按不动的按钮"：
    /// 原型的操作行在页面里、可以用 `allowsHitTesting(false)` 做成"看起来一样但按不动"；
    /// 菜单项只能靠 `.disabled`（系统灰）表达不可用（决策 #51 那条"不用灰"在这里字面分岔，
    /// 原委见 `FileView` 的类型说明）。
    public static let editAction = "编辑"

    /// `重命名`（PRD §5.15 逐字）。
    ///
    /// ⚠️ **2026-10-13 起它是右上角菜单里的一项**：那张「文件操作」弹层被撤掉了
    /// （用户要求"把底部操作按钮都放进菜单"，走查第 62 条）—— 点它仍然打开 §5.16。
    public static let renameAction = "重命名"

    /// `删除文件`（PRD §5.15 逐字）。⚠️ 危险色（菜单里走 `Button(role: .destructive)`）。
    public static let deleteAction = "删除文件"

    /// **复制原文** —— 原型那一颗 `Raw` 按钮的文案（2026-10-13 改）。
    ///
    /// ## ⚠️ 它**当真做**（决策 #51 里两处例外之一）
    ///
    /// 原型演的正是"复制原文到剪贴板"（`toast('已复制 Raw 内容')`），
    /// 而 PRD 把它标 ⏳ 只说明"没细化"，不构成反对 ——
    /// 按事实优先级（原型 > TECH_SPEC > PRD），以原型的行为为准。
    ///
    /// ⚠️ **零请求**：正文已经在手上（`FileContent.text`），复制是纯本地操作。
    ///
    /// ⚠️ **2026-10-13 从 `Raw` 改成 `复制原文`**（走查第 62 条）：原型那颗按钮的逐字
    /// 是裸 `Raw`（GitHub 自己的术语），而它搬进菜单之后要跟 `复制路径` / `复制文件名`
    /// **并排**住在一起 —— 三个同族动作里混一个英文单词，读起来是两套语言。
    /// ⚠️ **成功那句 toast 一个字没动**（仍是原型逐字 `已复制 Raw 内容`）：
    /// 改的是菜单项的**动词**，不是这套功能的说法。
    public static let rawAction = "复制原文"

    // MARK: - 底部说明（PRD §4.5 表）

    /// 自己的仓库的页脚（原型逐字）。
    public static let ownFooter = "保存即一次 commit · 提交面板可选当前分支或新分支 + PR"

    /// 他人仓库的页脚（原型逐字）。
    public static let readOnlyFooter = "只读浏览 · 他人仓库文件"

    // ⚠️ **2026-10-13 删掉了 `fileOperationsSheetTitle`**（原本是 `文件操作 · {文件名}`，
    //    那张「文件操作」弹层的标题）。用户要求"把底部操作按钮都放进「⋯」菜单"
    //    （走查第 62 条）⇒ `重命名` / `删除文件` 成了菜单里两项、**直接**换成各自的确认层
    //    ⇒ 那张中间弹层（`FileOperationsSheet.swift`）整个删除，这个常量失去唯一消费端。
    //
    // ⚠️ **同日删掉的还有四条**（`forkToEditAction` / `forkToEditUnavailableHint` /
    //    `historyAction` / `historyUnavailableHint`）：用户在"照常可点但点了给说明 /
    //    由系统灰掉 / **不放进菜单**"三档里选了最后一条 ⇒ 界面上一处都不再提示
    //    `历史`（⏳）与 `Fork 后可编辑`（Fork 没做）这两个入口。
    //    失去唯一消费端的常量留着不是"以后可能用得上"，而是让下一个读的人先要判断
    //    "它是不是还在用"（同 `GitHubIcon` 里那条"有意没有"的处置）。

    // MARK: - §5.16 重命名弹层（切片 8 新增，决策 #66）

    /// 弹层标题（PRD §5.16 逐字）。
    public static let renameSheetTitle = "重命名文件"

    /// 说明行（PRD §5.16 逐字）。
    ///
    /// ⚠️ 它承诺"原路径将不再存在" —— 而两步里的第二步（删旧路径）**可能失败**
    /// （那时两个都在）。这句话不是假话（正常路径下它成立），但接口失败时
    /// 必须由 `renamePartiallyMovedToast` 主动纠正，不能只靠这一句。
    public static let renameSheetHint = "重命名会移动文件 · 原路径将不再存在"

    /// 确认按钮（PRD §5.16 逐字）。
    public static let renameConfirmAction = "保存"

    /// 路径为空（PRD §5.16 逐字）。
    public static let renameEmptyHint = "先输入文件路径"

    /// 目标路径上已有文件（PRD §5.16 逐字）。
    ///
    /// ⚠️ 与 `CommitSheetCopy.destinationExistsHint`（上传那一侧）**措辞不同**，
    /// 这是有意的 —— 两句话分别由 §5.16 与 §5.8 定，各自带着自己的下一步。
    public static let renameDestinationExistsHint = "该路径上已有文件"

    /// 某一级路径不合法（**规格未给**，自拟）。
    ///
    /// 它拦的是 `.` / `..` 与空段（`a//b`）—— 那一串在服务端是**另一条路径**，
    /// 而界面上看起来只是想改个名（判据见 `RepoPath.resolveRenameDestination`）。
    /// 提示里点名那一级：用户需要知道改哪里。
    public static func renameInvalidPathHint(component: String) -> String {
        "路径里的「\(component)」不是有效的一级，请去掉它"
    }

    /// 两步都成了（PRD §5.16 逐字）。
    public static func renamedToast(newPath: String) -> String {
        "已重命名为 \(newPath)"
    }

    /// ⚠️ **第一步成了、第二步失败**（PRD §5.16 逐字）—— 这一刻仓库里**两个文件都在**。
    ///
    /// 含糊成"重命名失败"会让用户以为什么都没变（他可能就此不管，
    /// 而仓库里多了一份副本）—— 决策 #68② 点名的正是这一处。
    public static let renamePartiallyMovedToast = "新路径已写入，原路径仍在"

    /// 源文件已经不在了（**规格未给**，自拟）。
    ///
    /// ⚠️ 与 `.notWritable` 分开：一个说"它没了"，一个说"它在，但这条通道做不了"。
    /// 合成一句会把一个**还在那里**的文件说成"已不存在"，用户会以为数据没了。
    public static let renameSourceGoneHint = "这个文件已经不在了，请刷新后重试"

    /// 源文件的内容拿不到 ⇒ 写不出新路径（>1MB / 二进制 / 解不出编码）。
    ///
    /// ⚠️ **规格未给**（自拟）。必须说清"它还在、只是这里做不了"，
    /// 并给网页端出口 —— 否则用户会以为这个文件坏了。
    public static let renameSourceNotWritableHint =
        "这个文件太大或格式不支持，App 内无法重命名，请到 GitHub 网页端处理"

    // MARK: - §5.17 删除文件确认（切片 8 新增，决策 #66）

    /// 弹层标题：`删除「{文件名}」？`（PRD §5.17 逐字）。
    public static func deleteSheetTitle(fileName: String) -> String {
        "删除「\(fileName)」？"
    }

    /// 说明（PRD §5.17 逐字）。
    ///
    /// ⚠️ 它先说"会立即生成一次提交" —— 这不是修辞：Contents 的删除**就是一次提交**，
    /// 所以"本机不做二次备份"这句才有意义（用户可以在网页端的提交历史里找回）。
    public static func deleteSheetHint(branch: String) -> String {
        "删除会立即在 \(branch) 上生成一次提交，本机不做二次备份。"
    }

    /// 确认按钮（PRD §5.17 逐字）。⚠️ 红底。
    public static let deleteConfirmAction = "删除文件"

    /// 警告行（PRD §5.17 逐字）。
    public static let deleteWarning = "此操作不可撤销（可在 GitHub 网页端的提交历史里找回）"

    /// 删除成功（PRD §5.17 逐字）。
    public static func deletedToast(fileName: String) -> String {
        "已删除 \(fileName)"
    }

    /// ⚠️ 现取版本标识时发现文件已不在（PRD §5.17 逐字）。
    ///
    /// **不报"删除失败"** —— 用户想要的结果本来就已经成立了。
    public static let alreadyGoneHint = "该文件已不存在"

    // MARK: - 通用取消

    /// `取消`（PRD §5.16 / §5.17 逐字）。
    ///
    /// ⚠️ 它与 `BranchCopy.cancelAction` **是同一个词、两个落点** ——
    /// 这里不跨命名空间引用（那样会让"文件操作的取消"悄悄跟着分支页的改动走）。
    /// 一个词的两个落点不会漂（它没有别的说法），而**跨模块的隐式依赖会**。
    public static let cancelAction = "取消"

    // MARK: - 提示

    /// 复制成功（原型 `onclick` 里那句 toast 逐字）。
    public static let rawCopiedToast = "已复制 Raw 内容"

    /// 没有可复制的正文时的提示。（图片与不支持预览的文件没有"原文"可复制 ——
    /// 那种情况下 `复制原文` 这一项**不出现**，所以这句只在极端时序下兜底。）
    public static let rawUnavailableToast = "这个文件没有可复制的文本内容"

    /// 复制失败（剪贴板被系统拒绝时的兜底）。
    public static let rawCopyFailedToast = "复制失败，请长按选择文本"

    // MARK: - 复制路径 / 复制文件名（2026-10-12 新增，按用户要求）

    /// 菜单第一项的动作名：`复制路径`。
    ///
    /// ⚠️ **原型里没有这个控件**（`REVIEW-CHECKLIST` 第 56 条：按用户要求新增）——
    /// 这一屏原型 `.crumb` 里只有 `文件名` 与 `分支` 两个 `Text`，右端没有任何动作位。
    /// ⚠️ 它出生在 `crumb` 行右端那颗「⋯」里，**2026-10-13 起住在右上角那颗「⋯」**里
    /// （第 62 条：一屏两颗同名图标没有道理，用户裁定并进右上角）。
    ///
    /// ⚠️ **它与 `复制原文` 不是一回事**：那一项复制的是**文件内容**
    /// （决策 #51 的两处例外之一），这一项复制的是**文件在仓库里的整个相对路径**
    /// （含文件名，形如 `Packages/GitDuoKit/Sources/RepoPath.swift`）。
    ///
    /// ⚠️ 与 `RepoCopy.copyPathAction` 是**同一个词、两个落点**（同 `cancelAction` 的处置：
    /// 不跨命名空间引用）。
    public static let copyPathAction = "复制路径"

    /// 菜单第二项的动作名：`复制文件名`。
    ///
    /// ⚠️ 它给的是**只有最后一段**（`RepoPath.swift`），一个目录都不带 ——
    /// 与上面那一项**必须能一眼分开**：两者住在同一个菜单里，
    /// 而"路径"与"文件名"在文字上只差两个字。
    ///
    /// ⚠️ 2026-10-12 追加（用户原话「另一个是复制文件名」）：在那之前这一屏
    /// 只有一颗裸图标按钮，它复制的是**整条相对路径**。
    public static let copyFileNameAction = "复制文件名"

    /// 复制成功。⚠️ 与 `RepoCopy.pathCopiedToast` 逐字相同 —— 两处复制出来的都是路径，
    /// 而"从哪一页复制的"对用户没有第二句话要说。
    public static let pathCopiedToast = "已复制路径"

    /// 复制**文件名**成功。
    ///
    /// ⚠️ 与前一句**必须不同**：这一项给的是只有最后一段的名字，
    /// 说「已复制路径」会让用户以为剪贴板里躺着整条路径（粘到终端里就少一截目录）。
    public static let fileNameCopiedToast = "已复制文件名"

    /// `crumb` 行右端那颗「⋯」的读屏标签 —— **2026-10-13 起改用 `operationsMenuAccessibilityLabel`**。
    ///
    /// ⚠️ 那一颗（`文件路径操作菜单`）只活了一天：它长在面包屑行右端、管"复制路径 / 复制文件名"，
    /// 而次日用户要求把底部操作行也收进「⋯」并摆到右上角 ⇒ 一屏两颗同名图标没有道理，
    /// 用户裁定**并进右上角那颗**（走查第 62 条）⇒ 这里只留下面那一枚标签。
    ///
    /// ⚠️ **有意不保留这个常量**（它已无任何消费端）：它当初的用处是与同屏那颗
    /// `Raw` 分开（读屏里两颗都读成"复制"就分不出哪一颗），而那两颗现在**同在一个菜单里**、
    /// 各自的标题就是区分。

    /// 右上角那颗「⋯」的读屏标签 —— 这一屏的所有动作都在它里面。
    ///
    /// ⚠️ **2026-10-13 从 `文件路径操作菜单` 改成 `文件操作菜单`**：菜单的职责变了
    /// （从"只管路径复制"扩到"这一屏的全部操作"），名字必须跟着变 ——
    /// 否则读屏用户听到的是"路径操作"，而里面躺着编辑 / 重命名 / 删除。
    ///
    /// ⚠️ 它说的是**菜单本身**（按下去会弹出什么），不是里面某一项的动作。
    /// 与 `RepoCopy.operationsMenuAccessibilityLabel` 同一条处置
    /// （那边那颗是"目录操作菜单"，**两边有意不同名** —— 两个菜单管的**对象**不同：
    /// 一颗管这个文件，一颗管这一层目录。2026-10-14 那边也搬到了导航栏右上角，
    /// 位置与控件与本颗逐字相同，差别只剩"管的是谁"）。
    public static let operationsMenuAccessibilityLabel = "文件操作菜单"

    // MARK: - 不支持预览（决策 #54 的第四档）

    /// 标题（**规格未给**，按 §8.5 空态/失败态的句式拟）。
    public static let unsupportedTitle = "无法预览这个文件"

    /// 二进制 / 不认识的格式。
    public static let unsupportedBinaryHint = "这个格式是二进制的，App 不下载它的内容"

    /// 图片超过上限。
    ///
    /// ⚠️ 把**具体上限**写进去（而不是笼统的"图片太大"）：用户据此才知道
    /// "换一张小图可以看"、或者"这个文件在 App 里永远看不了"。
    /// 上限取自 `FilePreviewKind.maxImageBytes`，改那个常量这句话跟着变。
    public static var unsupportedImageHint: String {
        "图片超过 \(megabytes(FilePreviewKind.maxImageBytes))MB，App 不下载它"
    }

    /// 出口按钮（PRD §4.5「给一个跳网页端的出口」）。
    public static let openInBrowserAction = "在 GitHub 上打开"

    /// **下载了、但解不出文本**（GBK / Big5，或扩展名与内容不符）。
    ///
    /// ⚠️ **规格未给，待评审**（自拟）。它与上面两条**必须分开**，
    /// 因为上面那句 `unsupportedBinaryHint` 明说「App **不下载**它的内容」——
    /// 而对这一档我们**刚刚下载了它**。照那句说就是**假话**，
    /// 且用户会以为"再试一次也许能好"（其实每次都会得到同一堆字节）。
    public static let undecodableTextHint = "这个文件的编码 App 不认识，无法显示为文本"

    /// 把字节数说成整数 MB（向上取整 —— 说"4.7MB"对用户没有意义，
    /// 而说"5MB"能让"我的图片是不是太大了"有一个可判断的答案）。
    private static func megabytes(_ bytes: Int) -> Int {
        max(1, Int((Double(bytes) / 1_000_000).rounded(.up)))
    }
}
