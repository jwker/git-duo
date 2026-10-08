import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

// MARK: - 替身

/// 写通道的替身：记录两次写、按脚本回话。
///
/// ⚠️ 本套件的**主要断言对象是"发了几次、按什么次序、带了什么参数"**，不是返回值。
/// §9.6.3 / §9.6.5 的全部意义是"某一档要多发两步"、"那两步必须串行"、
/// "`branch` 与 `sha` 一个都不能省" —— 而这三件事**只能靠记录看出来**：
/// 参数写错时界面照样说"已提交"（写到了别的分支 / 覆盖了别人那一版）。
actor ScriptedWriteSource: RepoFileWriteDataSource {

    /// 一次 `PUT` 的记录。
    struct Put: Equatable, Sendable {
        let path: String
        let message: String
        let content: Data
        let sha: String?
        let branch: String
    }

    /// 一次 `DELETE` 的记录。
    struct Delete: Equatable, Sendable {
        let path: String
        let message: String
        let sha: String
        let branch: String
    }

    private let putReply: Result<FileWriteResultDTO, GitHubError>
    private let deleteReply: Result<Void, GitHubError>

    private(set) var puts: [Put] = []
    private(set) var deletes: [Delete] = []

    init(
        put: Result<FileWriteResultDTO, GitHubError> = .success(.stub()),
        delete: Result<Void, GitHubError> = .success(())
    ) {
        self.putReply = put
        self.deleteReply = delete
    }

    func putFile(
        owner: String,
        repo: String,
        path: String,
        message: String,
        content: Data,
        sha: String?,
        branch: String
    ) async throws -> FileWriteResultDTO {
        puts.append(Put(path: path, message: message, content: content, sha: sha, branch: branch))
        return try putReply.get()
    }

    func deleteFile(
        owner: String,
        repo: String,
        path: String,
        message: String,
        sha: String,
        branch: String
    ) async throws {
        deletes.append(Delete(path: path, message: message, sha: sha, branch: branch))
        try deleteReply.get()
    }
}

extension FileWriteResultDTO {
    /// 一次成功写入的最小构造器。
    static func stub(blobSHA: String = "sha-new", commitSHA: String = "c0ffee") -> FileWriteResultDTO {
        FileWriteResultDTO(
            content: RepoFileDTO(
                name: "main.swift", path: "Sources/main.swift",
                sha: blobSHA, size: 3, encoding: "base64", content: "YWJj"
            ),
            commit: FileWriteResultDTO.Commit(sha: commitSHA, message: nil)
        )
    }
}

/// 分支端点的替身 —— 只关心"建分支被调了几次、从哪个 sha 建的"。
actor ScriptedBranchSource: RepoBranchDataSource {

    struct Create: Equatable, Sendable {
        let name: String
        let sha: String
    }

    private let branchReply: Result<BranchDTO, GitHubError>
    private let createReply: Result<Void, GitHubError>

    private(set) var creates: [Create] = []
    private(set) var branchReads: [String] = []

    init(
        branch: Result<BranchDTO, GitHubError> = .success(BranchDTO(name: "main", commitSHA: "head-1", protected: false)),
        create: Result<Void, GitHubError> = .success(())
    ) {
        self.branchReply = branch
        self.createReply = create
    }

    func branches(owner: String, repo: String) async throws -> Page<BranchDTO> {
        Page(items: [], nextCursor: nil, headers: HTTPHeaders([:]))
    }

    func branch(owner: String, repo: String, name: String) async throws -> BranchDTO {
        branchReads.append(name)
        return try branchReply.get()
    }

    func compare(owner: String, repo: String, base: String, head: String) async throws -> CompareDTO {
        CompareDTO(aheadBy: 0, behindBy: 0, totalCommits: 0)
    }

    @discardableResult
    func createBranch(owner: String, repo: String, name: String, sha: String) async throws -> GitReferenceDTO {
        creates.append(Create(name: name, sha: sha))
        try createReply.get()
        return GitReferenceDTO(ref: "refs/heads/\(name)", object: .init(sha: sha))
    }

    func deleteBranch(owner: String, repo: String, name: String) async throws {}

    func merge(owner: String, repo: String, base: String, head: String, message: String?) async throws -> MergeOutcome {
        .nothingToMerge
    }
}

