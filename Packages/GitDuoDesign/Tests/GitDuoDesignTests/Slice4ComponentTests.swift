import SwiftUI
import Testing

@testable import GitDuoDesign

/// 两个纯函数“那一半”的断言 —— 图标换名与头像首字母。
///
/// 为什么只测这一半：视图的长相没法用断言描述（要靠截图与逐屏对照），
/// 但"已 Star 时到底用哪个符号""匿名贡献者画什么"是**可以**被钉住的规则，
/// 而它们恰好是最容易写错的两处（SF Symbols 里不是每个符号都有 `.fill` 变体）。
@MainActor
@Suite("切片 4 组件 · 纯函数部分")
struct Slice4ComponentTests {

    // MARK: - StatButton

    @Test("未激活 ⇒ 用常态符号")
    func inactiveUsesBaseSymbol() {
        let name = StatButton.resolvedSystemImage(
            systemImage: "star", activeSystemImage: "star.fill", isActive: false
        )
        #expect(name == "star")
    }

    @Test("激活且有激活态符号 ⇒ 换成实心")
    func activeUsesFilledSymbol() {
        let name = StatButton.resolvedSystemImage(
            systemImage: "star", activeSystemImage: "star.fill", isActive: true
        )
        #expect(name == "star.fill")
    }

    @Test("⚠️ 激活但**没有**激活态符号 ⇒ 沿用常态名，绝不自己拼一个 `.fill`")
    func activeWithoutFilledVariantKeepsBaseSymbol() {
        // `arrow.triangle.branch` 在 SF Symbols 里没有 `.fill` 变体。
        // 若按"名字追加 .fill"来推导，会拿到一个不存在的符号名 ——
        // 界面上表现为**图标凭空消失**（而不是报错），排查时很难想到这一层。
        let name = StatButton.resolvedSystemImage(
            systemImage: "arrow.triangle.branch", activeSystemImage: nil, isActive: true
        )
        #expect(name == "arrow.triangle.branch")
    }

    // MARK: - AvatarStack.Member

    @Test(
        "首字母取登录名的第一个字符并大写",
        arguments: [("jiangjiang", "J"), ("Dev-K", "D"), ("9号", "9")]
    )
    func initialComesFromLogin(_ login: String, _ expected: String) {
        #expect(AvatarStack.Member(login: login, avatarURL: nil).initial == expected)
    }

    @Test(
        "⚠️ 没有登录名 / 空名字 ⇒ `?`（不是空白圆圈 —— 那看起来像图片还在加载）",
        arguments: [nil, "", "   "]
    )
    func anonymousFallsBackToQuestionMark(_ login: String?) {
        #expect(AvatarStack.Member(login: login, avatarURL: nil).initial == "?")
    }
}
