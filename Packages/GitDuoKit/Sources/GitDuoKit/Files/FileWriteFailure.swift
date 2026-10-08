import Foundation
import GitHubAPI

/// 一次文件写操作失败时的**分类** —— 把 `GitHubError` 翻成写通道里能说的四种话。
///
/// ## 为什么需要它（而不是让视图直接看 `GitHubError`）
///
/// 写通道会遇到的三个状态码各自要求**完全不同的下一步**，而它们在
/// `GitHubError` 里是三个平铺的 case，视图自己判会漏、会错位：
///
/// | 状态码 | `GitHubError` | 含义 | 用户该做什么 |
/// |---|---|---|---|
/// | 409 | `.conflict` | **版本基准过期** | 换版本再提 / 强制覆盖（§9.6.4 两个出口） |
/// | 422 | `.validation` | 不带 `sha` 去写一个已存在的路径 | 改名 / 去网页端（决策 #70⑤） |
/// | 404 | `.notFound` | 那个路径不在了（别人删了它，或分支没了） | 重新看一眼 |
///
/// ## ⚠️ 409 在这里**不叫"冲突"以外的东西**，也**不与分支合并的 409 共用常量**
///
/// §9.6.4 明写：本处的 409 是"`sha` 过期"，而 §9.7.1 合并分支的 409 是"分支内容冲突"、
/// §9.7.2 合并 PR 的 405/409 又是第三件事。三处的**处置**不同（合并冲突要去网页端解，
/// 版本过期要在本弹层换两个出口），所以三处各有各的文案常量。
/// 把它们合成一句"冲突了"是那种"看起来更一致、实际更没用"的统一。
///
/// ⚠️ **409 也不等于"别人改了这个文件"**（§9.6.4 末）：他可能就是同一个人在另一台设备上改的。
/// 所以 `conflictMessage` 只说"这个文件被更新过"，**不断言是谁**。
public enum FileWriteFailure: Sendable, Equatable {

    /// 409 —— 版本基准过期，§9.6.4 的两个出口就是为它准备的。
    case conflict

    /// 422 —— 目标路径上已经有文件了（决策 #70⑤：不带 `sha` 写已存在路径）。
    ///
    /// ⚠️ 它**不只是**上传会遇到：新建文件到一条已有同名文件的路径上同样是这一档。
    case destinationExists

    /// 404 —— 那个路径（或分支）不在了。
    case notFound

    /// 其余（403 / 配额 / 网络 / 5xx …）—— **原样带出去，不编造含义**。
    ///
    /// ⚠️ 这一档是兜底而**不是**"其他错误"的意思：调用方要判"能不能重试"
    /// 必须再看 `GitHubError.serverError(status:)` 的 `status` 是否 5xx
    /// （`GitHubError` 的类型说明点名过这件事）。
    case other(GitHubError)

    /// 把网络层的错误归到写通道的类别里。
    public init(_ error: GitHubError) {
        switch error {
        case .conflict: self = .conflict
        case .validation: self = .destinationExists
        case .notFound: self = .notFound
        default: self = .other(error)
        }
    }

    /// 给用户看的那句话。
    ///
    /// ⚠️ 只有前两档是本类型自己拟的话；`.notFound` 与 `.other` 交给调用方 ——
    /// 因为 404 在不同入口下的下一句不一样（提交时说"分支或文件已不在"，
    /// 删除时说"该文件已不存在"，见 `FileCopy.alreadyGoneHint`），
    /// 而 `.other` 的成因各操作自己说得更准（照 `ActionCopy` 那条取舍）。
    public var message: String? {
        switch self {
        case .conflict: CommitSheetCopy.conflictHint
        case .destinationExists: CommitSheetCopy.destinationExistsHint
        case .notFound, .other: nil
        }
    }

    /// 要不要把**两个出口**（查看最新版 / 强制覆盖）换出来。
    ///
    /// 写成属性而不是让视图 `if case .conflict = failure`：那句会出现在
    /// 提交弹层的按钮区与提示条两处，而漏掉一处的表现是
    /// **"提示说可以强制覆盖、但按钮没出现"**。
    public var offersConflictExits: Bool { self == .conflict }
}
