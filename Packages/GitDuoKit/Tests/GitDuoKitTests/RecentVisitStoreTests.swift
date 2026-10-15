import Foundation
import Testing

@testable import GitDuoKit

/// 「最近访问」的不变式（PRD §3.13 / TECH_SPEC §9.13）。
///
/// 原型只有一行实现：`RECENT = [{n,t:'刚刚'}].concat(RECENT.filter(v=>v.n!==n)).slice(0,6)`
/// —— 去重 · 置顶 · 裁剪到 6，三件事任一漏掉都会在真机上表现为
/// 「同一个仓库在列表里出现两次」或「越用越长」。
///
/// 另有一条原型没有的：**每条记录还要带上"打开它时是否可写"**（2026-10-06 补）——
/// 首页那一行点进去要按它分流到「自己的仓库详情」还是「他人只读页」，
/// 而本机只存全名的话这份归属就丢了（PRD §3.13、铁律 #7）。
@Suite("RecentVisitStore · 去重 / 置顶 / 上限 / 归属")
struct RecentVisitStoreTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func visit(
        _ name: String,
        canWrite: Bool = true,
        at offset: TimeInterval
    ) -> RecentVisit {
        RecentVisit(
            fullName: name,
            canWrite: canWrite,
            visitedAt: base.addingTimeInterval(offset)
        )
    }

    @Test("上限是 6 条 —— 与 PRD §3.13 及个人主页置顶上限一致")
    func maxCountIsSix() {
        #expect(InMemoryRecentVisitStore.maxCount == 6)
    }

    @Test("新记录置顶，最新在最前")
    func newestFirst() async {
        let store = InMemoryRecentVisitStore()
        await store.record(fullName: "a/one", canWrite: true, ownerAvatarURL: nil, at: base)
        await store.record(fullName: "b/two", canWrite: false, ownerAvatarURL: nil, at: base.addingTimeInterval(10))

        let names = await store.visits().map(\.fullName)
        #expect(names == ["b/two", "a/one"])
    }

    @Test("同一个仓库再次访问 ⇒ **只留最新一条**，且排到最前（不产生重复行）")
    func deduplicatesAndMovesToFront() async {
        let store = InMemoryRecentVisitStore(seed: [
            visit("a/one", at: 0), visit("b/two", at: 10), visit("c/three", at: 20),
        ])

        await store.record(fullName: "a/one", canWrite: true, ownerAvatarURL: nil, at: base.addingTimeInterval(30))

        let names = await store.visits().map(\.fullName)
        #expect(names == ["a/one", "c/three", "b/two"])
        #expect(names.count == Set(names).count, "出现重复行就是这条不变式破了")
    }

    @Test("超过 6 条时淘汰**最旧**的那条，而不是最新的")
    func trimsOldest() async {
        let store = InMemoryRecentVisitStore()
        for index in 0..<8 {
            await store.record(
                fullName: "o/r\(index)",
                canWrite: true,
                ownerAvatarURL: nil,
                at: base.addingTimeInterval(Double(index))
            )
        }

        let names = await store.visits().map(\.fullName)
        #expect(names.count == 6)
        #expect(names.first == "o/r7", "最新的必须在最前")
        #expect(!names.contains("o/r0"), "最旧的两条应被裁掉")
        #expect(!names.contains("o/r1"))
    }

    @Test("预置超过 6 条时截断 —— 落盘数据被外部改大也不会让首页变长")
    func seedIsTrimmed() async {
        let store = InMemoryRecentVisitStore(seed: (0..<9).map { visit("o/r\($0)", at: Double($0)) })

        let count = await store.visits().count
        #expect(count == 6)
    }

    @Test("清除后为空 —— 且不影响置顶仓库（置顶是 GitHub 侧数据，压根不在这里）")
    func clearEmptiesTheList() async {
        let store = InMemoryRecentVisitStore(seed: [visit("a/one", at: 0)])
        await store.clear()

        let remaining = await store.visits()
        #expect(remaining.isEmpty)
    }

    @Test("`id` 就是仓库全名 —— 去重与 `ForEach` 的同一把钥匙")
    func idIsFullName() {
        #expect(visit("a/one", at: 0).id == "a/one")
        // 同一仓库、不同时刻：整体值不同（`visitedAt` 参与 `Hashable`），但 `id` 必须相同 ——
        // `ForEach` 认的是 `id`，两者不一致会让列表出现"看似重复的行"。
        #expect(visit("a/one", at: 0) != visit("a/one", at: 99))
        #expect(visit("a/one", at: 0).id == visit("a/one", at: 99).id)
        #expect(visit("a/one", at: 0).id != visit("a/two", at: 0).id)
    }

    @Test("相对文案由时刻现算 —— 不会永远停在「刚刚」")
    func timeLabelIsComputed() {
        let old = visit("a/one", at: 0)

        #expect(old.timeLabel(now: base) == "刚刚")
        #expect(old.timeLabel(now: base.addingTimeInterval(3 * 86_400)) == "3 天前")
    }

    // MARK: - 归属（2026-10-06 补）

    @Test("写入时把「当时是否可写」一起存下来，读回时还在")
    func recordsWritabilityWithTheVisit() async {
        let store = InMemoryRecentVisitStore()
        await store.record(fullName: "rust-lang/rust", canWrite: false, ownerAvatarURL: nil, at: base)
        await store.record(fullName: "my-git/gitduo", canWrite: true, ownerAvatarURL: nil, at: base.addingTimeInterval(1))

        let visits = await store.visits()
        #expect(visits.map(\.fullName) == ["my-git/gitduo", "rust-lang/rust"])
        #expect(visits.map(\.canWrite) == [true, false])
    }

    @Test("重新访问同一个仓库 ⇒ **用新的归属覆盖旧的**（权限可能变了：用户刚 Fork 过来）")
    func revisitingOverwritesWritability() async {
        let store = InMemoryRecentVisitStore()
        await store.record(fullName: "rust-lang/rust", canWrite: false, ownerAvatarURL: nil, at: base)

        // 同一个仓库，这次是在"自己的仓库"页里打开的（比如刚 Fork 完）。
        await store.record(fullName: "rust-lang/rust", canWrite: true, ownerAvatarURL: nil, at: base.addingTimeInterval(60))

        let visits = await store.visits()
        #expect(visits.count == 1, "覆盖归属不该产生第二条记录")
        #expect(visits.first?.canWrite == true, "沿用旧归属会让首页永远指向只读页")
    }
}