/// 建 PR 的替身。
actor ScriptedPullCreationSource: RepoPullCreationDataSource {

    struct Create: Equatable, Sendable {
        let title: String
        let head: String
        let base: String
    }

    private let reply: Result<Int, GitHubError>

    private(set) var creates: [Create] = []

    init(number: Int = 58, failure: GitHubError? = nil) {
        self.reply = failure.map { .failure($0) } ?? .success(number)
    }

    func createPull(
        owner: String,
        repo: String,
        title: String,
        head: String,
        base: String
    ) async throws -> PullDetailDTO {
        creates.append(Create(title: title, head: head, base: base))
        let number = try reply.get()
        return PullDetailDTO(
            number: number, title: title, state: "open",
            head: PullRefDTO(ref: head), base: PullRefDTO(ref: base),
            additions: 0, deletions: 0, changedFiles: 1
        )
    }
}

/// 读文件的替身（重命名 / 删除要先读一次源文件）。
actor ScriptedReadSource: RepoContentsDataSource {

    private let reply: Result<RepoFileDTO?, GitHubError>
    private(set) var reads: [(path: String, ref: String?)] = []

    init(reply: Result<RepoFileDTO?, GitHubError>) {
        self.reply = reply
    }

    /// 一次正常的单文件读取。
    static func file(
        sha: String = "sha-old",
        size: Int = 3,
        text: String = "abc"
    ) -> ScriptedReadSource {
        ScriptedReadSource(reply: .success(RepoFileDTO(
            name: "a.swift", path: "Sources/a.swift", sha: sha, size: size,
            encoding: "base64", content: Data(text.utf8).base64EncodedString()
        )))
    }

    func contents(owner: String, repo: String, path: String, ref: String?) async throws -> ContentsPayload {
        reads.append((path: path, ref: ref))
        let payload = try reply.get()
        // `nil` 表示「这个 path 上不是一个文件」（目录）。
        return payload.map(ContentsPayload.file) ?? .directory([])
    }

    func rawFile(owner: String, repo: String, path: String, ref: String?) async throws -> Data {
        Data()
    }

    func readme(owner: String, repo: String, ref: String?) async throws -> String? { nil }
}

private func draft(
    message: String = "",
    target: FileWriteTarget = .currentBranch,
    source: CommitSource = .newFile
) -> CommitDraft {
    CommitDraft(message: message, target: target, source: source)
}

private let path = RepoPath(path: "Sources/main.swift")

// MARK: - SaveFile

/// 提交一个文件（§9.6.1 / §9.6.3、决策 #65 / #67 / #68）。
@Suite("提交文件 · 两档目标 / 三步的部分失败 / 参数一个不能省")
struct SaveFileTests {

    private func makeSaveFile(
        files: ScriptedWriteSource,
        branches: ScriptedBranchSource = ScriptedBranchSource(),
        pulls: ScriptedPullCreationSource = ScriptedPullCreationSource()
    ) -> SaveFile {
        SaveFile(files: files, branches: branches, pulls: pulls)
    }

    // MARK: - 当前分支那一档

