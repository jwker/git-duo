import Foundation
import Testing

@testable import GitDuoKit

/// 收藏夹的归属与计数（PRD §4.19、TECH_SPEC §9.12）。
///
/// ## 这一套守的是什么
///
/// 原型第一版给每个夹配了**独立计数器**，于是"删除收藏夹时把里面的项搬去默认夹"
/// 那一步会让默认夹那一格**纹丝不动**（`TECH_SPEC §9.12` 记着这次踩坑）。
/// 现在的口径是**计数纯派生**（= 归属映射里值等于该夹名的条目数）。
///
/// 所以下面每一条都会**同时**断言"归属变成了什么"与"各夹的计数变成了多少"——
/// 只断言其中一半，当年那个 bug 就会从缝里漏过去
/// （它有归属、有计数，两个数各自看都说得过去，凑在一起才是假的）。
@Suite("收藏夹 · 归属与计数（§9.12 归属表）")
struct FolderStoreTests {

    private let alpha = "a/one"
    private let beta = "b/two"
    private let gamma = "c/three"

    /// 一次把"这个夹几项"全部取回来，用整份字典做断言 ——
    /// 比逐个 `count(in:)` 强的地方是**顺带钉住"没有多余的夹"**。
    private func counts(_ store: InMemoryFolderStore) async -> [String: Int] {
        let summaries = await store.summaries()
        return Dictionary(uniqueKeysWithValues: summaries.map { ($0.name, $0.itemCount) })
    }

    // MARK: - 默认夹的存在性与位置

    @Test("默认收藏夹恒在**第一位**（顺序就是展示顺序，不是创建顺序）")
    func defaultFolderIsAlwaysFirst() async {
        let store = InMemoryFolderStore(seed: [Folder(name: "以后再看"), Folder(name: "给老板看的")])

        #expect(await store.folderNames() == [FolderDefaults.name, "以后再看", "给老板看的"])
    }

    @Test("预置里默认夹排在中间 ⇒ 挪到首位（否则新收藏会掉进列表中间那一行）")
    func defaultFolderIsMovedToFront() async {
        let store = InMemoryFolderStore(seed: [Folder(name: "以后再看"), Folder(name: FolderDefaults.name)])

        #expect(await store.folderNames() == [FolderDefaults.name, "以后再看"])
    }

    @Test("预置同名夹只留一个（保留先出现的）—— 否则「重名判定」会自相矛盾")
    func duplicateSeedsKeepTheFirst() async {
        let store = InMemoryFolderStore(seed: [Folder(name: "x"), Folder(name: "x"), Folder(name: "y")])

        #expect(await store.folderNames() == [FolderDefaults.name, "x", "y"])
    }

    @Test("预置里的空名被丢掉（否则「我的收藏」会多出一行没有名字的夹）")
    func blankSeedsAreDropped() async {
        let store = InMemoryFolderStore(seed: [Folder(name: "   "), Folder(name: "x")])

        #expect(await store.folderNames() == [FolderDefaults.name, "x"])
    }

    @Test("⚠️ 归属指向一个不存在的夹 ⇒ **回落默认夹**，而不是把那条收藏丢掉")
    func danglingFavoritesFallBackToDefault() async {
        // 磁盘上的旧数据可能来自一个"删了一半"的版本 —— 那时归属还在、夹已经没了。
        // 丢掉那条归属的表现是"用户一夜之间少了几条收藏"，而回落至少保住了
        // "它还被收藏着"这个事实（与删夹回落是同一条规则，§9.12 归属表第 6 行）。
        let store = InMemoryFolderStore(
            seed: [Folder(name: "x")],
            favorites: [alpha: "已经没有的夹"]
        )

        #expect(await counts(store) == [FolderDefaults.name: 1, "x": 0])
        #expect(await store.folder(ofRepo: alpha) == FolderDefaults.name)
    }

    // MARK: - §9.12 归属表逐行

    @Test("① 首次收藏：`previous` 是 `nil` —— 界面据此说「已加入收藏」而不是「已移动」")
    func firstFavoriteHasNilPrevious() async {
        let store = InMemoryFolderStore(seed: [Folder(name: "x")])

        let outcome = await store.move(repo: alpha, to: "x")

        #expect(outcome == .moved(previous: nil, current: "x"))
        #expect(await counts(store) == [FolderDefaults.name: 0, "x": 1])
    }