/// 落盘编解码的往返（TECH_SPEC §7.1：最近访问走 **UserDefaults + JSON**）。
///
/// ## 为什么这门测试非有不可
///
/// 落盘实现落在 App target，而 **App target 没有测试 target**（`AGENTS.md §3`）。
/// 于是"存进去取不回来"是一类**没有任何提示的故障**：不报错、不崩溃，
/// 只是每次冷启动后最近访问都空着，而且很难想到是编码问题。
///
/// 所以编解码收在 `RecentVisit` 自己身上（`encodeList` / `decodeList`），
/// 由本套件用一次往返钉住 —— 包括**归属字段必须一起活下来**。
@Suite("RecentVisit · 落盘编解码")
struct RecentVisitCodingTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("编码 → 解码：全名 / 时刻 / 归属三样一个不丢")
    func roundTripKeepsEveryField() throws {
        let avatar = URL(string: "https://avatars.githubusercontent.com/u/1?v=4")!
        let original = [
            RecentVisit(fullName: "my-git/gitduo", canWrite: true, visitedAt: base,
                        ownerAvatarURL: avatar),
            RecentVisit(fullName: "rust-lang/rust", canWrite: false, visitedAt: base.addingTimeInterval(90)),
        ]

        let data = try #require(RecentVisit.encodeList(original))
        let restored = RecentVisit.decodeList(from: data)

        #expect(restored == original)
        // ⚠️ 单独再断言一次 `canWrite`：它是 2026-10-06 才加的字段，
        //    "漏掉某个字段"正是这类改动最容易出的错（合成 `Codable` 会跟着漏）。
        #expect(restored.map(\.canWrite) == [true, false])
        // 走查第 72 条：头像地址同样要一起活下来；没有的那条解码成 `nil`（不是崩溃）。
        #expect(restored.first?.ownerAvatarURL == avatar)
        #expect(restored.last?.ownerAvatarURL == nil)
    }

    @Test("⚠️ 旧版本落盘的记录（没有 `ownerAvatarURL` 键）⇒ 解码成 nil，不是失败")
    func legacyJSONWithoutAvatarDecodes() throws {
        // 与真实落盘同形状：2026-10-15 之前的版本写下的 JSON 就长这样。
        let legacy = #"[{"fullName":"a/b","canWrite":true,"visitedAt":1700000000}]"#
        let restored = RecentVisit.decodeList(from: Data(legacy.utf8))

        #expect(restored.count == 1)
        #expect(restored.first?.ownerAvatarURL == nil)
        #expect(restored.first?.owner == "a", "首字母兜底要的 owner 登录名从全名派生，不依赖头像字段")
    }

    @Test("解码**不抛错**：坏数据退化成空数组，而不是让首页变成错误屏")
    func decodingGarbageYieldsEmpty() {
        #expect(RecentVisit.decodeList(from: Data("不是 JSON".utf8)).isEmpty)
        #expect(RecentVisit.decodeList(from: Data()).isEmpty)
        // 形状对但字段不全（旧版本写下的格式）：同样退化，不是崩溃。
        #expect(RecentVisit.decodeList(from: Data(#"[{"fullName":"a/b"}]"#.utf8)).isEmpty)
    }

    @Test("顺序原样保留 —— 编解码不得悄悄重排（首页读的正是这个顺序）")
    func orderSurvives() throws {
        let original = (0..<6).map {
            RecentVisit(fullName: "o/r\($0)", canWrite: $0.isMultiple(of: 2), visitedAt: base.addingTimeInterval(Double($0)))
        }

        let restored = RecentVisit.decodeList(from: try #require(RecentVisit.encodeList(original)))
        #expect(restored.map(\.fullName) == original.map(\.fullName))
    }
}