    @Test("当前分支：**一次 PUT**，带 `branch` 与 `sha`，不碰分支与 PR 两个端点")
    func currentBranchDoesASinglePut() async throws {
        let files = ScriptedWriteSource()
        let branches = ScriptedBranchSource()
        let pulls = ScriptedPullCreationSource()

        let outcome = try await makeSaveFile(files: files, branches: branches, pulls: pulls).run(
            fullName: "octocat/hello",
            path: path,
            content: Data("let a = 1".utf8),
            draft: draft(message: "改一行", target: .currentBranch),
            sha: "sha-baseline",
            currentBranch: "feature/x"
        )

        #expect(outcome == .committedToCurrentBranch(FileSaveReceipt(
            path: path, blobSHA: "sha-new", commitSHA: "c0ffee"
        )))
        let puts = await files.puts
        #expect(puts.count == 1)
        #expect(puts.first?.branch == "feature/x", "⚠️ `branch` 只能来自调用方 —— 不传就会落到默认分支")
        #expect(puts.first?.sha == "sha-baseline", "⚠️ 这里那个 sha 必须是**用户读到的那一版**，不是新取的")
        #expect(puts.first?.message == "改一行")
        #expect(puts.first?.content == Data("let a = 1".utf8), "内容原样发出去（base64 是数据层的事）")
        #expect(await branches.creates.isEmpty)
        #expect(await pulls.creates.isEmpty)
    }

    @Test("新建文件（`sha: nil`）从当前分支出发，同样只发一次 PUT")
    func createSendsNoSHA() async throws {
        let files = ScriptedWriteSource()

        _ = try await makeSaveFile(files: files).run(
            fullName: "octocat/hello",
            path: RepoPath(path: "NewFile.swift"),
            content: Data("// 新建".utf8),
            draft: draft(target: .currentBranch),
            sha: nil,
            currentBranch: "main"
        )

        #expect(await files.puts.first?.sha == nil, "⚠️ 带上 sha 就变成「更新一个不存在的文件」")
    }

    @Test("⚠️ 提交信息为空 ⇒ 发出去的是默认信息（不是空串）")
    func emptyMessageFallsBackToDefault() async throws {
        let files = ScriptedWriteSource()

        _ = try await makeSaveFile(files: files).run(
            fullName: "octocat/hello", path: path, content: Data(),
            draft: draft(message: "   ", target: .currentBranch),
            sha: nil, currentBranch: "main"
        )

        #expect(await files.puts.first?.message == "update via GitDuo")
    }

    @Test("⚠️ 409（版本基准过期）**照旧抛**，调用方靠 `FileWriteFailure` 认出它并换出两个出口")
    func conflictPropagates() async throws {
        let files = ScriptedWriteSource(put: .failure(.conflict))

        await #expect(throws: GitHubError.conflict) {
            _ = try await self.makeSaveFile(files: files).run(
                fullName: "octocat/hello", path: path, content: Data(),
                draft: draft(target: .currentBranch), sha: "old", currentBranch: "main"
            )
        }
        #expect(FileWriteFailure(.conflict) == .conflict)
        #expect(FileWriteFailure(.conflict).offersConflictExits)
    }

    @Test("⚠️ 422（路径上已有文件）被认成「目标已存在」，而不是笼统的「提交失败」")
    func validationIsRecognisedAsExistingFile() async throws {
        let files = ScriptedWriteSource(put: .failure(.validation(["sha: wasn't supplied"])))

        await #expect(throws: GitHubError.validation(["sha: wasn't supplied"])) {
            _ = try await self.makeSaveFile(files: files).run(
                fullName: "octocat/hello", path: path, content: Data(),
                draft: draft(target: .currentBranch), sha: nil, currentBranch: "main"
            )
        }
        #expect(FileWriteFailure(.validation([])) == .destinationExists)
        #expect(FileWriteFailure(.validation([])).offersConflictExits == false,
                "⚠️ 422 不给「两个出口」—— 那是 409 的东西，混了会让用户以为覆盖一下就过去了")
    }

    // MARK: - 「新分支 + PR」那一档（三步）

    @Test("⚠️ 三步的**次序**：建分支 → 提交到新分支 → 建 PR；`base` = 当前分支、`head` = 新分支")
    func newBranchRunsThreeStepsInOrder() async throws {
        let files = ScriptedWriteSource()
        let branches = ScriptedBranchSource()
        let pulls = ScriptedPullCreationSource(number: 58)

        let target = FileWriteTarget.newBranch(name: "gitduo/x", prTitle: "加个入口")
        let outcome = try await makeSaveFile(files: files, branches: branches, pulls: pulls).run(
            fullName: "octocat/hello",
            path: path,
            content: Data("let a = 1".utf8),
            draft: draft(message: "改一行", target: target),
            sha: "sha-baseline",
            currentBranch: "main",
            headSHA: "head-1"
        )

        #expect(outcome == .createdBranchAndPull(
            branch: "gitduo/x",
            receipt: FileSaveReceipt(path: path, blobSHA: "sha-new", commitSHA: "c0ffee"),
            pullNumber: 58
        ))
        #expect(await branches.creates == [.init(name: "gitduo/x", sha: "head-1")])
        #expect(await branches.branchReads.isEmpty, "手上已经有 head-1，没有理由再问一次")
        let puts = await files.puts
        #expect(puts.count == 1)
        #expect(puts.first?.branch == "gitduo/x", "⚠️ 提交要落在**新分支**上，不是当前分支")
        #expect(await pulls.creates == [.init(title: "加个入口", head: "gitduo/x", base: "main")],
                "⚠️ 三个必填值：title 来自第二行输入、head 是新分支、base 是当前分支")
    }

    @Test("`headSHA` 拿不到 ⇒ 补一次 `GET /branches/{当前分支}`（§9.7.1 的取法）")
    func fallsBackToASingleBranchRead() async throws {
        let files = ScriptedWriteSource()
        let branches = ScriptedBranchSource(
            branch: .success(BranchDTO(name: "main", commitSHA: "head-9", protected: false))
        )

        _ = try await makeSaveFile(files: files, branches: branches).run(
            fullName: "octocat/hello", path: path, content: Data(),
            draft: draft(target: .newBranch(name: "gitduo/y", prTitle: "t")),
            sha: nil, currentBranch: "main"
        )

        #expect(await branches.branchReads == ["main"])
        #expect(await branches.creates == [.init(name: "gitduo/y", sha: "head-9")])
    }

    @Test("⚠️ 分支名先过客户端校验（trim 后再判）：不合法 ⇒ 抛 `BranchCreationError`，**一个请求都不发**")
    func invalidBranchNameIsRejectedBeforeAnyRequest() async throws {
        let files = ScriptedWriteSource()
        let branches = ScriptedBranchSource()

        await #expect(throws: BranchCreationError.invalidName(.containsDoubleDot)) {
            _ = try await self.makeSaveFile(files: files, branches: branches).run(
                fullName: "octocat/hello", path: path, content: Data(),
                draft: draft(target: .newBranch(name: "a..b", prTitle: "t")),
                sha: nil, currentBranch: "main"
            )
        }
        #expect(await branches.creates.isEmpty)
        #expect(await files.puts.isEmpty)
    }

    @Test("⚠️ 分支名里的首尾空格被宽容（与 `CreateBranch` 逐字同一套：先 trim 再校验）")
    func branchNameIsTrimmed() async throws {
        let files = ScriptedWriteSource()
        let branches = ScriptedBranchSource()

        _ = try await makeSaveFile(files: files, branches: branches).run(
            fullName: "octocat/hello", path: path, content: Data(),
            draft: draft(target: .newBranch(name: "  gitduo/z  ", prTitle: "t")),
            sha: nil, currentBranch: "main", headSHA: "h"
        )

        #expect(await branches.creates == [.init(name: "gitduo/z", sha: "h")])
    }

    @Test("⚠️ 第 1 步（建分支）失败 ⇒ **什么都不该发生**，照旧抛出去")
    func branchCreationFailureThrowsAndWritesNothing() async throws {
        let files = ScriptedWriteSource()
        let branches = ScriptedBranchSource(create: .failure(.forbidden("no")))

        await #expect(throws: GitHubError.forbidden("no")) {
            _ = try await self.makeSaveFile(files: files, branches: branches).run(
                fullName: "octocat/hello", path: path, content: Data(),
                draft: draft(target: .newBranch(name: "gitduo/x", prTitle: "t")),
                sha: nil, currentBranch: "main", headSHA: "h"
            )
        }
        #expect(await files.puts.isEmpty, "分支都没建起来，不该有任何提交")
    }

    @Test("⚠️ 第 2 步失败 ⇒ 报「分支已创建、改动未提交」（分支**真的在那里了**）")
    func commitFailureAfterBranchCreationIsReportedAsPartial() async throws {
        let files = ScriptedWriteSource(put: .failure(.forbidden("push denied")))
        let branches = ScriptedBranchSource()
        let pulls = ScriptedPullCreationSource()

        let outcome = try await makeSaveFile(files: files, branches: branches, pulls: pulls).run(
            fullName: "octocat/hello", path: path, content: Data(),
            draft: draft(target: .newBranch(name: "gitduo/x", prTitle: "t")),
            sha: nil, currentBranch: "main", headSHA: "h"
        )

        #expect(outcome == .branchCreatedButCommitFailed(branch: "gitduo/x", reason: .forbidden("push denied")))
        #expect(outcome.didWrite == false, "改动没进去")
        #expect(await branches.creates.count == 1, "⚠️ 分支确实建出来了 —— 文案必须说出来")
        #expect(await pulls.creates.isEmpty, "提交都没成，不该去建 PR")
    }

    @Test("⚠️ 第 3 步失败 ⇒ 报「改动已提交、PR 未创建」（内容**真的进去了**）")
    func pullCreationFailureIsReportedAsPartial() async throws {
        let files = ScriptedWriteSource()
        let pulls = ScriptedPullCreationSource(failure: .validation(["base: invalid"]))

        let outcome = try await makeSaveFile(files: files, pulls: pulls).run(
            fullName: "octocat/hello", path: path, content: Data(),
            draft: draft(target: .newBranch(name: "gitduo/x", prTitle: "t")),
            sha: nil, currentBranch: "main", headSHA: "h"
        )

        #expect(outcome == .committedButPullCreationFailed(
            branch: "gitduo/x",
            receipt: FileSaveReceipt(path: path, blobSHA: "sha-new", commitSHA: "c0ffee"),
            reason: .validation(["base: invalid"])
        ))
        #expect(outcome.didWrite, "⚠️ 这次改动**真的进了那条新分支** —— 报「提交失败」是假话")
    }

    @Test("⚠️ 收据里的 `blobSHA` 与 `commitSHA` 是**两个不同的东西**（混了会让下次编辑必 409）")
    func receiptKeepsBothSHAsDistinct() async throws {
        let files = ScriptedWriteSource(put: .success(.stub(blobSHA: "blob-a", commitSHA: "commit-b")))

        let outcome = try await makeSaveFile(files: files).run(
            fullName: "octocat/hello", path: path, content: Data(),
            draft: draft(target: .currentBranch), sha: nil, currentBranch: "main"
        )

        guard case let .committedToCurrentBranch(receipt) = outcome else {
            Issue.record("当前分支那一档应当直接成功")
            return
        }
        #expect(receipt.blobSHA == "blob-a")
        #expect(receipt.commitSHA == "commit-b")
    }

    @Test("`fullName` 形状不对 ⇒ 抛形状错误且不发请求")
    func malformedFullNameIsRejected() async throws {
        let files = ScriptedWriteSource()

        await #expect(throws: RepositoryMappingError.malformedFullName("octocat")) {
            _ = try await self.makeSaveFile(files: files).run(
                fullName: "octocat", path: path, content: Data(),
                draft: draft(target: .currentBranch), sha: nil, currentBranch: "main"
            )
        }
        #expect(await files.puts.isEmpty)
    }

    @Test("⚠️ 写上限与读那一侧的内联上限是同一个数（不另立常量）")
    func maxContentBytesMatchesReadSide() {
        #expect(SaveFile.maxContentBytes == FilePreviewKind.maxInlineTextBytes)
    }
}

