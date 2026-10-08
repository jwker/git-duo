import Foundation

/// 编辑器（§4.6）打开时的两种模式。
///
/// ## ⚠️ 它原先在 App 层的 `Route.swift` 里（切片 8.1 搬进来）
///
/// 搬进来的理由与 `RepoSection` 当初一样（`Route.swift` 抬头那段记录了同一件事）：
/// 这个枚举在切片 8 之前**只有路由在用**，所以放哪都行；而 8.1 起它多了两个用户 ——
/// `SaveFile`（`sha` 带不带由模式决定）与 `EditorCopy`（说明行与导航标题各说一句）。
///
/// 两处各定义一份的下场不是"多几行"：
/// **同模块的类型会遮蔽 import 进来的那个**，于是"给编辑器取标题"这类调用
/// 拿到的可能是另一份，报错还指向一行完全正常的代码。
/// 与 `RepoSection` 一样，正本只有这一处。
///
/// ⚠️ **`Hashable` 是路由要求的**（`Route.editor` 是 `Hashable` 枚举的一个 case）——
/// 不是随手加的协议。
public enum EditorMode: Hashable, Sendable {

    /// 新建文件（编辑器里出现路径输入框，`sha` 不带）。
    case create

    /// 编辑既有文件（进页面时读一次正文与 `sha`，提交时带 `sha`）。
    case edit

    /// 这个模式要不要在进页面时读一次既有内容（= 要不要拿 `sha`）。
    ///
    /// ⚠️ 收成一处而不是让调用方 `mode == .edit`：那个判断在编辑器页、
    /// 提交弹层、测试替身里都会出现，而 `== .create` 与 `!= .edit` 这两种写法
    /// 在只加两个 case 时**看起来一模一样**，加第三个模式那天就分叉了。
    public var loadsExistingContent: Bool { self == .edit }
}
