import Foundation
import GitDuoKit
import Testing

@testable import GitDuo

/// 上传目标的**落盘实现**（`UserDefaultsUploadTargetStore`）与上下文存储。
///
/// ## ⚠️ 为什么 App 层也要有测试
///
/// 这个落盘实现**在 App 层**（`GitDuo/App/Stores/UploadStores.swift`），
/// 而落盘这一份**没有领域层的单测**（领域层只有 `InMemoryUploadTargetStore` 那个参照实现）。
/// 存储是最容易"看着对、读出来是空"的地方 —— 键名写错、类型转换失败、忘记删键，
/// 三种错法在界面上都表现为"我明明选过，它却说不记得"。
@MainActor
@Suite struct UploadTargetStoreTests {

    /// 每次用一个**独立**的 suite 名（不碰 `.standard`）——
    /// 否则测试之间会互相看见对方写的键。
    private func makeStore() -> UserDefaultsUploadTargetStore {
        UserDefaultsUploadTargetStore(suiteName: "GitDuoTests.uploadTarget.\(UUID().uuidString)")
    }

    @Test func 记下来能读回来()
    async {
        let store = makeStore()
        let target = UploadTarget(
            fullName: "jwker/my-app",
            directory: RepoPath(path: "assets/photos"),
            branch: "main"
        )
        await store.remember(target)
        #expect(await store.target() == target)
    }

    @Test func 从没记过时是空()
    async {
        let store = makeStore()
        #expect(await store.target() == nil)
    }

    @Test func 清空之后读不到()
    async {
        let store = makeStore()
        await store.remember(
            UploadTarget(fullName: "jwker/my-app", directory: .root, branch: "main")
        )
        await store.clear()
        #expect(await store.target() == nil)
    }

    @Test func 根目录那一格存的是空串而不是斜杠()
    async {
        let store = makeStore()
        await store.remember(
            UploadTarget(fullName: "jwker/my-app", directory: .root, branch: "main")
        )
        let loaded = await store.target()
        #expect(loaded?.directory.isRoot == true)
        #expect(loaded?.directory.raw.isEmpty == true)
    }

    @Test func 上下文是瞬时的：写了能读，不落盘()
    async {
        let store = UploadContextStore()
        #expect(await store.current() == nil)
        let target = UploadTarget(
            fullName: "jwker/my-app",
            directory: RepoPath(path: "src"),
            branch: "dev"
        )
        await store.set(target)
        #expect(await store.current() == target)
        await store.set(nil)
        #expect(await store.current() == nil)
    }

    @Test func 离开页面时只清还是自己写的那份()
    async {
        let store = UploadContextStore()
        let mine = UploadTarget(fullName: "jwker/mine", directory: .root, branch: "main")
        let someoneElse = UploadTarget(fullName: "jwker/other", directory: .root, branch: "main")

        await store.set(mine)
        // 另一个页面已经写了更新的值 ⇒ 这一页的离开**不许**把它抹掉。
        await store.set(someoneElse)
        await store.clear(ifCurrentIs: mine)
        #expect(await store.current() == someoneElse)

        // 当前值就是自己写的那份 ⇒ 清掉。
        await store.clear(ifCurrentIs: someoneElse)
        #expect(await store.current() == nil)
    }
}