// MARK: - RenameFile

/// 重命名（§9.6.5、PRD §5.16、决策 #66 / #68②）。
@Suite("重命名文件 · 两步串行 / 两个都在 / 目标判据")
struct RenameFileTests {

    private let source = RepoPath(path: "Sources/a.swift")
    private let destination = RepoPath(path: "Sources/b.swift")

    // MARK: - 目标路径的判据（纯函数）

    @Test("空 / 全空白 ⇒ `.empty`（提示「先输入文件路径」）")
    func emptyDestinationIsRejected() {
        #expect(RepoPath.resolveRenameDestination(from: source, input: "") == .rejected(.empty))
        #expect(RepoPath.resolveRenameDestination(from: source, input: "   \n ") == .rejected(.empty))
    }

    @Test("⚠️ 与源相同（含只差首尾空格）⇒ `.unchanged` —— 视图据此**直接关闭、什么都不提示**")
    func unchangedDestinationIsRejectedSilently() {
        #expect(RepoPath.resolveRenameDestination(from: source, input: "Sources/a.swift") == .rejected(.unchanged))
        #expect(RepoPath.resolveRenameDestination(from: source, input: "  Sources/a.swift  ") == .rejected(.unchanged))
        // 前导 `/` 是同一个路径（`RepoPath.init(path:)` 会剥掉它）。
        #expect(RepoPath.resolveRenameDestination(from: source, input: "/Sources/a.swift") == .rejected(.unchanged))
    }

