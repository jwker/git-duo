import Foundation
import Testing

@testable import GitDuoKit

/// Star 基线的存储与落盘编解码（TECH_SPEC §9.10.2 / §7.1）。
///
/// ## 基线为什么值得单独测
///
/// 「新星榜」的 `+812 本周` 不是接口给的数，而是**本机两次采样相减**（决策 #36）。
/// 基线丢了 ⇒ 那一轮**不显示增幅**（这是设计好的降级）。
/// 但它有一个更难发现的坏法：**基线被换成了别人的** ——
/// 换账号登录后如果没清，屏幕上会出现"凭空长出来的增幅"，而且数字看着完全合理。
@Suite("StarSnapshotStore · 基线与落盘")
struct StarSnapshotStoreTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("首次记录 ⇒ 读得回来；这就是「下次相减」的那一半")
    func recordsAndReadsBack() async {
        let store = InMemoryStarSnapshotStore()
        #expect(await store.snapshot(for: "a/b") == nil, "首次见到时**没有**基线（增量按 nil 处理，不是 0）")

        await store.record(fullName: "a/b", stars: 100, at: base)

        let snapshot = await store.snapshot(for: "a/b")
        #expect(snapshot?.stars == 100)
        #expect(snapshot?.fetchedAt == base)
    }

    @Test("再次记录 ⇒ 覆盖而不是累加（基线永远是最近一次看到的值）")
    func recordOverwrites() async {
        let store = InMemoryStarSnapshotStore()
        await store.record(fullName: "a/b", stars: 100, at: base)
        await store.record(fullName: "a/b", stars: 112, at: base.addingTimeInterval(3_600))

        #expect(await store.snapshot(for: "a/b")?.stars == 112)
    }

    @Test("换账号 / 登出 ⇒ clear 之后拿不到任何仓库的基线")
    func clearWipesEveryRepository() async {
        let store = InMemoryStarSnapshotStore(seed: [
            StarSnapshot(fullName: "a/b", stars: 1, fetchedAt: base),
            StarSnapshot(fullName: "c/d", stars: 2, fetchedAt: base),
        ])

        await store.clear()

        #expect(await store.snapshot(for: "a/b") == nil)
        #expect(await store.snapshot(for: "c/d") == nil,
                "留下别人的基线 ⇒ 换账号后屏幕上会长出凭空出现的增幅")
    }

    @Test("落盘往返：全名 / 星数 / 采样时刻三样都不丢")
    func roundTripKeepsEveryField() throws {
        let original = [
            StarSnapshot(fullName: "a/b", stars: 100, fetchedAt: base),
            StarSnapshot(fullName: "c/d", stars: 7, fetchedAt: base.addingTimeInterval(60)),
        ]

        let data = try #require(StarSnapshot.encodeList(original))
        #expect(StarSnapshot.decodeList(from: data) == original)
    }

    @Test("落盘数据坏掉 ⇒ 退化成空基线，而不是让探索页打不开")
    func garbageDecodesToEmpty() {
        #expect(StarSnapshot.decodeList(from: Data("不是 JSON".utf8)).isEmpty)
        #expect(StarSnapshot.decodeList(from: Data()).isEmpty)
    }

    @Test("`allSnapshots()` 按全名升序 —— 落盘实现靠它写出确定的一份")
    func allSnapshotsIsOrdered() async {
        let store = InMemoryStarSnapshotStore(seed: [
            StarSnapshot(fullName: "z/last", stars: 1, fetchedAt: base),
            StarSnapshot(fullName: "a/first", stars: 2, fetchedAt: base),
            StarSnapshot(fullName: "m/mid", stars: 3, fetchedAt: base),
        ])

        let names = await store.allSnapshots().map(\.fullName)
        // ⚠️ 这条断言挡的是"直接写 `storage.values`"：字典的迭代顺序每次运行都可能不同，
        //    于是同一份基线两次落盘会得到两个字节序列，任何按内容比对的地方都会间歇失败。
        #expect(names == ["a/first", "m/mid", "z/last"])
    }
}
