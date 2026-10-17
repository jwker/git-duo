import SwiftUI
import Testing

@testable import GitDuoDesign

/// 切片 5 三个新件里"纯函数那一半"的断言 —— 胶囊三族配色、头像首字母、兜底色下标。
///
/// 为什么只测这一半：视图的长相没法用断言描述（要靠截图与逐屏对照），
/// 但"哪一族配哪三处颜色""匿名画什么""同一个登录名拿到的是不是同一个颜色"
/// 都是**可以**被钉住的规则，而它们恰好是最容易出错的三处。
@MainActor
@Suite("切片 5 组件 · 纯函数部分")
struct Slice5ComponentTests {

    // MARK: - StatusPill

    @Test("⚠️ 只有三族 —— 原型四个类名里 `.closed-i` 与 `.merged` 同色，不另立同值异名的档位")
    func onlyThreeTones() {
        #expect(StatusPill.Tone.allCases.count == 3)
    }

    @Test("三族各自成组：前景 / 底 / 边都落在同一族的 token 上")
    func toneFamiliesAreConsistent() {
        #expect(StatusPill.foreground(.open) == Theme.Palette.stateOpen)
        #expect(StatusPill.surface(.open) == Theme.Palette.stateOpenSurface)
        #expect(StatusPill.border(.open) == Theme.Palette.stateOpenBorder)

        #expect(StatusPill.foreground(.merged) == Theme.Palette.stateMerged)
        #expect(StatusPill.surface(.merged) == Theme.Palette.stateMergedSurface)
        #expect(StatusPill.border(.merged) == Theme.Palette.stateMergedBorder)

        #expect(StatusPill.foreground(.closed) == Theme.Palette.stateClosed)
        #expect(StatusPill.surface(.closed) == Theme.Palette.stateClosedSurface)
        #expect(StatusPill.border(.closed) == Theme.Palette.stateClosedBorder)
    }

    @Test("⚠️ 三族的底 / 边两两不同 —— 两族同色会让「红字配绿底」这类串味事故看不出来")
    func toneColorsAreDistinct() {
        // 逐对比，不用 `Set`：这里要断言的是"两两不同"，逐对写出来失败时能直接指出是哪一对。
        #expect(StatusPill.surface(.open) != StatusPill.surface(.merged))
        #expect(StatusPill.surface(.merged) != StatusPill.surface(.closed))
        #expect(StatusPill.surface(.open) != StatusPill.surface(.closed))

        #expect(StatusPill.border(.open) != StatusPill.border(.merged))
        #expect(StatusPill.border(.merged) != StatusPill.border(.closed))
        #expect(StatusPill.border(.open) != StatusPill.border(.closed))
    }

    @Test("⚠️ 前景走的是**胶囊**那族，不是**图标**那族 —— 两族值不同，混用会让图标与文字串味")
    func foregroundDoesNotUseIconFamily() {
        // 这是 `Theme.Palette.stateOpenIcon` 的文档专门警告过的坑：
        // 两个绿值、两个紫值都"看起来差不多"，取错了不报错、只是颜色微妙地不一致。
        #expect(StatusPill.foreground(.open) != Theme.Palette.stateOpenIcon)
        #expect(StatusPill.foreground(.merged) != Theme.Palette.stateCompletedIcon)
    }

    // MARK: - UserAvatar

    @Test(
        "首字母取登录名的第一个字符并大写",
        arguments: [("jiangjiang", "J"), ("Dev-K", "D"), ("9号", "9")]
    )
    func initialComesFromLogin(_ login: String, _ expected: String) {
        #expect(UserAvatar.initial(for: login) == expected)
    }

    @Test(
        "⚠️ 没有登录名 / 空名字 / 全空白 ⇒ `?`（不是空白圆圈 —— 那看起来像图片还在加载）",
        arguments: [nil, "", "   "]
    )
    func blankLoginFallsBackToQuestionMark(_ login: String?) {
        #expect(UserAvatar.initial(for: login) == "?")
    }

    @Test("⚠️ `AvatarStack.Member.initial` 与 `UserAvatar.initial` 是**同一份实现**（不是各写一遍）")
    func memberInitialDelegatesToUserAvatar() {
        for login in ["jiangjiang", "Dev-K", "9号", nil, "", "   "] as [String?] {
            #expect(AvatarStack.Member(login: login, avatarURL: nil).initial == UserAvatar.initial(for: login))
        }
    }
}
