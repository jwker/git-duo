import SwiftUI
import Testing

@testable import GitDuoDesign

/// 设计令牌的**不变式测试**。
///
/// 为什么值得测：TECH_SPEC §10.7 要求颜色必须走语义 token，理由是"补深色时只补一列映射"。
/// 而这条承诺只有在**浅色本身对比度达标**时才有意义——否则补深色时必然要重新校准对比度，
/// 又变成逐页返工。所以把 WCAG AA 对比度固化成断言，而不是靠肉眼。
@Suite("Theme · 语义令牌不变式")
struct ThemeTests {

    /// sRGB 相对亮度（WCAG 2.1 定义）
    private func luminance(_ color: Color) -> Double {
        let resolved = color.resolve(in: EnvironmentValues())
        func channel(_ value: Float) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(resolved.red)
            + 0.7152 * channel(resolved.green)
            + 0.0722 * channel(resolved.blue)
    }

    private func contrastRatio(_ a: Color, _ b: Color) -> Double {
        let l1 = max(luminance(a), luminance(b))
        let l2 = min(luminance(a), luminance(b))
        return (l1 + 0.05) / (l2 + 0.05)
    }

    @Test("正文 / 次要文字在 surface 与 background 上都满足 WCAG AA（≥ 4.5:1）")
    func bodyTextContrast() {
        for surface in [Theme.Palette.surface, Theme.Palette.background] {
            #expect(contrastRatio(Theme.Palette.textPrimary, surface) >= 4.5)
            #expect(contrastRatio(Theme.Palette.textSecondary, surface) >= 4.5)
        }
    }

    @Test("三级文字：卡片面达标；灰色页面底为**已接受的已知偏差**（TECH_SPEC §10.7）")
    func tertiaryTextContrast() {
        #expect(contrastRatio(Theme.Palette.textTertiary, Theme.Palette.surface) >= 3.0)

        // 已知偏差【已定 2026-10-05】：原型的三级灰 #8B949E 在页面底 #F6F8FA 上只有 2.89:1，
        // 低于大字号 3:1 门槛。决策为**保留现值**——该 token 只用于时间戳等极弱信息；
        // 调色等于改产品视觉，而原型是唯一可点验收依据。详见 TECH_SPEC §10.7「已知偏差」。
        // 本断言是**下界护栏**：将来调色若低于 2.85，必须连同该偏差一起重新评估。
        #expect(contrastRatio(Theme.Palette.textTertiary, Theme.Palette.background) >= 2.85)
    }

    @Test("互斥状态色两两可辨（开放 / 已合并 / 已关闭 不得撞色）")
    func stateColorsAreDistinct() {
        func rgb(_ color: Color) -> [Float] {
            let c = color.resolve(in: EnvironmentValues())
            return [c.red, c.green, c.blue]
        }
        let mutual = [rgb(Theme.Palette.stateOpen), rgb(Theme.Palette.stateMerged), rgb(Theme.Palette.stateClosed)]

        for i in mutual.indices {
            for j in mutual.indices where j > i {
                let distance = zip(mutual[i], mutual[j]).map { abs($0 - $1) }.reduce(0, +)
                #expect(distance > 0.15, "状态色 \(i) 与 \(j) 过于接近，色弱用户无法区分")
            }
        }
    }

    @Test("已合并与已发布同色属**有意为之**（紫族），改动必须同时改文档")
    func mergedAndReleasedSharePurple() {
        #expect(Theme.Palette.stateMerged == Theme.Palette.stateReleased)
    }

    @Test("diff 增删色与危险色：正文在底色上可读，且增删底色互不相同")
    func diffColors() {
        #expect(contrastRatio(Theme.Palette.diffAddedText, Theme.Palette.diffAddedSurface) >= 4.5)
        #expect(contrastRatio(Theme.Palette.diffDeletedText, Theme.Palette.diffDeletedSurface) >= 4.5)

        let added = Theme.Palette.diffAddedSurface.resolve(in: EnvironmentValues())
        let deleted = Theme.Palette.diffDeletedSurface.resolve(in: EnvironmentValues())
        #expect(added.green != deleted.green || added.red != deleted.red)
    }

    @Test("玻璃 tint 走令牌且不是全透明（§10.4 #4：浅色约 30% 混合）")
    func glassTintIsTokenized() {
        let tint = Theme.Palette.glassTint.resolve(in: EnvironmentValues())
        #expect(tint.opacity > 0.2 && tint.opacity < 0.4)
    }

    @Test("间距与圆角为递增的正值尺度（防止出现魔法值式的零散数值）")
    func scalesAreOrdered() {
        let spacings = [Theme.Spacing.xxs, Theme.Spacing.xs, Theme.Spacing.s,
                        Theme.Spacing.m, Theme.Spacing.l, Theme.Spacing.xl, Theme.Spacing.xxl]
        #expect(spacings == spacings.sorted())
        #expect(spacings.allSatisfy { $0 > 0 })

        let radii = [Theme.Radius.chip, Theme.Radius.card, Theme.Radius.container, Theme.Radius.sheet]
        #expect(radii == radii.sorted())
    }
}
