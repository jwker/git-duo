import Foundation
import Testing

@testable import GitDuoKit

/// `UploadTarget` / `UploadTargetResolver` / `UploadTargetPath` 的契约。
///
/// ⚠️ 这些规则是**写操作**的规则（上传 = 往仓库里写东西），
/// 所以它们必须被单测钉住 —— 错了会写错仓库或写错目录。
struct UploadTargetTests {

    // MARK: - 回落规则

    @Test("上下文优先：站在某个仓库里时用当前仓库与目录，不拿记忆")
    func contextWins() {
        let remembered = UploadTarget(
            fullName: "jwker/other",
            directory: RepoPath(path: "assets"),
            branch: "main"
        )
        let context = UploadTarget(
            fullName: "jwker/here",
            directory: RepoPath(path: "src/app"),
            branch: "dev"
        )
        let resolved = UploadTargetResolver.resolve(
            remembered: remembered,
            context: context,
            facts: UploadTargetFacts(
                repositoryExists: true,
                directoryExists: true,
                branchExists: true,
                defaultBranch: "main"
            )
        )
        #expect(resolved == context)
    }

    @Test("没有上下文时才用记忆")
    func fallsBackToMemory() {
        let remembered = UploadTarget(
            fullName: "jwker/my-app",
            directory: RepoPath(path: "assets/photos"),
            branch: "main"
        )
        let resolved = UploadTargetResolver.resolve(
            remembered: remembered,
            context: nil,
            facts: UploadTargetFacts(
                repositoryExists: true,
                directoryExists: true,
                branchExists: true,
                defaultBranch: "main"
            )
        )
        #expect(resolved == remembered)
    }

    @Test("仓库没了 ⇒ 回落成「还没选」（不猜一个仓库）")
    func repositoryGoneYieldsNil() {
        let remembered = UploadTarget(
            fullName: "jwker/gone",
            directory: RepoPath(path: "assets"),
            branch: "main"
        )
        let resolved = UploadTargetResolver.resolve(
            remembered: remembered,
            context: nil,
            facts: UploadTargetFacts(
                repositoryExists: false,
                directoryExists: true,
                branchExists: true,
                defaultBranch: "main"
            )
        )
        #expect(resolved == nil)
    }

    @Test("目录没了 ⇒ 落到仓库根")
    func directoryGoneFallsBackToRoot() {
        let remembered = UploadTarget(
            fullName: "jwker/my-app",
            directory: RepoPath(path: "assets/photos"),
            branch: "main"
        )
        let resolved = UploadTargetResolver.resolve(
            remembered: remembered,
            context: nil,
            facts: UploadTargetFacts(
                repositoryExists: true,
                directoryExists: false,
                branchExists: true,
                defaultBranch: "main"
            )
        )
        #expect(resolved?.directory == .root)
        #expect(resolved?.fullName == "jwker/my-app")
    }

    @Test("分支没了 ⇒ 落到默认分支")
    func branchGoneFallsBackToDefault() {
        let remembered = UploadTarget(
            fullName: "jwker/my-app",
            directory: RepoPath(path: "assets"),
            branch: "deleted-branch"
        )
        let resolved = UploadTargetResolver.resolve(
            remembered: remembered,
            context: nil,
            facts: UploadTargetFacts(
                repositoryExists: true,
                directoryExists: true,
                branchExists: false,
                defaultBranch: "main"
            )
        )
        #expect(resolved?.branch == "main")
    }

    @Test("什么都没记过 ⇒ 还没选")
    func nothingRemembered() {
        let resolved = UploadTargetResolver.resolve(
            remembered: nil,
            context: nil,
            facts: UploadTargetFacts(
                repositoryExists: true,
                directoryExists: true,
                branchExists: true,
                defaultBranch: "main"
            )
        )
        #expect(resolved == nil)
    }

    // MARK: - 路径

    @Test("复制出去的路径带仓库名")
    func displayPathCarriesRepositoryName() {
        #expect(
            UploadTargetPath.displayPath(
                fullName: "jwker/my-app",
                directory: RepoPath(path: "assets/photos"),
                fileName: "photo-20261017-143012.jpg"
            ) == "jwker/my-app/assets/photos/photo-20261017-143012.jpg"
        )
    }

    @Test("根目录时路径是「仓库名/文件名」")
    func displayPathAtRoot() {
        #expect(
            UploadTargetPath.displayPath(
                fullName: "jwker/my-app",
                directory: .root,
                fileName: "photo.jpg"
            ) == "jwker/my-app/photo.jpg"
        )
    }

    @Test("⚠️ 与 RepoCopy.clipboardPath 不是一回事：那边给的是仓库内路径")
    func differsFromRepoClipboardPath() {
        let path = RepoPath(path: "assets/photos")
        #expect(RepoCopy.clipboardPath(for: path, fullName: "jwker/my-app") == "assets/photos")
        #expect(
            UploadTargetPath.displayPath(
                fullName: "jwker/my-app",
                directory: path,
                fileName: "photo.jpg"
            ) == "jwker/my-app/assets/photos/photo.jpg"
        )
    }

    // MARK: - 记忆

    @Test("记忆能存能取能清")
    func storeRoundTrip() async {
        let store = InMemoryUploadTargetStore()
        #expect(await store.target() == nil)

        let target = UploadTarget(
            fullName: "jwker/my-app",
            directory: RepoPath(path: "assets"),
            branch: "main"
        )
        await store.remember(target)
        #expect(await store.target() == target)

        await store.clear()
        #expect(await store.target() == nil)
    }

    @Test("摘要一行写全仓库 · 目录 · 分支")
    func summaryCarriesAllThree() {
        let target = UploadTarget(
            fullName: "jwker/my-app",
            directory: RepoPath(path: "assets/photos"),
            branch: "main"
        )
        #expect(target.summary == "jwker/my-app · assets/photos · main")
        #expect(target.directoryDisplay == "assets/photos")
    }
}