    @Test("⚠️ `a//b` **不是** `a/b` —— 默认的 `split` 会静默吃掉空段，这里必须当成错误")
    func doubleSlashIsRejected() {
        let outcome = RepoPath.resolveRenameDestination(from: source, input: "Sources//b.swift")
        #expect(outcome == .rejected(.invalidComponent("")))
    }

    @Test("⚠️ 前导 `/` 宽容一次（用户常从网页端抄路径），但 `//` 仍然拦")
    func leadingSlashIsToleratedOnce() {
        #expect(
            RepoPath.resolveRenameDestination(from: source, input: "/docs/a.md")
                == .acceptable(RepoPath(path: "docs/a.md"))
        )
        // 剥一次之后还剩一个前导 `/` ⇒ 空段 ⇒ 拦下（`//a` 不是一条合法路径）。
        #expect(
            RepoPath.resolveRenameDestination(from: source, input: "//docs/a.md")
                == .rejected(.invalidComponent(""))
        )
    }

    @Test("`. ` / `..` 作为一级 ⇒ `.invalidComponent` 并带上那一级（`..` 会跳到别的目录去）")
    func relativeSegmentsAreRejected() {
        #expect(RepoPath.resolveRenameDestination(from: source, input: "../b.swift")
            == .rejected(.invalidComponent("..")))
        #expect(RepoPath.resolveRenameDestination(from: source, input: "Sources/./b.swift")
            == .rejected(.invalidComponent(".")))
    }

    @Test("合法的多级路径通过，且**首尾空格被 trim 掉**（它会成为一个真实文件名）")
    func validDestinationIsTrimmed() {
        #expect(
            RepoPath.resolveRenameDestination(from: source, input: "  docs/guide.md  ")
                == .acceptable(RepoPath(path: "docs/guide.md"))
        )
    }

    @Test("⚠️ 只改名不换目录也合法（`b.swift` 落在仓库根，不是「改到源文件旁边」）")
    func plainNameLandsAtRoot() {
        #expect(
            RepoPath.resolveRenameDestination(from: source, input: "b.swift")
                == .acceptable(RepoPath(path: "b.swift"))
        )
    }

    // MARK: - 两步串行

    @Test("⚠️ 次序：读源 → PUT 新（`sha: nil`）→ DELETE 旧（带**旧** sha）")
    func renameRunsThreeCallsInOrder() async throws {
        let reads = ScriptedReadSource.file(sha: "sha-old", text: "abc")
        let files = ScriptedWriteSource()

        let outcome = try await RenameFile(contents: reads, files: files).run(
            fullName: "octocat/hello",
            source: source,
            destination: destination,
            message: "改名",
            branch: "feature/x"
        )

        #expect(outcome == .renamed(to: destination))
        #expect(await reads.reads.map(\.path) == ["Sources/a.swift"])
        #expect(await reads.reads.map(\.ref) == ["feature/x"], "⚠️ 读也要带 ref，否则拿到的是默认分支的内容")

        let puts = await files.puts
        #expect(puts.count == 1)
        #expect(puts.first?.path == "Sources/b.swift")
        #expect(puts.first?.sha == nil, "⚠️ 新路径是一次**新建**；带上 sha 会 422")
        #expect(puts.first?.content == Data("abc".utf8))
        #expect(puts.first?.branch == "feature/x")

        let deletes = await files.deletes
        #expect(deletes.count == 1)
        #expect(deletes.first?.path == "Sources/a.swift")
        #expect(deletes.first?.sha == "sha-old", "⚠️ 删要带**旧** sha（官方必填）")
    }

    @Test("⚠️ 两个写动作必须**串行**：POST 完成之前 DELETE 不能出现在记录里")
    func writesAreSerialNotConcurrent() async throws {
        let files = ScriptedWriteSource()
        let reads = ScriptedReadSource.file()

        _ = try await RenameFile(contents: reads, files: files).run(
            fullName: "octocat/hello", source: source, destination: destination,
            message: nil, branch: "main"
        )

        // 记录只有一份、且 PUT 在后 DELETE 之前 ⇒ 两次写确有先后（不是并发发出）。
        #expect(await files.puts.count == 1)
        #expect(await files.deletes.count == 1)
    }

    @Test("⚠️ PUT 撞上 422 ⇒ `.destinationExists`，且**不发 DELETE**（不然会删掉源文件、什么都没建）")
    func destinationExistsStopsBeforeDelete() async throws {
        let reads = ScriptedReadSource.file()
        let files = ScriptedWriteSource(put: .failure(.validation(["sha: wasn't supplied"])))

        let outcome = try await RenameFile(contents: reads, files: files).run(
            fullName: "octocat/hello", source: source, destination: destination,
            message: nil, branch: "main"
        )

        #expect(outcome == .destinationExists)
        #expect(outcome.didRename == false)
        #expect(await files.deletes.isEmpty, "⚠️ 目标写不进去时删源文件 = 把两个都弄丢")
    }

    @Test("⚠️ 第一步成了、第二步失败 ⇒ `.movedButOldRemains`（仓库里**两个文件都在**）")
    func deleteFailureYieldsPartialRename() async throws {
        let reads = ScriptedReadSource.file()
        let files = ScriptedWriteSource(delete: .failure(.forbidden("protected")))

        let outcome = try await RenameFile(contents: reads, files: files).run(
            fullName: "octocat/hello", source: source, destination: destination,
            message: nil, branch: "main"
        )

        #expect(outcome == .movedButOldRemains(newPath: destination, reason: .forbidden("protected")))
        #expect(outcome.didRename == false, "⚠️ 用户要的结果没达到 —— 两个都在")
    }

    @Test("⚠️ DELETE 回 404 ⇒ 如实报**成功**（旧路径本来就不在了，终态正是用户要的）")
    func deleteNotFoundCountsAsSuccess() async throws {
        let reads = ScriptedReadSource.file()
        let files = ScriptedWriteSource(delete: .failure(.notFound))

        let outcome = try await RenameFile(contents: reads, files: files).run(
            fullName: "octocat/hello", source: source, destination: destination,
            message: nil, branch: "main"
        )

        #expect(outcome == .renamed(to: destination))
        #expect(outcome.didRename, "照 404 报「两个都在」是假话 —— 用户会去找一个不存在的文件")
    }

    @Test("源文件 404 ⇒ `.sourceUnavailable(.gone)`，一个写请求都不发")
    func missingSourceIsReportedAsGone() async throws {
        let reads = ScriptedReadSource(reply: .failure(.notFound))
        let files = ScriptedWriteSource()

        let outcome = try await RenameFile(contents: reads, files: files).run(
            fullName: "octocat/hello", source: source, destination: destination,
            message: nil, branch: "main"
        )

        #expect(outcome == .sourceUnavailable(.gone))
        #expect(await files.puts.isEmpty)
        #expect(await files.deletes.isEmpty)
    }

    @Test("⚠️ 源文件 >1MB（`encoding: none` + 空 content）⇒ `.notWritable`，**不是** `.gone`")
    func oversizedSourceIsNotWritableNotGone() async throws {
        let reads = ScriptedReadSource(reply: .success(RepoFileDTO(
            name: "big.swift", path: "Sources/a.swift", sha: "sha-big",
            size: 4_280_356, encoding: "none", content: ""
        )))
        let files = ScriptedWriteSource()

        let outcome = try await RenameFile(contents: reads, files: files).run(
            fullName: "octocat/hello", source: source, destination: destination,
            message: nil, branch: "main"
        )

        #expect(outcome == .sourceUnavailable(.notWritable))
        #expect(await files.puts.isEmpty)
    }

    @Test("⚠️ 0 字节的文件**可以**重命名（`decodeBase64` 对空串有意返回 nil，这里要特判）")
    func emptySourceIsStillWritable() async throws {
        let reads = ScriptedReadSource(reply: .success(RepoFileDTO(
            name: "empty.txt", path: "Sources/a.swift", sha: "sha-empty",
            size: 0, encoding: "base64", content: ""
        )))
        let files = ScriptedWriteSource()

        let outcome = try await RenameFile(contents: reads, files: files).run(
            fullName: "octocat/hello", source: source, destination: destination,
            message: nil, branch: "main"
        )

        #expect(outcome == .renamed(to: destination))
        #expect(await files.puts.first?.content == Data(), "空文件写出去的是零个字节")
    }

    @Test("⚠️ 服务端的 base64 是**带换行**的（每 60 字符插一个）—— 复用 `FileContentCodec` 才能解开")
    func wrappedBase64IsDecoded() async throws {
        let text = String(repeating: "a", count: 200)
        let wrapped = Data(text.utf8).base64EncodedString()
            .enumerated()
            .reduce(into: "") { result, pair in
                if pair.offset > 0, pair.offset % 60 == 0 { result.append("\n") }
                result.append(pair.element)
            }
        let reads = ScriptedReadSource(reply: .success(RepoFileDTO(
            name: "a.swift", path: "Sources/a.swift", sha: "sha", size: 200,
            encoding: "base64", content: wrapped
        )))
        let files = ScriptedWriteSource()

        _ = try await RenameFile(contents: reads, files: files).run(
            fullName: "octocat/hello", source: source, destination: destination,
            message: nil, branch: "main"
        )

        #expect(await files.puts.first?.content == Data(text.utf8))
    }

    @Test("提交信息为空 ⇒ 默认信息（重命名没有输入框）")
    func renameUsesDefaultMessage() async throws {
        let reads = ScriptedReadSource.file()
        let files = ScriptedWriteSource()

        _ = try await RenameFile(contents: reads, files: files).run(
            fullName: "octocat/hello", source: source, destination: destination,
            message: "   ", branch: "main"
        )

        #expect(await files.puts.first?.message == "update via GitDuo")
        #expect(await files.deletes.first?.message == "update via GitDuo")
    }

    @Test("`fullName` 形状不对 ⇒ 抛形状错误且一个请求都不发")
    func malformedFullNameIsRejected() async throws {
        let reads = ScriptedReadSource.file()
        let files = ScriptedWriteSource()

        await #expect(throws: RepositoryMappingError.malformedFullName("octocat")) {
            _ = try await RenameFile(contents: reads, files: files).run(
                fullName: "octocat", source: source, destination: destination,
                message: nil, branch: "main"
            )
        }
        #expect(await reads.reads.isEmpty)
    }
}

