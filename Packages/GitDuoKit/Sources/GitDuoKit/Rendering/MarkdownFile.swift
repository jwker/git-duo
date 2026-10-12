import Foundation

/// 「这个文件在文件页要不要按 markdown 渲染」+ 把它装配成可渲染的文档
/// （2026-10-12 新增，按用户要求 —— `REVIEW-CHECKLIST` **第 57 条**）。
///
/// ## ⚠️ 它是在原型与 PRD **都没有**的情况下新增的
///
/// 原型 `SCR.fileView` 的正文写死成 `<div class="markdown"><pre><code>…`（一个代码块），
/// 演示数据是一个 **Swift 文件** —— 也就是说它**一次都没展示过"打开一个 `.md` 文件"**。
/// `PRD §4.5` 第 2 条同样只写「代码块（带语法着色的源码）」。
/// ⇒ 文件页渲染 markdown 属**用户要求新增**，不是实现走样（与第 56 条同一性质）。
///
/// ## 为什么这条判据落在领域层
///
/// App target 没有测试 target（判据 **#34**）。而"哪种扩展名算 markdown"恰好是
/// 那种写错了**不会报错、只会显示成另一种东西**的规则 —— 少写一个 `.markdown`
/// 只会让一批文件继续以代码块出现，看起来像"这个 App 没做这个功能"。
/// 所以它有一条单测（`MarkdownFileTests`），与 `FilePreviewKind.decide` 同一处置。
///
/// ## ⚠️ 范围是用户裁定的（`.md` / `.markdown`）
///
/// 不含 `.rst` / `.adoc` / `.txt` —— 那些不是 markdown，仍是代码块。
/// 也不含 `.mdx` / `.mdown` / `.mkdn` 等 markdown 家族的其他后缀：
/// 本仓库生态里几乎见不到，多写一张表就多一条没人验的规则。
/// 另两条同日裁定：md 正文里的**相对链接可点、在 App 内跳转**（对齐 README 卡片）；
/// **>1MB 的 md 也照样渲染**（那一档极罕见，行为统一优先）。
public enum MarkdownFile {

    /// 认得出的 markdown 扩展名（小写、不含点）。
    ///
    /// ⚠️ 与 `FilePreviewKind.textExtensions` 里那两个是**同一批字面**
    /// （那边决定"能不能当文本打开"，这里决定"打开之后画成什么"）——
    /// 有意各存一份：两者的**判据不同**（`.rst` 是文本但不是 markdown），
    /// 合并会让"改一处"变成"改两件不相干的事"。
    public static let extensions: Set<String> = ["md", "markdown"]

    /// 这个路径在文件页要不要按 markdown 渲染。
    ///
    /// 只看**最后一段**的扩展名（`docs/guide.md` 与 `guide.md` 同判）——
    /// 复用 `FilePreviewKind.extensionOf`：它已经处理了"文件名里带点"与
    /// "`.md` 大写写成 `.MD`"（内部 `lowercased()`）这两件事，不另写一份。
    public static func rendersAsMarkdown(path: RepoPath) -> Bool {
        extensions.contains(FilePreviewKind.extensionOf(path.displayName))
    }

    /// 文本 + 路径 → **已经解析好的**文档；不是 markdown（或它是空的）时给 `nil`。
    ///
    /// ⚠️ 解析在**取数那一层**做一次、**不在视图的 `body` 里**（同 README 那条：
    /// `MarkdownDocument` 的类型说明写了为什么）。本函数就是"取数层判断该不该解析"
    /// 的那个唯一落点 —— 两个组装点（`RepoFileMapper` 与 `LoadFileContent`）都走它。
    ///
    /// ## ⚠️ 空文档（一个块都没有）也给 `nil` —— 回落成代码块
    ///
    /// 否则一个 0 字节的 `.md` 会画出一张**白底空白卡片**（有边框、有 16 内边距、
    /// 里面什么都没有），而它比一个空代码块更像 bug。同 README 那条
    /// `if !readme.isEmpty`（空 README 不画空区块）。
    public static func document(path: RepoPath, text: String) -> MarkdownDocument? {
        guard rendersAsMarkdown(path: path) else { return nil }
        let document = MarkdownDocument(text)
        return document.isEmpty ? nil : document
    }
}
