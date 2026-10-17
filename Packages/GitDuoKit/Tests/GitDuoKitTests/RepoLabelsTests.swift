import Foundation
import GitHubAPI
import Testing

@testable import GitDuoKit

/// 标签库：**10 色板** · 取全部 · **空名 / 重名都不发那次必败的请求**（PRD §5.2、TECH_SPEC §9.8、决策 #56）。
///
/// ## 这组断言守的三件事，出错时都"看起来正常"
///
/// 1. **色值不带 `#`** —— 发一个带 `#` 的色过去，服务端回 422，
///    而那条 422 的文案是机器话术（用户读成"服务器坏了"）。所以色板里存的就必须是
///    **不带 `#`** 的那一版，而不是靠某个转换函数保证。
/// 2. **重名要本地挡掉** —— §9.8 写明了要"提前本地去重、不发那一次必败的请求"，
///    并且把结局变成"帮你选中它"。
/// 3. **标签库取不到 ≠ 这个仓库没有标签** —— 前者要说"没加载出来、重试"，
///    后者才是"还没有标签"。折成空数组会让一次网络抖动看起来像"我的标签全没了"。
@Suite("仓库标签库 · 色板 / 取全部 / 新建校验")
struct RepoLabelsTests {

    // MARK: - 数据源替身

    private actor ScriptedLabelsSource: RepoLabelsDataSource {

        private var pages: [Page<LabelDTO>]
        private let createResult: Result<LabelDTO, any Error>

        private(set) var listCalls = 0
        private(set) var cursors: [URL?] = []
        private(set) var createdNames: [String] = []
        private(set) var createdColors: [String] = []
        private(set) var createCalls = 0

        init(
            pages: [Page<LabelDTO>],
            createResult: Result<LabelDTO, any Error> = .success(LabelDTO(name: "x", color: "d73a4a"))
        ) {
            self.pages = pages
            self.createResult = createResult
        }

        func labels(owner: String, repo: String, cursor: URL?) async throws -> Page<LabelDTO> {
            listCalls += 1
            cursors.append(cursor)
            return pages.count > 1
                ? pages.removeFirst()
                : (pages.first ?? Page(items: [], nextCursor: nil))
        }

        func createLabel(
            owner: String,
            repo: String,
            name: String,
            color: String
        ) async throws -> LabelDTO {
            createCalls += 1
            createdNames.append(name)
            createdColors.append(color)
            return try createResult.get()
        }
    }

    private func dto(_ name: String, color: String = "d73a4a") -> LabelDTO {
        LabelDTO(name: name, color: color)
    }

    // MARK: - 10 色板

    @Test("色板正好 **10** 个（§3.8 / §5.2 的产品承诺，写死成常量是为了让人改时有一次自觉）")
    func paletteHasTenColors() {
        #expect(LabelPalette.count == 10)
        #expect(LabelPalette.hexes.count == 10)
    }

    @Test("⚠️ 色板里**一个 `#` 都没有** —— 发出去会被服务端 422（机器话术，用户读成「服务器坏了」）")
    func paletteHasNoHashPrefix() {
        for hex in LabelPalette.hexes {
            #expect(!hex.hasPrefix("#"), "`\(hex)` 带了 `#`：POST /labels 的 color 不带前缀")
        }
    }

