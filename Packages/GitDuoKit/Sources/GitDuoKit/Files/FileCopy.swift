import Foundation

/// 文件查看页（§4.5）的可见文案。
///
/// 与 `SearchCopy` 同源：可见契约放领域层，才能被单测钉住。
public enum FileCopy {

    // MARK: - 操作按钮（PRD §4.5 的权限差异表）

    /// 自己的仓库：`编辑`（→ 编辑器 §4.6）。
    ///
    /// ⚠️ 属切片 8 ⇒ 本片**画出但不可点**（决策 #51）。
    public static let editAction = "编辑"

    /// 他人仓库的替代按钮（原型逐字，含 `⑂`）。
    ///
    /// ⚠️ 同样不可点。原型点它会给一句 `演示：Fork 该仓库后即可编辑` ——
    /// 那是原型的演示语，不是产品文案（PRD §4.5 把它标为 ⏳）。
    public static let forkToEditAction = "⑂ Fork 后可编辑"

    /// `历史`（原型逐字）。
    ///
    /// ⚠️ PRD §4.5 标 ⏳（它指向"这个文件的提交历史"这一独立页面，
    /// 本期没有做它的切片）⇒ 画出但不可点。
    public static let historyAction = "历史"

    /// `Raw`（原型逐字）。
    ///
    /// ## ⚠️ 它**当真做**（决策 #51 里两处例外之一）
    ///
    /// 原型演的正是"复制原文到剪贴板"（`toast('已复制 Raw 内容')`），
    /// 而 PRD 把它标 ⏳ 只说明"没细化"，不构成反对 ——
    /// 按事实优先级（原型 > TECH_SPEC > PRD），以原型的行为为准。
    ///
    /// 零请求：正文已经在手上（`FileContent.text`），复制是纯本地操作。
    public static let rawAction = "Raw"

    /// `更多`（重命名 / 删除，原型逐字）。
    ///
    /// ⚠️ **切片 8 起它可点了**（用户 2026-10-08 裁定「一起做」）——
    /// 三个弹层规格见 §5.15–§5.17，本文件下面那三节就是它们的文案。
    /// 8.4 接线之前，`FileView` 仍然按 `moreUnavailableHint` 画出不可点的形态。
    public static let moreAction = "更多"

    // MARK: - 不可点按钮的读屏提示（决策 #51）

    /// ⚠️ 这四条是**决策 #51 要求的那句 hint**，不是可选的装饰：
    /// 一颗点不动的按钮若不解释，读屏用户只会反复点它 —— 而这条路上没有任何反馈。
    ///
    /// 每一条都必须说**为什么**点不了，且**四条各不相同** ——
    /// 合成一句"暂不可用"会让"下一片就做"与"本期根本不做"看起来是同一件事，
    /// 而这两者对用户该有的期待完全不同。
    /// ⚠️ 8.4 起这一条**只用于"文件 >1MB"那一档**（决策 #54 的边界、
    /// `REVIEW-CHECKLIST` 偏差 32）—— 普通文件上它可点了。
    /// 那句话改由 `EditorCopy.editTooLargeHint` 说（它说的是"太大"，不是"还没做"）。
    /// **8.4 接线时这张常量连同本行说明一起删掉。**
    public static let editUnavailableHint = "编辑在切片 8 落地，当前版本暂不可用"

    /// ⚠️ `Fork 后可编辑` 的障碍**不是**这个按钮本身没做，而是 Fork 没做
    /// （原型点它只给一句演示 toast）。所以说的是"先 Fork"，而不是"编辑没做"。
    public static let forkToEditUnavailableHint = "Fork 后才能编辑，而 Fork 功能待细化，当前版本不可用"

    /// 历史指向"这个文件的提交历史"这一独立页面，PRD §4.5 标 ⏳ ⇒ 没有切片认领它。
    public static let historyUnavailableHint = "这个文件的提交历史尚未落地，当前版本暂不可用"

    /// ⚠️ **8.4 起它变成一条死常量**（「更多」成为了可点按钮，没有"不可点"这一档了）
    /// —— 接线时**连同本行说明一起删掉**。留着它会让"这颗按钮还不能点"
    /// 在代码里看起来仍然成立。
    public static let moreUnavailableHint = "重命名与删除在切片 8 落地，当前版本暂不可用"

    // MARK: - 底部说明（PRD §4.5 表）

    /// 自己的仓库的页脚（原型逐字）。
    public static let ownFooter = "保存即一次 commit · 提交面板可选当前分支或新分支 + PR"

    /// 他人仓库的页脚（原型逐字）。
    public static let readOnlyFooter = "只读浏览 · 他人仓库文件"

    // MARK: - §5.15 文件操作菜单（切片 8 新增，决策 #66）

    /// 弹层标题：`文件操作 · {文件名}`（PRD §5.15 逐字）。
    ///
    /// ⚠️ 带**文件名**而不是完整路径：这一屏的上下文是"我正在看哪个文件"，
    /// 而路径可能很长（`Sources/GitDuoKit/Features/Repo/Views/FileView.swift`）——
    /// 标题放不下它，且用户此刻不需要在两级目录之间做区分。
    public static func fileOperationsSheetTitle(fileName: String) -> String {
        "文件操作 · \(fileName)"
    }

    /// `重命名`（PRD §5.15 逐字）。
    public static let renameAction = "重命名"

    /// `删除文件`（PRD §5.15 逐字）。⚠️ 危险色（`ActionButton.Style.destructive`）。
    public static let deleteAction = "删除文件"

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
    /// 那种情况下 `Raw` 按钮**不出现**，所以这句只在极端时序下兜底。）
    public static let rawUnavailableToast = "这个文件没有可复制的文本内容"

    /// 复制失败（剪贴板被系统拒绝时的兜底）。
    public static let rawCopyFailedToast = "复制失败，请长按选择文本"

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
