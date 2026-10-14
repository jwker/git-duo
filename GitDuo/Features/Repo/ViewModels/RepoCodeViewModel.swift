import Foundation
import GitHubAPI
import GitDuoDesign
import GitDuoKit
import UIKit

/// **代码页**的状态 —— 2026-10-14 新增（走查第 63 条）。
///
/// ## 它只做两件事：把默认分支取回来、把动作转给某一层的会话
///
/// 「目录层级」是**页内导航**（`RepoCodeView` 里那个 `levels` 数组，
/// **不是**一条嵌套的 `NavigationStack` —— 那样会崩，见那边的说明），不进路由
/// ⇒ **每一层一份 `RepoTreeSession`**（那一层的目录页、分支列表、取数状态都在它自己身上）。
/// 本类型因此**不持有**那些会话：谁是当前层、层级里有哪几层，是**视图**的事
/// （导航状态归导航控件，这条与全仓一致 —— `Router` 持有的是推入页的路径，
/// 而"页内的层"没有离开过这一页）。
///
/// 本类型只留两样东西：
/// 1. **默认分支** —— 每层取目录都要它（`RepoTreeSession.load(defaultBranch:)`），
///    而它只该问一次（`LoadRepoDetail.repository(fullName:)` 与首页走同一条路由，
///    通常命中 304、不计配额）；
/// 2. **跨层的那几个动作** —— 切分支（所有层一起换）、复制当前层路径、
///    往当前层上传（§5.8 的后两个出口）。
///
/// ## ⚠️ 为什么切分支要**遍历所有层**
///
/// 每一层的目录是用**某条分支**取的 ⇒ 换了分支，层级里每一层拿着的都是旧分支的内容。
/// 只换当前层的话，用户返回上一层会看到"新分支的面包屑 + 旧分支的目录"
/// —— 而屏幕上没有任何东西是错的（两边各自都合理），只有对照着看才发现对不上。
/// 所以在途的那几层一起换（`RepoTreeSession.switchBranch` 自己判"值没变就不做"，
/// 于是第一个换完之后，其余每个都会真的换一次）。
///
/// ⚠️ 这一条**只在"所有层都在这一页手里"时才写得出** —— 2026-10-14 的崩溃修复
/// （见 `RepoCodeView` 的说明）之后层级仍是页面自己的数组，所以这层遍历照旧成立。
@MainActor
@Observable
final class RepoCodeViewModel {

    // MARK: - 状态

    /// 这次进入解析出的默认分支 —— **每一层取目录都靠它做回落**。
    ///
    /// `nil` 有两种含义，由 `failure` 区分：还没取回来 / 取不回来。
    private(set) var defaultBranch: String?

    /// 取头部失败 ⇒ **整页失败**（连目录都取不了：分支无从解析）。
    private(set) var failure: GitHubError?

    // MARK: - 依赖

    private let detailLoader: LoadRepoDetail
    private let treeLoader: LoadRepoTree
    private let branchesLoader: LoadBranches
    private let memory: any BranchMemoryStore
    private let saver: SaveFile
    private let toast: ToastCenter

    let fullName: String

    /// 他人仓库那一档（§4.13 进来时是 `true`）。
    let readOnly: Bool

    init(
        fullName: String,
        readOnly: Bool,
        detail: LoadRepoDetail,
        treeLoader: LoadRepoTree,
        branches: LoadBranches,
        memory: any BranchMemoryStore,
        saver: SaveFile,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.readOnly = readOnly
        self.detailLoader = detail
        self.treeLoader = treeLoader
        self.branchesLoader = branches
        self.memory = memory
        self.saver = saver
        self.toast = toast
    }

    // MARK: - 生命周期

    /// 进页：只取一次头部（拿默认分支）。目录由各层自己取（见 `load`）。
    func start() async {
        guard defaultBranch == nil, failure == nil else { return }
        do {
            defaultBranch = try await detailLoader.repository(fullName: fullName).defaultBranch
        } catch {
            failure = Self.failure(from: error)
        }
    }

    /// 整页失败之后的「重试」。
    ///
    /// ⚠️ 必须先清掉 `failure`：`start()` 的守卫里有它（"已经失败过就别再取"），
    ///    不清的话这颗重试按钮按下去什么都不做 —— 而它看起来完全正常。
    func retry() async {
        failure = nil
        await start()
    }

    /// 给一层建一个会话（**视图在推入新一层之前调它**）。
    ///
    /// ⚠️ 建会话这件事必须发生在**动作**里、不能发生在 `body` 里 ——
    ///    在渲染期间改状态是 SwiftUI 明令禁止的（会得到"Modifying state during
    ///    view update"的运行时告警，而界面上不一定看得出异常）。
    func makeSession(path: RepoPath) -> RepoTreeSession {
        RepoTreeSession(
            fullName: fullName,
            path: path,
            loader: treeLoader,
            branches: branchesLoader,
            memory: memory
        )
    }