    @Test("色板逐字对齐原型 `LBL_COLORS`（去掉 CSS 的 `#`）")
    func paletteMatchesPrototype() {
        // ⚠️ 2026-10-08 换过四档（橙 / 黄 / 粉 / 灰）—— 理由见 `LabelPalette` 的文档注释。
        // 这份清单冻结自原型 `07-issues.js` 的 `LBL_COLORS`（原型树已于 2026-10-17 删除；
        // 此处就是现正本，再改动要单独说明）。
        #expect(
            LabelPalette.hexes == [
                "d73a4a", "bc4c00", "9a6700", "0e8a16", "0075ca",
                "5319e7", "8250df", "bf3989", "6a737d", "1f2328"
            ]
        )
    }

    @Test("⚠️ 十档的白字对比度**全部 ≥ 4.5:1** —— `.lbl-tag` 是白字压色块，浅色会让标签名读不出来")
    func paletteAllPassWhiteTextContrast() {
        // 这条是 2026-10-08 那次换色的**护栏**：将来谁把某一档调浅（"这个黄更亮好看"），
        // 编译不会报错、也不会有人发现 —— 除非这条断言拦下他。
        // 门槛 4.5 = WCAG 2.1 对正文的 AA 要求（标签名是要读的文字，不按"非文字图形"的 3:1 算）。
        for hex in LabelPalette.hexes {
            let ratio = Self.whiteTextContrast(of: hex)
            #expect(
                ratio >= 4.5,
                "`\(hex)` 白字对比度只有 \(ratio):1 —— 低于 4.5，标签名会读不出来"
            )
        }
    }

    @Test("⚠️ 最紧的一档是绿 `0e8a16`（4.50）—— 它离门槛只有 0.001，换色时别把它也当成「有余量」")
    func paletteTightestEntryIsGreen() {
        // 留这条是为了说清一件事：**别看到"全过了"就以为还能再调浅一档**。
        let ratios = LabelPalette.hexes.map { ($0, Self.whiteTextContrast(of: $0)) }
        let tightest = ratios.min { $0.1 < $1.1 }
        #expect(tightest?.0 == "0e8a16")
        #expect((tightest?.1 ?? 0) < 4.51, "绿那一档的余量比登记的大了 —— 换色后请一并更新这条与文档")
    }

    /// 白字压在这个色值上的对比度（WCAG 2.1 相对亮度公式）。
    ///
    /// ⚠️ 它是**测试内部的**实现，不进产品代码：产品侧只需要"色板里每一档都够深"这一个事实，
    /// 而运行时按亮度自动选字色这件事**已经判定不做**（偏离原型，见 `LabelPalette` 的说明）。
    private static func whiteTextContrast(of hex: String) -> Double {
        let digits = Array(hex)
        func channel(_ index: Int) -> Double {
            Double(Int(String(digits[index * 2 ... index * 2 + 1]), radix: 16) ?? 0) / 255
        }
        func linear(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(channel(0))
            + 0.7152 * linear(channel(1))
            + 0.0722 * linear(channel(2))
        return 1.05 / (luminance + 0.05)
    }

    @Test("每个色值都是**六位十六进制小写**")
    func paletteEntriesAreSixDigitHex() {
        let allowed = Set("0123456789abcdef")
        for hex in LabelPalette.hexes {
            #expect(hex.count == 6, "`\(hex)` 不是六位")
            #expect(hex.allSatisfy { allowed.contains($0) }, "`\(hex)` 含非小写十六进制字符")
        }
    }

    @Test("默认选中项 = **第一个**（原型 `pickedClr = LBL_COLORS[0]`）")
    func paletteInitialIsFirst() {
        #expect(LabelPalette.initial == LabelPalette.hexes[0])
        #expect(LabelPalette.initial == "d73a4a")
    }

    // MARK: - 取全部

    @Test("一页取回：顺序原样（服务端按名字升序，客户端**不重排**）")
    func singlePageKeepsServerOrder() async throws {
        let source = ScriptedLabelsSource(pages: [
            Page(items: [dto("bug"), dto("docs"), dto("enhancement")], nextCursor: nil)
        ])

        let library = try await LabelCatalog(source: source).all(fullName: "a/b")

        #expect(library.labels.map(\.name) == ["bug", "docs", "enhancement"])
        #expect(library.count == 3)
        #expect(library.hasMore == false)
    }

    @Test("⚠️ 有下一页时**自动续页** —— §5.2 说的是「仓库全部标签列表」")
    func followsNextPage() async throws {
        let page2 = URL(string: "https://api.github.com/repos/a/b/labels?page=2")!
        let source = ScriptedLabelsSource(pages: [
            Page(items: [dto("bug")], nextCursor: page2),
            Page(items: [dto("docs")], nextCursor: nil),
        ])

        let library = try await LabelCatalog(source: source).all(fullName: "a/b")

        #expect(library.labels.map(\.name) == ["bug", "docs"])
        #expect(await source.cursors == [nil, page2], "续页必须带上服务端给的游标")
        #expect(library.hasMore == false)
    }

    @Test("⚠️ 翻页边界上的**同名条目只留一条** —— 重复的键会在 picker 里画成两行同名")
    func duplicateNamesAreDropped() async throws {
        let page2 = URL(string: "https://api.github.com/repos/a/b/labels?page=2")!
        let source = ScriptedLabelsSource(pages: [
            Page(items: [dto("bug"), dto("docs")], nextCursor: page2),
            Page(items: [dto("docs"), dto("enhancement")], nextCursor: nil),
        ])

        let library = try await LabelCatalog(source: source).all(fullName: "a/b")

        #expect(library.labels.map(\.name) == ["bug", "docs", "enhancement"])
    }

    @Test("⚠️ 翻到页数上限 ⇒ 停下来并把 `hasMore` 置真（不许既截断又没人知道）")
    func stopsAtPageCeilingAndSaysSo() async throws {
        let next = URL(string: "https://api.github.com/repos/a/b/labels?page=99")!
        // 造满上限那么多页，每页都还有下一页。
        let pages = (0..<LabelCatalog.maxPages).map { index in
            Page(items: [dto("l\(index)")], nextCursor: next)
        }
        let source = ScriptedLabelsSource(pages: pages)

        let library = try await LabelCatalog(source: source).all(fullName: "a/b")

        #expect(library.count == LabelCatalog.maxPages)
        #expect(library.hasMore, "到上限停下时 `count` 只是下界，标志必须说明这件事")
        #expect(await source.listCalls == LabelCatalog.maxPages)
    }

    @Test("⚠️ 取标签库**失败不降级成空数组**（否则一次网络抖动看起来像「标签全没了」）")
    func failureDoesNotBecomeAnEmptyList() async throws {
        // 一页都没有 —— 但这不是"失败"，这里另造一个真的会抛的替身。
        let source = FailingLabelsSource()
        var threw = false
        do {
            _ = try await LabelCatalog(source: source).all(fullName: "a/b")
        } catch is GitHubError {
            threw = true
        }
        #expect(threw)
    }

    private struct FailingLabelsSource: RepoLabelsDataSource {
        func labels(owner: String, repo: String, cursor: URL?) async throws -> Page<LabelDTO> {
            throw GitHubError.transport(URLError(.notConnectedToInternet))
        }
        func createLabel(
            owner: String, repo: String, name: String, color: String
        ) async throws -> LabelDTO {
            throw GitHubError.notFound
        }
    }

    @Test("`fullName` 形状不对 ⇒ 抛错")
    func malformedFullNameThrows() async throws {
        let source = ScriptedLabelsSource(pages: [])
        var threw = false
        do {
            _ = try await LabelCatalog(source: source).all(fullName: "noSlash")
        } catch is RepositoryMappingError {
            threw = true
        }
        #expect(threw)
        #expect(await source.listCalls == 0)
    }

    // MARK: - 新建：两条"不发请求"的路径

    @Test("⚠️ **空名 ⇒ `.emptyName`，一个请求都没发**")
    func emptyNameSkipsTheRequest() async throws {
        let source = ScriptedLabelsSource(pages: [])

        let outcome = try await LabelCatalog(source: source).create(
            fullName: "a/b", name: "", colorHex: "d73a4a", existing: []
        )

        #expect(outcome == .emptyName)
        #expect(await source.createCalls == 0, "发一个必败的请求换回一句机器话术，是白花一次配额")
    }

    @Test("⚠️ **只有空白也算空名**（`trim` 之后为空就停）")
    func whitespaceOnlyNameIsEmpty() async throws {
        let source = ScriptedLabelsSource(pages: [])

        let outcome = try await LabelCatalog(source: source).create(
            fullName: "a/b", name: "   \n ", colorHex: "d73a4a", existing: []
        )

        #expect(outcome == .emptyName)
        #expect(await source.createCalls == 0)
    }

    @Test("⚠️ **重名 ⇒ `.alreadyExists`（带上已有那条）+ 一个请求都没发**（§9.8 的「提前本地去重」）")
    func duplicateNameReturnsTheExistingLabel() async throws {
        let source = ScriptedLabelsSource(pages: [])
        let existing = [Label(name: "bug", colorHex: "d73a4a"), Label(name: "docs", colorHex: "0075ca")]

        let outcome = try await LabelCatalog(source: source).create(
            fullName: "a/b", name: "docs", colorHex: "0e8a16", existing: existing
        )

        #expect(outcome == .alreadyExists(Label(name: "docs", colorHex: "0075ca")))
        #expect(await source.createCalls == 0, "服务端会回 422（机器话术），客户端应当提前挡掉")
    }

    @Test("⚠️ 比较是**大小写敏感**的（`Bug` 与 `bug` 在 GitHub 上是两个标签）")
    func nameComparisonIsCaseSensitive() async throws {
        let source = ScriptedLabelsSource(
            pages: [],
            createResult: .success(LabelDTO(name: "Bug", color: "d73a4a"))
        )

        let outcome = try await LabelCatalog(source: source).create(
            fullName: "a/b", name: "Bug", colorHex: "d73a4a",
            existing: [Label(name: "bug", colorHex: "d73a4a")]
        )

        #expect(outcome == .created(Label(name: "Bug", colorHex: "d73a4a")))
        #expect(await source.createCalls == 1, "本地以为重名、服务端其实是两个 ⇒ 点了却没建成且无报错")
    }

    @Test("重名前后的空格被吃掉（原型 `createLabel` 就是这么 trim 的）")
    func nameIsTrimmedBeforeComparing() async throws {
        let source = ScriptedLabelsSource(pages: [])

        let outcome = try await LabelCatalog(source: source).create(
            fullName: "a/b", name: "  bug  ", colorHex: "d73a4a",
            existing: [Label(name: "bug", colorHex: "d73a4a")]
        )

        #expect(outcome == .alreadyExists(Label(name: "bug", colorHex: "d73a4a")))
        #expect(await source.createCalls == 0)
    }

    // MARK: - 新建：真的发出去那一次

    @Test("⚠️ 色值**原样发出**（不补 `#`、不剥除）——静默改写会把调用方的 bug 藏起来")
    func colorIsSentVerbatim() async throws {
        let source = ScriptedLabelsSource(
            pages: [],
            createResult: .success(LabelDTO(name: "performance", color: "0075ca"))
        )

        _ = try await LabelCatalog(source: source).create(
            fullName: "a/b", name: "performance", colorHex: "0075ca", existing: []
        )

        #expect(await source.createdColors == ["0075ca"])
    }

    @Test("名字以 **trim 后**的形状发出")
    func trimmedNameIsSent() async throws {
        let source = ScriptedLabelsSource(
            pages: [],
            createResult: .success(LabelDTO(name: "performance", color: "0075ca"))
        )

        _ = try await LabelCatalog(source: source).create(
            fullName: "a/b", name: "  performance ", colorHex: "0075ca", existing: []
        )

        #expect(await source.createdNames == ["performance"])
    }

    @Test("⚠️ 返回的是**服务端回的那一条**，不是本地拼的（名字的规范化以服务端为准）")
    func createdLabelComesFromTheServer() async throws {
        // 服务端把它规范化成了小写 —— 本地必须跟着服务端走。
        let source = ScriptedLabelsSource(
            pages: [],
            createResult: .success(LabelDTO(name: "performance", color: "0075ca", description: "性能"))
        )

        let outcome = try await LabelCatalog(source: source).create(
            fullName: "a/b", name: "Performance", colorHex: "0075ca", existing: []
        )

        #expect(outcome == .created(
            Label(name: "performance", colorHex: "0075ca", description: "性能")
        ))
    }

    @Test("`LabelLibrary.label(named:)` 与去重**同一套比较规则**（不然「自动选中」会选中另一个）")
    func libraryLookupMatchesTheDedupRule() {
        let library = LabelLibrary(
            labels: [Label(name: "bug", colorHex: "d73a4a"), Label(name: "Bug", colorHex: "0e8a16")],
            hasMore: false
        )
        #expect(library.label(named: "bug")?.colorHex == "d73a4a")
        #expect(library.label(named: "Bug")?.colorHex == "0e8a16")
        #expect(library.label(named: "bug ") == nil, "带空格的名字不该在库里命中（调用方负责 trim）")
    }
}