// MARK: - DeleteFile

/// 删除文件（§9.6.5、PRD §5.17）。
@Suite("删除文件 · 现取 sha / 已经不在了不是错误")
struct DeleteFileTests {

    private let path = RepoPath(path: "Sources/a.swift")

    @Test("⚠️ 次序：先**现取** sha，再带着它删（官方两个都必填）")
    func deleteFetchesFreshSHAThatSendsIt() async throws {
        let reads = ScriptedReadSource.file(sha: "sha-now")
        let files = ScriptedWriteSource()

        let outcome = try await DeleteFile(contents: reads, files: files).run(
            fullName: "octocat/hello", path: path, message: "删掉它", branch: "feature/x"
        )

        #expect(outcome == .deleted)
        #expect(await reads.reads.map(\.ref) == ["feature/x"])
        let deletes = await files.deletes
        #expect(deletes.count == 1)
        #expect(deletes.first?.sha == "sha-now")
        #expect(deletes.first?.message == "删掉它")
        #expect(deletes.first?.branch == "feature/x", "⚠️ `branch` 恒传（决策 #65）")
    }

    @Test("⚠️ 文件已经被删掉（404）⇒ `.alreadyGone`，**不报「删除失败」**、也不发 DELETE")
    func alreadyGoneIsNotAFailure() async throws {
        let reads = ScriptedReadSource(reply: .failure(.notFound))
        let files = ScriptedWriteSource()

        let outcome = try await DeleteFile(contents: reads, files: files).run(
            fullName: "octocat/hello", path: path, message: nil, branch: "main"
        )

        #expect(outcome == .alreadyGone)
        #expect(await files.deletes.isEmpty)
    }