    /// 取某一层 —— **已经取过就跳过**。
    ///
    /// ## ⚠️ 这一句 `guard` 就是"返回上一层不重取"的全部
    ///
    /// ⚠️ **2026-10-14 起它成了唯一的一道**：那时底下的层视图还留在嵌套栈的视图树上，
    /// 返回时 `.task` 根本不会重跑；现在层级是页面自己的数组、**只有栈顶被渲染**，
    /// 而 `.task` 的 id 带着"哪一层"（`RepoCodeView` 的 `RepoCodeLoadKey`）
    /// ⇒ 返回时它会**再跑一次**，全靠这一句把它挡掉（那一层的 `page` 已经落地）。
    /// 用户看到的是**立刻就有的内容**，没有骨架、没有转圈 —— 这正是用户要的"文件夹感"，
    /// 而不是"每次都重新加载"。
    /// ⚠️ 所以这一句不是"顺手加的一道保险"，**它和 `RepoCodeLoadKey` 里的路径合起来才是**
    /// "返回即所见"的全部：路径那一半保证"该取的时候一定取到"（漏了它 ⇒ 永远停在骨架屏，
    /// 见 2026-10-14 用户报回的那条），这一句保证"不该取的时候一定不取"。
    ///
    /// ⚠️ 失败的层**不会**被这句挡在门外（`hasFinished` 对失败也是 `true`），
    ///    所以它不会自动重试 —— 那一层的失败块上有一颗「重试」（`RepoTreeSection`）。
    ///
    /// ⚠️ 反过来说：**从没被渲染过的那几层**（进页时铺的中间层，见 `RepoCodeView.chain`）
    ///    确实还没落地 ⇒ 第一次返回到它们时才真取一次。这是那套铺法的代价，如实记着。
    func load(_ session: RepoTreeSession) async {
        guard let defaultBranch else { return }
        guard !session.page.hasFinished else { return }
        await session.load(defaultBranch: defaultBranch)
    }

    // MARK: - 分支（跨层）

    /// 打开分支弹层时取列表（用**当前层**的会话 —— 列表是仓库级的，哪一层问都一样）。
    func loadBranches(_ session: RepoTreeSession) async {
        await session.loadBranches()
    }

    /// 切分支：**栈里每一层都换一次**（理由见类型说明）。
    ///
    /// - Returns: 真的换了才 `true`（点当前那一条时 `false`）。
    @discardableResult
    func switchBranch(to name: String, sessions: [RepoTreeSession]) async -> Bool {
        guard let defaultBranch else { return false }

        // ⚠️ 先取一遍"有没有任何一层真的换了"：**不能**用第一层的返回值当结论 ——
        //    弹层里选中的那条正好是第一层当前的分支时它会返回 `false`，
        //    而其余层可能还在另一条分支上（那就真的换了，提示不该吞掉）。
        var switched = false
        for session in sessions {
            if await session.switchBranch(to: name, defaultBranch: defaultBranch) {
                switched = true
            }
        }
        if switched { toast.show(BranchCopy.switchedToast(branch: name)) }
        return switched
    }

    // MARK: - 复制当前层路径（2026-10-12 按用户要求新增）

    /// 复制**某一层**的仓库内相对路径 —— 那一层面包屑右侧「⋯」菜单里的第一项。
    ///
    /// ## ⚠️ 根目录复制的是**仓库全名**，不是空串
    ///
    /// 根目录没有"仓库内相对路径"（`RepoPath.root.raw` 就是空串），而复制一个空串
    /// 对用户毫无用处。取仓库全名兜底 —— **这是用户裁定的**（`REVIEW-CHECKLIST` 第 56 条）。
    /// 代价如实记着：两档复制出来的东西**形态不同**（一个是路径、一个是仓库名），
    /// 粘到终端里根目录那一次是个无效路径。别把它当成设计本意。
    ///
    /// ⚠️ 零请求：路径就在参数上，复制是纯本地操作（同 `FileViewModel.copyRaw`）。
    ///
    /// ⚠️ **要复制的那一串由 `RepoCopy.clipboardPath(for:fullName:)` 算**（含根目录那条兜底）——
    /// 规则写在领域层才跑得进单测（`make test` 不编译 App target），
    /// 本方法只负责"取路径 → 写剪贴板 → 弹提示"这三步。
    func copyPath(at path: RepoPath) {
        UIPasteboard.general.string = RepoCopy.clipboardPath(for: path, fullName: fullName)
        toast.show(RepoCopy.pathCopiedToast)
    }

    // MARK: - 上传（§5.8 的后两个出口）

