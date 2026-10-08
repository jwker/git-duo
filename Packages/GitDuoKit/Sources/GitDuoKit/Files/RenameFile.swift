import Foundation
import GitHubAPI

/// 重命名（移动）一个文件 —— §9.6.5，**两步串行**。
///
/// ## ⚠️ 为什么必须串行
///
/// 官方对这两个端点有一条 NOTE（原文见决策 #66）：
/// `PUT contents` 与 `DELETE contents` **并行会冲突**，必须 serially。
/// 所以这里没有 `async let`、没有 `TaskGroup` —— 两次写**顺序发出**。
/// 并发的写法更"快"，但它在服务端是偶发失败，而那种失败看起来像网络抖动。
///
/// ## ⚠️ 为什么先读一次源文件
///
/// 重命名要**把原来的字节写到新路径**（`PUT` 的 `content` 必填），
/// 同时 `DELETE` 旧路径要**旧版的 `sha`**（决策 #66②：`message` 与 `sha` 都必填）。
/// 两样东西同一次 `GET /contents` 就给全了 —— 而且那一次读顺带回答了
/// "这个文件还在不在"（404）与"它的内容能不能写"（>1MB 时服务端回
/// `encoding: "none"` + 空 `content` ⇒ 写不出来）。
///
/// 也就是说：**这一次读不是"多一趟"，它是这道操作的前置判据**。
/// 跳掉它去复用文件查看页手上的 `sha` 有两个问题 ——
/// 那个值可能来自几分钟前，而更麻烦的是**没有任何东西回答"内容拿不拿得到"**：
/// 一个 2MB 的文本文件在文件查看页看得见（走 raw），却写不出来。
public struct RenameFile: Sendable {

    private let contents: any RepoContentsDataSource
    private let files: any RepoFileWriteDataSource

    public init(contents: any RepoContentsDataSource, files: any RepoFileWriteDataSource) {
        self.contents = contents
        self.files = files
    }

    /// - Parameters:
    ///   - source: 当前路径（一定已经在仓库里）。
    ///   - destination: 新路径 —— 调用方应先用
    ///     `RepoPath.resolveRenameDestination(from:input:)` 过一遍（空 / 与源相同 /
    ///     非法段都在那里拦）。本方法**假设它已经合法**，但仍按服务端的话办事。
    ///   - message: 提交信息（空则用默认信息，与 `SaveFile` 同源）。
    ///   - branch: 在哪条分支上做（`PUT` 与 `DELETE` 都带它 —— 决策 #65 那条"绝不依赖默认值"）。
    ///
    /// - Returns: 见 `RenameOutcome`（**四种结局，其中一种是"两个文件都在"**）。
    /// - Throws: 第 1 步（写新路径）之外的失败 —— 即 `PUT` 拿到 422 之外的错误，
    ///   以及读源文件时 404 之外的错误。⚠️ 读源 404 **不抛**：
    ///   "这个文件已经不在了"是一个要说给用户听的正常结论（`RenameSourceIssue.gone`）。
    public func run(
        fullName: String,
        source: RepoPath,
        destination: RepoPath,
        message: String?,
        branch: String
    ) async throws -> RenameOutcome {
        let (owner, repo) = try RepositoryMapper.splitFullName(fullName)
        let commitMessage = CommitMessageDefaults.resolved(message)

        // ── 第 0 步（判据）：读源文件的 sha 与字节。
        let payload: RepoFileDTO?
        do {
            payload = try await contents.contents(
                owner: owner, repo: repo, path: source.raw, ref: branch
            ).file
        } catch {
            guard let githubError = error as? GitHubError else { throw error }
            if case .notFound = githubError { return .sourceUnavailable(.gone) }
            throw githubError
        }

        guard let payload else {
            // 这个 path 上不是一个文件（是目录，或服务端的形状变了）。
            // 对用户而言准确的说法仍是"这个文件不在了" —— 它确实不是一个可重命名的文件。
            return .sourceUnavailable(.gone)
        }

        guard let bytes = Self.writableBytes(payload) else {
            return .sourceUnavailable(.notWritable)
        }

        // ── 第 1 步：写新路径。**不带 `sha`** —— 新路径是一次新建。
        //    路径上已有文件 ⇒ 服务端 422（决策 #70⑤）；那一档要单独说，
        //    因为 422 的原文解释不了"我明明只是想改个名字"（§9.6.5）。
        do {
            // ⚠️ **有意丢掉返回值**：`putFile` 回的是"新 blob SHA + 这次提交 SHA"，
            //    而重命名**不需要新基准** —— 新路径是刚建出来的，用户并没有"读到过的那一版"；
            //    下一次编辑会重新读一次，那时拿到的才是基准。
            //    写 `_ =` 而不是让编译器静默忽略（`putFile` 故意没有 `@discardableResult`）：
            //    那条规则在**编辑器**那个调用点上是一条真缺陷（丢掉新 sha ⇒ 第二次提交必 409），
            //    所以这里的"不要它"必须是一句显式的话，而不是无声的默认。
            _ = try await files.putFile(
                owner: owner,
                repo: repo,
                path: destination.raw,
                message: commitMessage,
                content: bytes,
                sha: nil,
                branch: branch
            )
        } catch {
            guard let githubError = error as? GitHubError else { throw error }
            if FileWriteFailure(githubError) == .destinationExists {
                return .destinationExists
            }
            throw githubError
        }

        // ── 第 2 步：删旧路径。⚠️ 上一步已经改了仓库，这一步失败是**部分成功**。
        do {
            try await files.deleteFile(
                owner: owner,
                repo: repo,
                path: source.raw,
                message: commitMessage,
                sha: payload.sha,
                branch: branch
            )
        } catch {
            guard let githubError = error as? GitHubError else { throw error }
            // ⚠️ 旧路径已经不在（别人删了它、或并发的一次操作抢先）⇒
            //    这时的**终态恰好就是我们要的**（只有新路径），如实报成功。
            //    照 404 报"两个文件都在"是**假话**，而用户会去找一个不存在的文件。
            if case .notFound = githubError { return .renamed(to: destination) }
            return .movedButOldRemains(newPath: destination, reason: githubError)
        }

        return .renamed(to: destination)
    }