    @Test("② 换夹：旧夹 −1、新夹 +1，**总数不变**")
    func movingBetweenFoldersKeepsTheTotal() async {
        let store = InMemoryFolderStore(
            seed: [Folder(name: "x"), Folder(name: "y")],
            favorites: [alpha: "x", beta: "x"]
        )

        let outcome = await store.move(repo: alpha, to: "y")

        #expect(outcome == .moved(previous: "x", current: "y"))
        // 两个数一起断言：只减不加（或只加不减）都会让总数变成 3，
        // 而屏幕上只是"某一格数字不对"，看不出是哪一步出了错。
        #expect(await counts(store) == [FolderDefaults.name: 0, "x": 1, "y": 1])
    }

    @Test("③ 取消收藏：只删归属，所属夹自动 −1")
    func removalDecrementsItsFolder() async {
        let store = InMemoryFolderStore(
            seed: [Folder(name: "x")],
            favorites: [alpha: "x", beta: "x"]
        )

        let removed = await store.remove(repo: alpha)

        #expect(removed)
        #expect(await store.folder(ofRepo: alpha) == nil)
        #expect(await counts(store) == [FolderDefaults.name: 0, "x": 1])
    }

    @Test("③' 取消一个本来就没收藏的 ⇒ `false`，且什么都没变（界面据此不该说「已移除」）")
    func removingUnknownRepoReportsFalse() async {
        let store = InMemoryFolderStore(seed: [Folder(name: "x")], favorites: [alpha: "x"])

        #expect(await store.remove(repo: beta) == false)
        #expect(await counts(store) == [FolderDefaults.name: 0, "x": 1])
    }

    @Test("已在目标夹里再点一次 ⇒ `unchanged`，**一个字节都没改**")
    func movingToTheCurrentFolderIsUnchanged() async {
        let store = InMemoryFolderStore(seed: [Folder(name: "x")], favorites: [alpha: "x"])

        let outcome = await store.move(repo: alpha, to: "x")

        #expect(outcome == .unchanged(folder: "x"))
        #expect(await counts(store) == [FolderDefaults.name: 0, "x": 1])
    }

    @Test("目标夹不存在 ⇒ `unknownFolder` 且**什么都不改**")
    func movingToUnknownFolderChangesNothing() async {
        // 静默吞掉它的表现是：那个仓库变成"显示已收藏、却在任何一个夹里都找不到"
        // （归属写进了一个不存在的夹名，而没有任何一行画得出它）。
        let store = InMemoryFolderStore(seed: [Folder(name: "x")], favorites: [alpha: "x"])

        let outcome = await store.move(repo: beta, to: "没有这个夹")

        #expect(outcome == .unknownFolder("没有这个夹"))
        #expect(await counts(store) == [FolderDefaults.name: 0, "x": 1])
    }

    @Test("⑤ 重命名：项目数不变，**归属跟着改名**")
    func renameCarriesItsFavoritesAlong() async {
        // 漏掉"改映射的值"这一步的表现是：项目数当场变 0，但那批仓库仍显示已收藏
        // （它们指向一个已经不存在的夹）—— 而收藏夹列表里一个空夹都不多，
        // 所以只改一半时屏幕上看起来只是"收藏被清空了"。两个断言缺一不可。
        let store = InMemoryFolderStore(
            seed: [Folder(name: "x")],
            favorites: [alpha: "x", beta: "x"]
        )

        let outcome = await store.rename(from: "x", to: "以后再看")

        #expect(outcome == .renamed(from: "x", to: "以后再看"))
        #expect(await counts(store) == [FolderDefaults.name: 0, "以后再看": 2])
        #expect(await store.folder(ofRepo: alpha) == "以后再看")
    }

