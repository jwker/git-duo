import Foundation

/// 「上传图片」那一屏的**文案**（2026-10-23 定）。
///
/// ## ⚠️ 为什么单独立一份
///
/// 上传这个入口是**全局**的（悬浮按钮每个页面都有），它说出的每一句话
/// 都会在很多个界面上出现 —— 措辞散在各处的那天，同一件事会出现两种说法。
/// 于是文案收在这里（与 `RepoCopy` / `CommitSheetCopy` 同一分工）。
public enum UploadImageCopy {

    /// 悬浮按钮的读屏标签。
    ///
    /// ⚠️ 按钮只有图标 ⇒ 读屏必须念得出它是干什么的（`FloatingActionButton` 的说明）。
    public static let floatingButtonAccessibilityLabel = "上传图片"

    /// 弹层标题。
    public static let sheetTitle = "上传图片"

    /// 目标那一行的标题。
    public static let targetSectionTitle = "目标"

    /// 还没选目标时那一行显示的字。
    public static let noTarget = "尚未选择目标"

    /// 还没选目标时那一行的副标题。
    public static let noTargetHint = "选一个仓库与目录"

    /// 目标摘要行下面的提示（告诉用户"点上面那行可以换"）。
    public static let changeTargetHint = "点上面这一行可以换一个仓库与目录。"

    /// 图片那一组的标题。
    public static let imageSectionTitle = "图片"

    /// 提交信息那一组的标题。
    public static let commitSectionTitle = "提交信息"

    /// 选仓库那一屏的标题。
    public static let chooseRepositoryTitle = "选仓库"

    /// 选目录那一屏的标题。
    public static let chooseDirectoryTitle = "选目录"

    /// 选目录那一屏的说明（目录相对仓库根；新目录随文件一起建）。
    public static let directoryHint = "目录相对仓库根；写进还不存在的目录会随文件一起建出来。"

    /// 选仓库那一屏的说明（只列可写的仓库）。
    public static let writableOnlyHint = "只列有 push 权限的仓库。"

    /// 压缩 / 转码那一行的说明。
    ///
    /// ⚠️ 这一句要跟着 `maxContentBytes` 与白名单走 —— 数字变了它也要改
    /// （与 `RepoCopy.addFileSheetHint` 同一份口径）。
    public static let compressionHint = "超过 1 MB 的图片会自动压缩；网页端显示不出来的格式会自动转换。"

    /// 上传成功后的兜底提示（弹层被划走时也会看到它）。
    ///
    /// - Parameter target: 落到哪儿了 —— **必须写清仓库与目录**：
    ///   上传是全局入口触发的写操作，用户最容易犯的错就是"以为传到了别处"。
    public static func uploadedToast(target: UploadTarget) -> String {
        "已上传到 \(target.fullName) / \(target.directory.isRoot ? "" : target.directory.raw)"
    }

    /// 成功态的标题。
    public static let successTitle = "已上传"

    /// 成功态里那串路径旁边的按钮。
    public static let copyPath = "复制路径"

    /// 复制完成（按钮上那一行字，不弹 Toast —— 按钮就在用户手指底下）。
    public static let copied = "已复制"

    /// 成功态的次要动作。
    public static let uploadAnother = "继续上传"

    /// 成功态的收尾动作。
    public static let done = "完成"
}
