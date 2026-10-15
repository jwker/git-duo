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

    // MARK: - 切片 4 新增的令牌

    private func components(of color: Color) -> [Float] {
        let resolved = color.resolve(in: EnvironmentValues())
        return [resolved.red, resolved.green, resolved.blue]
    }

    private func distance(_ lhs: Color, _ rhs: Color) -> Float {
        zip(components(of: lhs), components(of: rhs)).map { abs($0 - $1) }.reduce(0, +)
    }

    /// 已 Star 的金色（原型 `.stat-btn.starred svg{fill:#eac54f}`）。
    ///
    /// 两条都是真会踩到的坑：
    /// ① 它与三个**互斥状态色**混用 —— 金色与"已合并 / 已发布"的紫在色弱视觉下并不远，
    ///    而状态色是要用户一眼分辨的；
    /// ② 它被拿去当文字色 —— 金色在白底上对比度只有 1.5 左右，正文必然读不清。
    @Test("Star 激活金：与互斥状态色可辨，且**不是**文字色（对比度不足以承载正文）")
    func starActiveIsNotAStateColorNorTextColor() {
        for state in [Theme.Palette.stateOpen, Theme.Palette.stateMerged, Theme.Palette.stateClosed] {
            #expect(distance(Theme.Palette.starActive, state) > 0.15, "星标金与状态色过于接近")
        }

        // 已知偏差【已定 2026-10-06，见 TECH_SPEC §10.7 末】：它确实达不到非文字图形 3:1 的门槛，
        // 但它**不是唯一线索** —— 已 Star 同时由文案（`Starred · n`）与星形是否填充表达。
        // 本断言是下界护栏：将来若把它调得更浅，必须连同 §10.7 的偏差一起重新评估。
        let onChip = contrastRatio(Theme.Palette.starActive, Theme.Palette.surfaceSunken)
        #expect(onChip >= 1.4, "星标金在控件底色上的对比度掉到了不可辨的程度：\(onChip)")
        #expect(onChip < 3.0, "若哪天它达标了，请删掉 §10.7 的已知偏差登记")
    }

    @Test("头像兜底色：8 色、两两可辨（同一屏最多画 8 个，撞色就分不清谁是谁）")
    func avatarFallbackColorsAreDistinct() {
        let palette = Theme.Palette.avatarFallback
        #expect(palette.count == 8)

        for i in palette.indices {
            for j in palette.indices where j > i {
                #expect(distance(palette[i], palette[j]) > 0.15, "兜底色 \(i) 与 \(j) 过于接近")
            }
        }
    }

    @Test("占比条「其他」段的中性灰：与页面底 / 卡片面都分得开，但不抢眼")
    func shareNeutralIsVisibleButQuiet() {
        #expect(distance(Theme.Palette.shareNeutral, Theme.Palette.background) > 0.1)
        #expect(distance(Theme.Palette.shareNeutral, Theme.Palette.surface) > 0.1)

        // 它是"若干语言的合计"，不该比任何真实语言色更抢眼 —— 所以必须比正文灰更浅。
        #expect(luminance(Theme.Palette.shareNeutral) > luminance(Theme.Palette.textSecondary))
    }

    @Test("仓库图标底色与正文最深色是两个值（它们不该同步变化）")
    func repoAvatarSurfaceIsItsOwnToken() {
        #expect(Theme.Palette.repoAvatarSurface != Theme.Palette.textPrimary)
        // 但必须足够深，白色字形压在上面要读得出来（≥ 7:1，远超非文字图形的 3:1）。
        #expect(contrastRatio(Theme.Palette.surface, Theme.Palette.repoAvatarSurface) >= 7)
    }

    // MARK: - 4.4 表现层新增的令牌

    @Test("Toast：文字压在自己的深底上远超 AA，且底色**带一点透明**（原型 .92）")
    func toastColorsAreReadableAndTranslucent() {
        #expect(contrastRatio(Theme.Palette.toastText, Theme.Palette.toastSurface) >= 7)

        // 原型是 `rgba(28,32,36,.92)` —— 那 8% 透明不是笔误：浮层要透出一点下面的内容，
        // 全不透明会让它看起来像"贴上去的一块补丁"，而不是浮在内容之上。
        // 断言上界 1.0 是为了挡住"顺手把 opacity 去掉"这种改动。
        let surface = Theme.Palette.toastSurface.resolve(in: EnvironmentValues())
        #expect(surface.opacity > 0.85)
        #expect(surface.opacity < 1.0)

        // ⚠️ 它与仓库图标底是两个来源不同的值，别因为"看着差不多"而合并。
        #expect(Theme.Palette.toastSurface != Theme.Palette.repoAvatarSurface)
    }

    @Test("筛选 chip 的已选底是**强调色系的浅底**，不是中性灰（中性灰会让「已选」读成「禁用」）")
    func accentSurfaceIsTintedNotNeutral() {
        // ① 与中性 sunken 底分得开。
        #expect(distance(Theme.Palette.accentSurface, Theme.Palette.surfaceSunken) > 0.02)

        // ② 是"蓝底"：蓝色通道明显高于红色（中性灰的三通道几乎相等）。
        let resolved = Theme.Palette.accentSurface.resolve(in: EnvironmentValues())
        #expect(resolved.blue > resolved.red)

        // ③ 但必须够浅 —— 强调色的文字压在上面要达到正文 AA。
        #expect(contrastRatio(Theme.Palette.accent, Theme.Palette.accentSurface) >= 4.5)
    }
}