    @Test("⑥ 删除：其中的收藏**先回落到默认夹**，不留指向已删夹的悬空归属")
    func deleteMovesItsItemsToDefault() async {
        let store = InMemoryFolderStore(
            seed: [Folder(name: "x")],
            favorites: [alpha: "x", beta: "x", gamma: FolderDefaults.name]
        )
        #expect(await counts(store) == [FolderDefaults.name: 1, "x": 2])

        let outcome = await store.delete(name: "x")

        // `moved` 就是删之前那个夹的项目数 —— PRD §5.14 的提示文案要用它，
        // 算错的表现是提示里那个数与用户刚看到的数字对不上。
        #expect(outcome == .deleted(name: "x", moved: 2))
        #expect(await counts(store) == [FolderDefaults.name: 3])
        #expect(await store.folder(ofRepo: alpha) == FolderDefaults.name)
        #expect(await store.folderNames() == [FolderDefaults.name])
    }
}

/// 收藏夹增删改的边界（PRD §4.19 / §5.13 / §5.14、TECH_SPEC §9.12）。
@Suite("收藏夹 · 新建 / 重命名 / 删除的边界")
struct FolderMutationTests {

    @Test("新建：排在末尾（默认夹恒在首位）、项目数为 0")
    func createAppendsToTheEnd() async {
        let store = InMemoryFolderStore()

        #expect(await store.create(name: "以后再看") == .created(name: "以后再看"))

        let summaries = await store.summaries()
        #expect(summaries.map(\.name) == [FolderDefaults.name, "以后再看"])
        #expect(summaries.allSatisfy { $0.itemCount == 0 })
    }

    @Test("新建：名字两端去空白（否则「`x `」与「`x`」会各占一行）")
    func createTrimsTheName() async {
        let store = InMemoryFolderStore()

        #expect(await store.create(name: "  x  ") == .created(name: "x"))
        #expect(await store.folderNames() == [FolderDefaults.name, "x"])
    }

    @Test("新建：空名 / 纯空白 ⇒ `emptyName`（不建、也不报错）")
    func createRejectsBlankNames() async {
        let store = InMemoryFolderStore()

        #expect(await store.create(name: "") == .emptyName)
        #expect(await store.create(name: "   ") == .emptyName)
        #expect(await store.create(name: "\n\t") == .emptyName)
        #expect(await store.folderNames() == [FolderDefaults.name])
    }

    @Test("新建：重名 ⇒ `duplicate`，**没有创建**（管理页入口「只提示不创建」）")
    func createRejectsDuplicateNames() async {
        let store = InMemoryFolderStore(seed: [Folder(name: "x")])

        #expect(await store.create(name: "x") == .duplicate(name: "x"))
        #expect(await store.folderNames() == [FolderDefaults.name, "x"])
    }

    @Test("⚠️ 重命名成**自己** ⇒ `unchanged`，不是 `duplicate`")
    func renameToItselfIsUnchangedNotDuplicate() async {
        // 这一条钉的是一个**顺序**问题：`guard name != oldName` 必须排在重名检查之前。
        // 反过来（先查重名）时"把夹名改成它自己"会撞上"已有同名收藏夹" ——
        // 而序列里明明只有它自己一个，用户会收到一句无法理解的"已有同名收藏夹"。
        let store = InMemoryFolderStore(seed: [Folder(name: "x")])

        #expect(await store.rename(from: "x", to: "x") == .unchanged(name: "x"))
    }

    @Test("重命名：去空白后与原名相同，同样算 `unchanged`（不是重名）")
    func renameToTrimmedItselfIsUnchanged() async {
        let store = InMemoryFolderStore(seed: [Folder(name: "x")])

        #expect(await store.rename(from: "x", to: "  x  ") == .unchanged(name: "x"))
    }

    @Test("重命名：与**其它**夹重名 ⇒ `duplicate`（PRD §5.13 的「其它」两个字就是这一句）")
    func renameToAnotherFolderNameIsDuplicate() async {
        let store = InMemoryFolderStore(seed: [Folder(name: "x"), Folder(name: "y")])

        #expect(await store.rename(from: "x", to: "y") == .duplicate(name: "y"))
        #expect(await store.folderNames() == [FolderDefaults.name, "x", "y"])
    }

    @Test("重命名：空名 ⇒ `emptyName`；目标已经不在了 ⇒ `notFound`")
    func renameRejectsBlankAndMissing() async {
        let store = InMemoryFolderStore(seed: [Folder(name: "x")])

        #expect(await store.rename(from: "x", to: "   ") == .emptyName)
        #expect(await store.rename(from: "已经没了", to: "y") == .notFound(name: "已经没了"))
        #expect(await store.folderNames() == [FolderDefaults.name, "x"])
    }