    // MARK: - 内部

    /// 这一次 `contents` 响应里**能拿去写的字节**；拿不到就是 `nil`。
    ///
    /// 三种情况都归 `nil`，而它们对用户的含义相同（都做不了这次重命名）：
    /// - `encoding == "none"`（>1MB，服务端不给内容）；
    /// - `content` 缺席或 `size > 0` 却是空串（`isContentOmitted`）；
    /// - base64 解不出来（`FileContentCodec.decodeBase64` 有意对空串返回 `nil`）。
    ///
    /// ⚠️ 复用 `FileContentCodec` 而不是在这里 `Data(base64Encoded:)`：
    /// GitHub 的 base64 是**带换行**的（每 60 字符插一个），直接解会失败 ——
    /// 而那一步失败的表现是"这个文件重命名不了"，看不出是编码问题。
    /// 同一条规则已经在文件查看页用着了，两处各写一遍就会分叉。
    private static func writableBytes(_ payload: RepoFileDTO) -> Data? {
        if FileContentCodec.isContentOmitted(
            encoding: payload.encoding, base64: payload.content, size: payload.size
        ) {
            return nil
        }
        // 0 字节的文件：`content` 是空串，而 `decodeBase64("")` 返回 `nil`。
        // 它的字节就是"零个字节"（与 `LoadFileContent.decodedBytes` 同一处特判、同一个理由）。
        if payload.size == 0, payload.content?.isEmpty ?? true { return Data() }
        return payload.content.flatMap(FileContentCodec.decodeBase64)
    }
}

/// 重命名的四种结局。
public enum RenameOutcome: Sendable, Equatable {

    /// 两步都成了。
    case renamed(to: RepoPath)

    /// 第 1 步就撞上"新路径已有文件"（服务端 422）。
    ///
    /// ⚠️ **不覆盖、不合并**（PRD §5.16 明写）：用户想要的是改名，
    /// 不是把两个文件并成一个 —— 那件事的正确做法是让他换个名字。
    case destinationExists

    /// 第 1 步成了、第 2 步失败 ⇒ **仓库里此刻有两个文件**（PRD §5.16）。
    ///
    /// ⚠️ 文案必须说"新路径已写入，原路径仍在" —— 含糊成"重命名失败"
    /// 会让用户以为什么都没变（他可能就此不再管，而仓库里多了一个副本）。
    /// 带 `reason` 的理由同 `FileSaveOutcome`：不静默吞掉成因。
    case movedButOldRemains(newPath: RepoPath, reason: GitHubError)

    /// 源文件这边做不了（不在了 / 内容拿不到）。
    case sourceUnavailable(RenameSourceIssue)

    /// 真的改成功了吗（只有 `.renamed` 为真）。
    ///
    /// ⚠️ **`.movedButOldRemains` 不算成功**：虽然新路径已经写进去了，
    /// 但用户要的结果（"这个文件现在叫那个名字"）并没有达到 —— 两个都在。
    public var didRename: Bool {
        if case .renamed = self { return true }
        return false
    }
}

/// 重命名做不了的原因（源文件侧）。
public enum RenameSourceIssue: Sendable, Equatable {

    /// 源路径已经不在了（别人删了 / 分支变了）。
    case gone

    /// 内容拿不到 ⇒ 写不出新路径：>1MB（服务端回空壳）、二进制、或解不出 base64。
    ///
    /// ⚠️ 与 `.gone` **必须分开**：一个说"它没了"，一个说"它在，但这条通道做不了"。
    /// 合成一句会让一个**还在那里**的文件被说成"已不存在"，用户会以为数据没了。
    case notWritable
}

/// 提交信息的默认值 —— `SaveFile` / `RenameFile` / `DeleteFile` 三条写通道共用。
///
/// ## 为什么单独提出来
///
/// 三条通道都要"空则用默认信息"（§5.9、原型 `doCommit` 逐字）。
/// 三处各写一遍 `?? "update via GitDuo"` 的后果不是多两行 ——
/// 而是这三条提交会**在仓库历史里长得不一样**，而那种差别只在网页端看得出来。
///
/// ⚠️ 与 `CommitDraft.effectiveMessage` 的关系：那一份是**草稿**上的规则
/// （原样保存、发出去时才 trim），这一份是**没有草稿**的两条通道
/// （重命名 / 删除，它们的提交信息没有输入框）的规则。两者的落点值相同，
/// 但"要不要 trim 落盘那一份"这件事上不同，所以不是同一个函数。
public enum CommitMessageDefaults {

    /// 把可能为空 / 全空白的提交信息换成默认信息。
    public static func resolved(_ message: String?) -> String {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? CommitSheetCopy.defaultMessage : trimmed
    }
}
