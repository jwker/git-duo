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

    /// `更多`（重命名 / 删除，原型逐字）——属切片 8，画出但不可点。
    public static let moreAction = "更多"

    // MARK: - 不可点按钮的读屏提示（决策 #51）

    /// ⚠️ 这四条是**决策 #51 要求的那句 hint**，不是可选的装饰：
    /// 一颗点不动的按钮若不解释，读屏用户只会反复点它 —— 而这条路上没有任何反馈。
    ///
    /// 每一条都必须说**为什么**点不了，且**四条各不相同** ——
    /// 合成一句"暂不可用"会让"下一片就做"与"本期根本不做"看起来是同一件事，
    /// 而这两者对用户该有的期待完全不同。
    public static let editUnavailableHint = "编辑在切片 8 落地，当前版本暂不可用"

    /// ⚠️ `Fork 后可编辑` 的障碍**不是**这个按钮本身没做，而是 Fork 没做
    /// （原型点它只给一句演示 toast）。所以说的是"先 Fork"，而不是"编辑没做"。
    public static let forkToEditUnavailableHint = "Fork 后才能编辑，而 Fork 功能待细化，当前版本不可用"

    /// 历史指向"这个文件的提交历史"这一独立页面，PRD §4.5 标 ⏳ ⇒ 没有切片认领它。
    public static let historyUnavailableHint = "这个文件的提交历史尚未落地，当前版本暂不可用"

    public static let moreUnavailableHint = "重命名与删除在切片 8 落地，当前版本暂不可用"

    // MARK: - 底部说明（PRD §4.5 表）

    /// 自己的仓库的页脚（原型逐字）。
    public static let ownFooter = "保存即一次 commit · 提交面板可选当前分支或新分支 + PR"

    /// 他人仓库的页脚（原型逐字）。
    public static let readOnlyFooter = "只读浏览 · 他人仓库文件"

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
