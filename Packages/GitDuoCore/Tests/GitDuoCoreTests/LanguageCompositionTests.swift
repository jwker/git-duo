import Foundation
import Testing

@testable import GitDuoCore

/// 语言构成占比条的分段与百分比（TECH_SPEC §9.11、**决策 #42**）。
///
/// 这里最要紧的两条：
/// ① **各段百分比之和恒为 100** —— 用户一眼就能看出"加起来不是 100%"；
/// ② **同字节数时的顺序必须确定** —— `Dictionary` 迭代顺序不定，不排就会让
///    占比条的颜色在两次渲染之间互换（看起来像"数据变了"）。
@Suite("LanguageComposition · 分段与百分比")
struct LanguageCompositionTests {

    // MARK: - 空输入

    @Test("无语言数据 ⇒ 空数组（调用方据此渲染空态，而不是一根全灰的条）")
    func emptyInputProducesNothing() {
        #expect(LanguageComposition.shares(from: [:]).isEmpty)
    }

    @Test("全零字节 ⇒ 空数组 —— 零字节条目在饼里占不到宽度，只会多出一行 `Foo 0%`")
    func zeroBytesProduceNothing() {
        #expect(LanguageComposition.shares(from: ["Swift": 0, "Shell": 0]).isEmpty)
    }

    @Test("负字节数与空名字被丢弃（脏数据不该撑出一段图例）")
    func junkEntriesAreDropped() {
        let shares = LanguageComposition.shares(from: ["Swift": -5, "   ": 100, "Rust": 60])

        #expect(shares.count == 1)
        #expect(shares.first?.language == "Rust")
        #expect(shares.first?.percent == 100)
    }

    @Test("语言名左右空白被裁掉（`\"Swift \"` 不该退化成图例上的带空格名字）")
    func namesAreTrimmed() {
        let shares = LanguageComposition.shares(from: ["  Swift  ": 90, "Go ": 10])

        #expect(shares.map(\.label) == ["Swift", "Go"])
    }

    // MARK: - 分段（决策 #42：前 2 个语言 + 「其他」= 最多 3 段）

    @Test("单一语言 ⇒ 一段 100%，且**没有**「其他」")
    func singleLanguageHasNoOther() {
        let shares = LanguageComposition.shares(from: ["Swift": 12_345])

        #expect(shares.count == 1)
        #expect(shares[0].language == "Swift")
        #expect(shares[0].percent == 100)
        #expect(!shares.contains { $0.language == nil })
    }

    @Test("恰好两种语言 ⇒ 两个具名，**不合并**成 `Swift / 其他`")
    func twoLanguagesAreBothNamed() {
        let shares = LanguageComposition.shares(from: ["Rust": 5_000, "TOML": 200])

        #expect(shares.map(\.label) == ["Rust", "TOML"])
        #expect(shares.map(\.percent) == [96, 4])
    }

    @Test("三种语言 ⇒ 前 2 具名 + 「其他」，与原型图例的 3 行一致")
    func threeLanguagesMatchThePrototype() {
        // 原型的图例：`Swift 72%` / `Shell 18%` / `其他 10%`
        let shares = LanguageComposition.shares(from: [
            "Swift": 72_000, "Shell": 18_000, "Ruby": 10_000,
        ])

        #expect(shares.map(\.label) == ["Swift", "Shell", "其他"])
        #expect(shares.map(\.percent) == [72, 18, 10])
    }

    @Test("多种语言 ⇒ 「其他」的字节数是**被合并那些的总和**（不是只取第 3 名）")
    func otherMergesEveryRemainingLanguage() {
        let shares = LanguageComposition.shares(from: [
            "Swift": 500, "Shell": 300, "Ruby": 100, "Python": 60, "Makefile": 40,
        ])

        #expect(shares.count == 3)
        #expect(shares[2].language == nil)
        #expect(shares[2].bytes == 200)          // 100 + 60 + 40
        #expect(shares.reduce(0) { $0 + $1.bytes } == 1_000)
    }

    @Test("段数由 `maxNamedLanguages` 一个常量决定（改口径只需改这一处）")
    func namedCountIsSingleConstant() {
        let shares = LanguageComposition.shares(from: [
            "A": 40, "B": 30, "C": 20, "D": 10,
        ])

        #expect(shares.filter { $0.language != nil }.count == LanguageComposition.maxNamedLanguages)
        #expect(shares.count == LanguageComposition.maxNamedLanguages + 1)
    }

    // MARK: - 排序