    @Test("这个 path 上已经不是文件（目录）⇒ 同样按 `.alreadyGone` 处置")
    func directoryPayloadCountsAsGone() async throws {
        let reads = ScriptedReadSource(reply: .success(nil))
        let files = ScriptedWriteSource()

        let outcome = try await DeleteFile(contents: reads, files: files).run(
            fullName: "octocat/hello", path: path, message: nil, branch: "main"
        )

        #expect(outcome == .alreadyGone)
        #expect(await files.deletes.isEmpty, "DELETE 一个目录会 422 —— 与其发出去再解释，不如就地给结论")
    }

    @Test("⚠️ 读源失败但**不是** 404（断网 / 配额）⇒ 照旧抛 —— 不能降级成「当作它不在了」")
    func nonNotFoundReadFailurePropagates() async throws {
        let reads = ScriptedReadSource(reply: .failure(.transport(URLError(.notConnectedToInternet))))
        let files = ScriptedWriteSource()

        await #expect(throws: GitHubError.transport(URLError(.notConnectedToInternet))) {
            _ = try await DeleteFile(contents: reads, files: files).run(
                fullName: "octocat/hello", path: path, message: nil, branch: "main"
            )
        }
        #expect(await files.deletes.isEmpty, "⚠️ 把断网当成「别人删了」会让用户以为文件没了")
    }

    @Test("DELETE 本身失败 ⇒ 抛出去（`GitHubError` 九档各自说清楚，不在这里造笼统的失败档）")
    func deleteFailurePropagates() async throws {
        let reads = ScriptedReadSource.file()
        let files = ScriptedWriteSource(delete: .failure(.forbidden("protected branch")))

        await #expect(throws: GitHubError.forbidden("protected branch")) {
            _ = try await DeleteFile(contents: reads, files: files).run(
                fullName: "octocat/hello", path: path, message: nil, branch: "main"
            )
        }
    }

    @Test("提交信息为空 ⇒ 默认信息（删除没有输入框）")
    func deleteUsesDefaultMessage() async throws {
        let reads = ScriptedReadSource.file()
        let files = ScriptedWriteSource()

        _ = try await DeleteFile(contents: reads, files: files).run(
            fullName: "octocat/hello", path: path, message: "", branch: "main"
        )

        #expect(await files.deletes.first?.message == "update via GitDuo")
    }
}