    /// §5.8 两个上传出口的落点 —— **点「添加文件」时所在的那一层目录 + 选中的文件名**。
    ///
    /// ## ⚠️ 只此一处算，提交弹层那行与真正 `PUT` 的路径都读它
    ///
    /// 两处各算一次的那天，露出来的落点与写下去的路径会不一样 —— 而"东西存到哪"
    /// 正是这一步里用户唯一可能搞错的事。
    ///
    /// - Returns: `nil` = 这个名字拼不进路径（服务端也会拒）⇒ 调用方据此**不显示落点**、
    ///   也不该发请求。正常路上到不了：文件名来自系统选择器（文件 App 是
    ///   `lastPathComponent`、相册由 `UploadFileName` 生成）。
    func uploadDestination(for fileName: String, at directory: RepoPath) -> RepoPath? {
        guard case let .acceptable(resolved) = RepoPath.resolveUpload(
            directory: directory, fileName: fileName
        ) else { return nil }
        return resolved
    }

    /// 把一份**已经在手上**的字节提交到**某一层目录**（`sha` 恒为 `nil` —— 这是一次新建）。
    ///
    /// ## ⚠️ 它**不复用** `EditorViewModel.submit`
    ///
    /// 两处的差别不是"路径从哪来"这一件事：那里是**文本**（要 UTF-8 编码、要判 1MB）、
    /// 这里是**字节**（不编码成文本；没动过时它就是选择器给的原样，>1MB 的图片、
    /// 或网页端显示不出来的格式，已经在 `AddFileSheet` 那一步由 `UploadIntake` 压过 / 转过
    /// —— 决策 #71 · #72 ⇒ **这里不再判大小**，判重了会让"动过之后到底算不算超限"
    /// 出现第二个答案）；那里有"编辑模式 ⇒ 带 sha"
    /// 那一档、这里恒为新建。合成一处要加两三个开关，而每一个开关在两个调用点里
    /// 总有一处是错的。
    ///
    /// ⚠️ 与 `EditorViewModel.submit` **可能撞上同一条 409**：上传不带 `sha`，
    /// 失败只可能是 422（同名已存在）—— 而那一档的文案由 `FileWriteFailure` 给
    ///（`CommitSheetCopy.destinationExistsHint`，§5.8 明写"重名不静默覆盖"）。
    ///
    /// - Parameter session: 落点那一层的会话 —— 写完之后**它的目录要重取**
    ///   （多了一个文件），而它自己的分支就是这次写入的 `ref`。
    func upload(
        _ draft: UploadDraft,
        commit: CommitDraft,
        at directory: RepoPath,
        session: RepoTreeSession
    ) async -> CommitAttempt {
        // 这一屏取内容时一定解析过分支（`session.load` 先定 ref、再取目录）——
        // 拿不到时说明那一层还没加载出来，而那时也不该有「＋ 添加」可点。
        guard let branch = session.branch else { return .rejected(ActionCopy.failed) }

        // ⚠️ 落点走 `uploadDestination`（**同一个方法**，提交弹层那行只读的「将写入 …」也读它）
        //    —— 两处各拼一次的那天，露出来的落点与写下去的路径会不一样。
        // ⚠️ 它内部仍是**与新建文件同一套**判据（`RepoPath.resolveUpload` 走
        //    `normalizeUserInput`，只多一条"文件名必须是一段"）：文件名虽然来自系统选择器，
        //    仍然要过一遍（"界面看起来正常、路径不对"正是那套判据拦的东西）。
        guard let path = uploadDestination(for: draft.fileName, at: directory) else {
            return .rejected(ActionCopy.failed)
        }

        do {
            let outcome = try await saver.run(
                fullName: fullName,
                path: path,
                content: draft.data,
                draft: commit,
                // 新建：**不带 `sha`**（决策 #70⑤：路径已存在时服务端回 422，不静默覆盖）。
                sha: nil,
                currentBranch: branch
            )
            // 完全成功 ⇒ 那一层的目录变了（多了一个文件）。
            // ⚠️ 两档"做到一半"**不刷新**：那一刻用户还在结果屏上读那句话，
            //    而列表在他背后换一次内容只会让人怀疑"我到底提交成功没有"。
            //
            // ⚠️ 这里**只重取落点那一层**：别的层的内容没有变，
            //    而"顺手把整栈刷一遍"会让用户返回时看到一个正在转圈的上一级。
            if outcome.isComplete { await session.reload() }
            return .settled(outcome)
        } catch let error as BranchCreationError {
            // 新分支名不合法 —— 与编辑器同一条处置（表单校验，不是网络错误）。
            return .rejected(error.message)
        } catch {
            let failure = FileWriteFailure(Self.failure(from: error))
            return .rejected(failure.message ?? ActionCopy.failed)
        }
    }

    // MARK: - 错误归一化

    /// 把任意错误收敛成 `GitHubError`（同其余 ViewModel：映射失败归 `.decoding`，
    /// **不是** `.transport` —— 后者会让界面给出"检查网络"的错误引导）。
    private static func failure(from error: any Error) -> GitHubError {
        if let githubError = error as? GitHubError { return githubError }
        return .decoding(error)
    }
}