    @Test("按字节数降序 —— 占比条从大到小排")
    func sortedByBytesDescending() {
        let shares = LanguageComposition.shares(from: ["Small": 10, "Big": 900, "Mid": 90])

        #expect(shares.map(\.label) == ["Big", "Mid", "其他"])
        #expect(shares.map(\.percent) == [90, 9, 1])
    }

    @Test("⚠️ 字节数相同时按名字升序 —— 否则同字节的两个语言会随字典顺序抖动、颜色互换")
    func tiesAreBrokenByNameForStability() {
        // 同一份数据反复解析 20 次，结果必须逐次相同。
        let input = ["Rust": 100, "Go": 100, "Zig": 100]

        let first = LanguageComposition.shares(from: input).map(\.label)
        #expect(first == ["Go", "Rust", "其他"])

        for _ in 0 ..< 20 {
            #expect(LanguageComposition.shares(from: input).map(\.label) == first)
        }
    }

    // MARK: - 百分比（最大余数法）

    @Test("⚠️ 三段各占三分之一 ⇒ 必须是 `34 / 33 / 33`，**不能是 `33 / 33 / 33`**")
    func equalThirdsSumToExactlyOneHundred() {
        let shares = LanguageComposition.shares(from: ["A": 10, "B": 10, "C": 10])

        #expect(shares.map(\.percent) == [34, 33, 33])
        #expect(shares.reduce(0) { $0 + $1.percent } == 100)
    }

    @Test(
        "各段百分比之和**恒为 100**（差数补给余数最大的那段）",
        arguments: [
            ["A": 1],                                  // 单段
            ["A": 1, "B": 1, "C": 1],                  // 均分
            ["A": 2, "B": 2, "C": 2],                  // 总数为偶数的均分
            ["A": 1, "B": 1, "C": 1, "D": 1, "E": 1],  // 五段
            ["A": 7, "B": 7, "C": 7],                  // 21 —— 与 10/10/10 同一形状
            ["A": 999, "B": 1],
            ["A": 1, "B": 999],
            ["A": 3, "B": 3, "C": 2, "D": 2],
        ]
    )
    func percentagesAlwaysSumToOneHundred(_ input: [String: Int]) {
        let shares = LanguageComposition.shares(from: input)

        #expect(!shares.isEmpty)
        #expect(shares.reduce(0) { $0 + $1.percent } == 100, "输入 \(input) 的百分比之和不是 100")
        #expect(shares.allSatisfy { $0.percent >= 0 && $0.percent <= 100 })
    }

    @Test("具名语言之间按字节降序 —— 占比条从左到右越来越小")
    func namedSegmentsAreDescending() {
        let shares = LanguageComposition.shares(from: ["A": 500, "B": 300, "C": 150, "D": 50])

        let namedBytes = shares.filter { $0.language != nil }.map(\.bytes)
        #expect(namedBytes == namedBytes.sorted(by: >))
    }

    @Test("⚠️ 「其他」恒在**末尾**，即使它的字节数比前面的具名语言还多（与 GitHub 网页端一致）")
    func otherAlwaysTrailsEvenWhenItIsTheLargest() {
        // 4 种语言各 3/3/2/2 字节 ⇒ 被合并的两种合计 4，比任何一个具名语言都大。
        // 若按大小重排，「其他」会跑到第一位 —— 那读起来像"其他"是一个语言名。
        let shares = LanguageComposition.shares(from: ["A": 3, "B": 3, "C": 2, "D": 2])

        #expect(shares.map(\.label) == ["A", "B", "其他"])
        #expect(shares.map(\.percent) == [30, 30, 40])
        #expect(shares.last?.language == nil)
    }

    // MARK: - 标识与文案

    @Test("⚠️ 「其他」的 `id` 与具名语言不在一个命名空间（真的存在名叫「其他」的语言时不会撞）")
    func otherIDDoesNotCollideWithALanguageNamedOther() {
        let other = LanguageShare(language: nil, bytes: 1, percent: 1)
        let literal = LanguageShare(language: LanguageComposition.otherLabel, bytes: 1, percent: 1)

        #expect(other.label == literal.label)
        #expect(other.id != literal.id)
    }

    @Test("文案：`label` 与 `percentLabel`")
    func labels() {
        let shares = LanguageComposition.shares(from: ["Swift": 3, "Rust": 1])

        #expect(shares.map(\.label) == ["Swift", "Rust"])
        #expect(shares.map(\.percentLabel) == ["75%", "25%"])
    }
}
