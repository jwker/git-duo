import Testing

@testable import GitDuoKit

/// §4.4 分区二 / 分区三分段条的两档（PRD §4.4、决策 #61）。
///
/// ## 这组断言守的是一条"漏一格不报错"的规则
///
/// 分段条上有几格、按什么顺序，是**用户能不能点到某一档**的唯一依据。
/// 漏一格的后果不是崩溃、也不是报错，而是**那一档点不着**（或者点下去没反应）。
/// 同样地，"当前是哪一档"如果靠一个三档枚举来承载，`.all` 落进哪一支都是静默错。
@Suite("仓库详情分段档位 · 两档与映射")
struct RepoSectionSegmentTests {

    @Test("⚠️ **只有两档**，顺序是「开放」在前（分段条按 `allCases` 画）")
    func onlyTwoSegmentsInOrder() {
        #expect(RepoSectionSegment.allCases == [.open, .closed])
    }

    @Test("两档分别映射到服务端的 `open` / `closed`")
    func listStateMapping() {
        #expect(RepoSectionSegment.open.listState == .open)
        #expect(RepoSectionSegment.closed.listState == .closed)
    }

    @Test("⚠️ **没有一档映射到 `.all`** —— 这两段的界面上没有「全部」这一格")
    func noSegmentMapsToAll() {
        for segment in RepoSectionSegment.allCases {
            #expect(segment.listState != .all)
        }
    }

    @Test("""
        ⚠️ 两档的 `rawValue` 与 `RepoListState` 的**恰好相同**，但那是巧合、不是契约 ——
        这条断言钉住的是"映射走 `switch`"，改任一边的名字都不会让请求悄悄发错
        """)
    func rawValuesAreCoincidentalAndMappingIsExplicit() {
        // 当前两者逐字相同（`"open"` / `"closed"`）—— 于是直接 `rawValue` 也能跑。
        for segment in RepoSectionSegment.allCases {
            #expect(segment.rawValue == segment.listState.rawValue)
        }

        // 但真正被依赖的是 `listState` 这个显式映射：`RepoListState` 有三档、
        // 本枚举只有两档 —— `allCases` 的**数量**不同就是那条隐式契约不成立的最简证据。
        #expect(RepoSectionSegment.allCases.count == 2)
        #expect(RepoListState.allCases.count == 3)
    }

    @Test("第二档的文案两段不同，但档位本身是同一个")
    func secondSegmentIsSharedByBothSections() {
        // Issues 段叫「已关闭」、PR 段叫「已合并」（两份文案各归各的 `…SectionCopy`）——
        // 底下要的都是服务端的 `closed`。这条断言钉住的是"它们共用同一个档位值"，
        // 从而不会有"两段各一个枚举、只给其中一段加档"这种事。
        #expect(RepoSectionSegment.closed.listState == RepoListState.closed)
        #expect(RepoPullsSectionCopy.mergedSegment == "已合并")
        #expect(RepoIssuesSectionCopy.closedSegment == "已关闭")
    }
}