    @Test("⚠️ 默认夹**不可重命名**（页脚写的是「不可重命名或删除」，两件事都要拦）")
    func renameProtectsTheDefaultFolder() async {
        // UI 不给入口是第一道，这里是逻辑层的第二道 —— 只拦删除不拦重命名的话，
        // 某个将来新加入口就会把默认夹改成别的名字，而"新收藏的落点"当场消失。
        let store = InMemoryFolderStore()

        #expect(await store.rename(from: FolderDefaults.name, to: "随便") == .protectedDefault)
        #expect(await store.folderNames() == [FolderDefaults.name])
    }

    @Test("⚠️ 默认夹**不可删除**（界面直接提示，不进确认弹层）")
    func deleteProtectsTheDefaultFolder() async {
        let store = InMemoryFolderStore(favorites: ["a/one": FolderDefaults.name])

        #expect(await store.delete(name: FolderDefaults.name) == .protectedDefault)
        #expect(await store.folderNames() == [FolderDefaults.name])
        #expect(await store.count(in: FolderDefaults.name) == 1)
    }

    @Test("删除一个不存在的夹 ⇒ `notFound`（另一个入口刚把它删了）")
    func deleteReportsMissingFolder() async {
        let store = InMemoryFolderStore()

        #expect(await store.delete(name: "x") == .notFound(name: "x"))
    }
}

/// 两个入口的**重名处置有意不同**（TECH_SPEC §9.12、PRD §5.6 vs §4.19）。
///
/// 这一组测试单独成套件，是因为它守的是最容易被人"顺手统一"掉的一处：
/// 两处提示只差一个字（「收藏夹已存在，已为你选中」vs「收藏夹已存在」），
/// 而**行为**差一整个动作（一个照样收藏、一个什么都不做）。
/// 抹平之后屏幕上看起来完全正常 —— 只是管理页那条路会悄悄把仓库收进去。
@Suite("收藏夹 · 两个入口的重名处置（有意不同）")
struct FolderTwoEntryTests {

    @Test("仓库详情入口：新建 ⇒ `created`，收藏也一起完成（两步只回一个结果）")
    func repositoryEntryCreatesAndFavorites() async {
        let store: any FolderStore = InMemoryFolderStore()

        let outcome = await store.createAndFavorite(name: "以后再看", repo: "a/one")

        #expect(outcome == .created(name: "以后再看"))
        #expect(await store.folder(ofRepo: "a/one") == "以后再看")
    }

    @Test("⚠️ 仓库详情入口：重名 ⇒ `reused`，而且**照样把仓库放进去**（PRD §5.6）")
    func repositoryEntryReusesAndStillFavorites() async {
        let store: any FolderStore = InMemoryFolderStore(seed: [Folder(name: "x")])

        let outcome = await store.createAndFavorite(name: "x", repo: "a/one")

        #expect(outcome == .reused(name: "x"))
        #expect(await store.folder(ofRepo: "a/one") == "x", "重名不是失败：那个仓库必须被放进去")
    }

    @Test("仓库详情入口：空名 ⇒ `emptyName`，**一条收藏都不产生**")
    func repositoryEntryRejectsBlankName() async {
        let store: any FolderStore = InMemoryFolderStore()

        #expect(await store.createAndFavorite(name: "   ", repo: "a/one") == .emptyName)

        let summaries = await store.summaries()
        #expect(summaries.allSatisfy { $0.itemCount == 0 })
    }

    @Test("⚠️ 管理页入口：重名 ⇒ `duplicate`，**既不创建、也不收藏**（与上面有意相反）")
    func managementEntryOnlyReportsTheDuplicate() async {
        let store: any FolderStore = InMemoryFolderStore(seed: [Folder(name: "x")])

        let outcome = await store.create(name: "x")

        #expect(outcome == .duplicate(name: "x"))
        #expect(await store.folderNames() == [FolderDefaults.name, "x"])

        // 关键的一句：管理页入口**没有**"顺带收藏"这回事 ——
        // 它连仓库是谁都不知道（`create` 只有一个签名）。两个夹的项目数都还是 0，
        // 而 `createAndFavorite` 那一侧同样的输入会变成 1。
        let summaries = await store.summaries()
        #expect(summaries.allSatisfy { $0.itemCount == 0 })
    }
}

