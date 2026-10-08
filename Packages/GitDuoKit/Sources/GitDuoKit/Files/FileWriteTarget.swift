import Foundation

/// 一次提交写到**哪里** —— §5.9 那两档分段（TECH_SPEC §9.6.3）。
///
/// ## 为什么做成枚举而不是"一个布尔 + 两个字符串"
///
/// 两档的**必填参数完全不同**：当前分支那一档只要 commit message；
/// 「新分支 + PR」那一档还要分支名与 PR 标题（官方 `POST /pulls` 的
/// `title` / `head` / `base` **三个都必填**，见决策 #67）。
///
/// 用布尔量表达时，那三个字符串**在"当前分支"这一档里也存在**（只是不用）——
/// 于是"界面没让用户填、代码却带着一个空串去建 PR"这种错**编译期看不出来**，
/// 运行期表现为建出一个叫空字符串的分支（服务端 422，文案解释不了）。
/// 收成枚举后，三个值**只存在于需要它们的那一档**里。
///
/// ⚠️ **分支名与 PR 标题都在这里，而不是在 `CommitDraft` 上**：
/// 它们是"这一档特有的输入"，跟着枚举走最不容易出现"目标已经不是新分支了、
/// 却还留着一份旧的分支名"这种状态残留。
public enum FileWriteTarget: Sendable, Hashable {

    /// 直接在当前分支上提交（§5.9 的第一档，默认选项）。
    case currentBranch

    /// 先建一条新分支、提交到它上面、再开一个 PR（§5.9 的第二档）。
    ///
    /// - Parameters:
    ///   - name: 新分支名。**从哪条分支分出去不是参数** —— 恒为当前分支，
    ///     那正是这一档的定义（决策 #67）。
    ///   - prTitle: PR 标题。`base` = 当前分支、`head` = `name`（两者都由调用链补上）。
    case newBranch(name: String, prTitle: String)

    /// 要不要先建分支。
    ///
    /// ⚠️ 收成一处：`SaveFile`、提交弹层、测试里都会问这个问题，
    /// 而 `if case .newBranch = target` 与 `target != .currentBranch` 两种写法
    /// 在只有两档时看起来一样，加第三档那天就分叉了。
    public var isNewBranch: Bool {
        if case .newBranch = self { return true }
        return false
    }

    /// 用户填的那条分支名（当前分支那一档为 `nil`）。
    ///
    /// 取值处要注意它**还没有 trim、没有校验** —— 那两件事在 `SaveFile` 里
    /// （与 `CreateBranch.run` 同一套：先 trim 再 `BranchName.validate`）。
    public var newBranchName: String? {
        if case let .newBranch(name, _) = self { return name }
        return nil
    }

    /// 用户填的那个 PR 标题（当前分支那一档为 `nil`）。
    public var newBranchPRTitle: String? {
        if case let .newBranch(_, prTitle) = self { return prTitle }
        return nil
    }
}

// MARK: - 默认分支名

extension FileWriteTarget {

    /// 「新分支 + PR」那一档的**预填分支名**：`gitduo/{yyyyMMdd-HHmmss}`（PRD §5.9②）。
    ///
    /// ## 为什么要给默认值，而不是让用户从空开始填
    ///
    /// 官方 `POST /pulls` 的 `head` 是必填，而"该填什么"对用户是个真问题；
    /// 预一个带时间戳的名字，用户直接提交就得到一条合法且不重名的分支
    /// （同一秒内连提两次会重名 —— 但那第二次本来就会撞 422，不是这条规则的锅）。
    /// ⚠️ 它**可以改**（决策 #67 存在的全部意义）：分支名会一直挂在仓库的历史里。
    ///
    /// ## 为什么是 `gitduo/` 前缀
    ///
    /// 一眼能看出这条分支是 App 建的（与网页端手建的区分开），
    /// 而 `gitduo/` 里有 `/` ⇒ 在分支列表里天然聚成一组。
    ///
    /// - Parameters:
    ///   - now: **必传**。本函数不自己取 `Date()` —— 那会让"预填名是什么"
    ///     在测试里不可断言（`FileWriteTargetTests` 要钉住格式与毫秒/秒的粒度）。
    ///   - timeZone: 默认跟设备。测试传固定时区以获得确定结果。
    ///     ⚠️ **不能用 `Locale` 影响格式**：`yyyyMMdd` 在泰历 / 和历下会算出别的年份，
    ///     所以 formatter 固定 `en_US_POSIX`。
    public static func defaultNewBranchName(
        now: Date,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "gitduo/\(formatter.string(from: now))"
    }
}