/// 清空（登出，TECH_SPEC §3.6 第 ③ 步）。
@Suite("收藏夹 · 清空")
struct FolderClearTests {

    @Test("清空后**默认夹回来** —— 它不是用户数据，是「新收藏总有着落」这条语义的载体")
    func clearRestoresTheDefaultFolder() async {
        // 清空之后一个夹都不剩的话，"收藏一个仓库"这个动作就没有落点了
        // （而它不会报错，只是点收藏什么都不发生）。
        let store = InMemoryFolderStore(seed: [Folder(name: "x")], favorites: ["a/one": "x"])

        await store.clear()

        #expect(await store.folderNames() == [FolderDefaults.name])
        #expect(await store.count(in: FolderDefaults.name) == 0)
        // ⚠️ 归属也要清 —— 用户自己起的夹名（"给老板看的"）留着换个账号登进来还能读到。
        #expect(await store.folder(ofRepo: "a/one") == nil)
    }
}

/// 落盘编解码（TECH_SPEC §7.1：**UserDefaults + JSON**）。
///
/// ## 为什么它必须在这里
///
/// 落盘实现落在 App target，而 **App target 没有测试 target**（`AGENTS.md §3`）。
/// 于是"存进去取不回来"是一类**没有任何提示的故障**：不报错、不崩溃，
/// 只是每次冷启动后「我的收藏」空着 —— 或者在磁盘上慢慢长出一份谁也没写过的东西。
@Suite("收藏夹 · 落盘编解码")
struct FolderCodingTests {

    @Test("往返：收藏夹顺序 + 归属一个不丢")
    func roundTripKeepsEverything() throws {
        let folders = [Folder(name: FolderDefaults.name), Folder(name: "x")]
        let mapping = ["a/one": "x", "b/two": FolderDefaults.name]

        let payload = FolderCoding.Payload(folders: folders, mapping: mapping)
        let data = try #require(FolderCoding.encode(payload))
        let restored = try #require(FolderCoding.decode(from: data))

        // 顺序也要比 —— `folders` 的顺序**就是展示顺序**，解码时排乱了
        // 屏幕上表现为"收藏夹被重新排了一遍"，而那不会有任何提示。
        #expect(restored.folders == folders)
        #expect(restored.mapping == mapping)
    }

    @Test("⚠️ 落盘前按仓库全名**排序**：`Dictionary` 的迭代顺序每次运行都可能不同")
    func favoritesAreSortedByRepo() {
        let payload = FolderCoding.Payload(
            folders: [Folder(name: "x")],
            mapping: ["z/z": "x", "a/a": "x", "m/m": "y"]
        )

        #expect(payload.favorites.map(\.repo) == ["a/a", "m/m", "z/z"])
    }

    @Test("解码坏数据 ⇒ `nil`（让调用方回落成「只有默认夹」，而不是**零个**收藏夹）")
    func decodingGarbageYieldsNil() async {
        #expect(FolderCoding.decode(from: Data("不是 JSON".utf8)) == nil)
        #expect(FolderCoding.decode(from: Data()) == nil)
        // 形状对但字段类型不对：同样退化，不崩。
        #expect(FolderCoding.decode(from: Data(#"{"folders":1,"favorites":[]}"#.utf8)) == nil)

        // ⚠️ 与 `SearchHistoryCoding` 的差别正在这里：那边返回**空数组**（一个合法空态），
        //    这边返回 `nil`。零个收藏夹是一个**不合法**的状态（新收藏没有落点），
        //    让 `nil` 与"合法但空"在类型上分开，加载路径就不可能漏掉补齐默认夹这一步。
        let nothing = FolderCoding.decode(from: Data())
        let store = InMemoryFolderStore(seed: nothing?.folders ?? [])

        #expect(await store.folderNames() == [FolderDefaults.name])
    }

    @Test("⚠️ 磁盘上只有 `name` 一个字段 —— `isDefault` 是**算出来的**，脱钩状态写不出来")
    func persistenceCarriesOnlyTheName() throws {
        let payload = FolderCoding.Payload(
            folders: [Folder(name: FolderDefaults.name), Folder(name: "x")],
            mapping: [:]
        )

        let data = try #require(FolderCoding.encode(payload))
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.contains(FolderDefaults.name))
        // 存成一个存储字段的话，下面两种脏数据都能被构造出来，而且都不会报错：
        // ① 叫「默认收藏夹」却不是默认；② 不叫却被标成默认（那个标记指向一个可删的夹）。
        #expect(!text.contains("isDefault"), "`isDefault` 一旦落盘，脱钩就成了可能")
    }

    @Test("`isDefault` 恒由名字决定（一个纯函数，没有别的输入）")
    func isDefaultIsDerivedFromTheName() {
        #expect(Folder(name: FolderDefaults.name).isDefault)
        #expect(!Folder(name: "x").isDefault)
        // 差一个空格就不是它了 —— 这是"名字即标识"这条选择的直接后果，
        // 写出来是为了让下一个人知道它有边界（而不是以为有个"宽松比较"）。
        #expect(!Folder(name: " \(FolderDefaults.name)").isDefault)
    }

    @Test("解码出来的那份可以直接喂给 store（两段数据在同一份负载里，落盘不会出现半截状态）")
    func payloadFeedsTheStoreDirectly() async {
        let payload = FolderCoding.Payload(
            folders: [Folder(name: "x")],
            mapping: ["a/one": "x"]
        )

        let store = InMemoryFolderStore(seed: payload.folders, favorites: payload.mapping)

        #expect(await store.count(in: "x") == 1)
        #expect(await store.folderNames() == [FolderDefaults.name, "x"])
    }

    @Test("⚠️ `payload()` 取出的是**变更之后**的内容，且能原样还原（落盘实现唯一的取数口）")
    func payloadRoundTripsAfterMutations() async {
        // 这一条守的是落盘实现（App 组合根那个 `UserDefaultsFolderStore`）赖以工作的前提：
        // 它自己不重写任何语义，每次改完只是"把 `payload()` 整份存回去" ⇒
        // 只要这个出口漏掉了某一半（比如改名后映射的值没跟上），
        // 磁盘上就会留下一个**默认夹之外的空夹**或一条指向不存在夹的归属。
        // 而那种数据在屏幕上看起来只是"收藏少了几条"，不会报错。
        let oldFolder = "旧的"
        let newFolder = "新的"
        let inOld = "owner/in-old"
        let inDefault = "owner/in-default"

        let store = InMemoryFolderStore(seed: [Folder(name: oldFolder)], favorites: [:])
        _ = await store.move(repo: inOld, to: oldFolder)
        _ = await store.move(repo: inDefault, to: FolderDefaults.name)
        // 改名 ⇒ 映射的"值"必须跟着改（§9.12 归属表第 5 行）。落盘取数口
        // 若在这一步之后仍能还原出 `新的`，说明两段数据是一起出去的。
        _ = await store.rename(from: oldFolder, to: newFolder)

        let payload = await store.payload()
        let restored = InMemoryFolderStore(
            seed: payload.folders,
            favorites: payload.mapping
        )

        // ⚠️ `await` 一律先落到局部量里再进 `#expect` —— 宏里直接写 `await`
        //    会静默地断言错东西（`AGENTS.md §5` 那条高频坑）。
        let restoredNames = await restored.folderNames()
        let originalNames = await store.folderNames()
        let restoredInOld = await restored.folder(ofRepo: inOld)
        let restoredInDefault = await restored.folder(ofRepo: inDefault)
        let restoredNewCount = await restored.count(in: newFolder)
        let restoredDefaultCount = await restored.count(in: FolderDefaults.name)

        #expect(restoredNames == originalNames)
        #expect(restoredInOld == newFolder)
        #expect(restoredInDefault == FolderDefaults.name)
        #expect(restoredNewCount == 1)
        #expect(restoredDefaultCount == 1)

        // ⚠️ 顺带钉住"归属表是排过序的"：不排序的话 `Dictionary` 的迭代顺序
        //    每次运行都可能不同 ⇒ 同一份收藏两次落盘会得到两个不同字节序列。
        let repos = payload.favorites.map { $0.repo }
        #expect(repos == repos.sorted())
    }
}
