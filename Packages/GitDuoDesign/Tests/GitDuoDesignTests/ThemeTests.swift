import SwiftUI
import Testing

@testable import GitDuoDesign

/// 设计令牌的**不变式测试** —— 2026-10-15 起双档化（走查第 69 条）。
///
/// 为什么值得测：TECH_SPEC §10.7 要求颜色必须走语义 token，承诺是"补深色只补一列映射"。
/// 深色列接通后，每条对比度断言都要在**浅 / 深两个 colorScheme 下分别成立**——
/// 否则"浅色达标、深色不可读"的令牌会静默上线。
///
/// ## ⚠️ 辅助函数的一条关键修正：alpha 合成
///
/// 原实现 `luminance` 直接取 `resolve` 的 RGB 分量，**忽略了 alpha** ——
/// 浅色档没踩到（表面色都不透明），但深色档的胶囊底全是 Primer 式"同色相低透明"
/// （`#2ea04326` 这类）。解析出的纯色与其真实观感完全不同
/// （例：`diffAddedText #3fb950` 对"纯 `#2ea043`"只有 1.3:1，
/// 而对"叠在卡面上的合成色"是 5.5:1 —— 后者才是屏幕上的事实）。
/// 所以带透明度的表面色一律先 `flatten(over:)` 到卡面上再算对比度。
/// ## ⚠️ 本套件必须跑在**主线程**（`@MainActor`）
///
/// 死锁实录（2026-10-15）：断言里大量 `Color.resolve(in:)`，而双列令牌在 **macOS**
/// （`swift test` 跑的就是 macOS 变体）走 `NSColor(name:)` dynamic provider ——
/// **非主线程 resolve 直接死锁**（探针实锤：后台线程"resolving…"后 15 秒无返回；
/// 主线程毫秒级完成）。swift-testing 并行/串行执行都不保证主线程 ⇒ 整套件挂起
/// （`make verify` 第 4 包 20 分钟零输出）。
///
/// ⚠️ 运行时含义（两件事分开）：
/// ① **iOS**（本 App 的 target）走 `UIColor(dynamicProvider:)` —— 官方模式、海量生产验证，
///    SwiftUI 渲染线程 resolve 是常态，不受此坑影响；
/// ② **macOS** 若哪天真构建 App，NSColor 动态色必须在主线程取色 —— 已在
///    `Theme.swift` 的 provider 处登记。本套件标 `@MainActor` 既绕开死锁，
///    也和"主线程才是唯一可信的取色语境"这条约定一致。
/// （这也是"swift-testing 默认没有超时"那条血泪的又一形状 —— 外部看起来像"编译很慢"。）
@Suite("Theme · 语义令牌不变式", .serialized)
@MainActor
struct ThemeTests {

    // MARK: - 双档求值辅助

    private var env: (light: EnvironmentValues, dark: EnvironmentValues) {
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        return (EnvironmentValues(), dark)
    }

    private struct Components {
        let red: Float, green: Float, blue: Float, alpha: Float
    }

    private func resolved(_ color: Color, _ scheme: ColorScheme) -> Components {
        let e = scheme == .dark ? env.dark : env.light
        let c = color.resolve(in: e)
        return Components(red: c.red, green: c.green, blue: c.blue, alpha: c.opacity)
    }

    private func luminance(_ rgb: [Float]) -> Double {
        func channel(_ value: Float) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb[0]) + 0.7152 * channel(rgb[1]) + 0.0722 * channel(rgb[2])
    }

    private func rgb(_ color: Color, _ scheme: ColorScheme) -> [Float] {
        let c = resolved(color, scheme)
        return [c.red, c.green, c.blue]
    }

    /// 把带 alpha 的表面色**按真实渲染**叠到 `base`（通常传 `surface`）上再取分量。
    /// 预乘 / 直通 alpha 两种语义下这条合成公式的数值相同，无歧义。
    private func flattened(_ top: Color, over base: Color, _ scheme: ColorScheme) -> [Float] {
        let t = resolved(top, scheme)
        let b = rgb(base, scheme)
        let a = t.alpha
        return [Float]([t.red, t.green, t.blue].indices.map { i in
            [t.red, t.green, t.blue][i] * a + b[i] * (1 - a)
        })
    }

    private func contrast(_ top: [Float], _ bottom: [Float]) -> Double {
        let l1 = max(luminance(top), luminance(bottom))
        let l2 = min(luminance(top), luminance(bottom))
        return (l1 + 0.05) / (l2 + 0.05)
    }

    /// 文字色（不透明）压在表面色上的对比度 —— 表面色带 alpha 时先合成到卡面上。
    private func contrast(_ text: Color, on surface: Color, scheme: ColorScheme) -> Double {
        let surfaceRGB: [Float] = resolved(surface, scheme).alpha < 1
            ? flattened(surface, over: Theme.Palette.surface, scheme)
            : rgb(surface, scheme)
        return contrast(rgb(text, scheme), surfaceRGB)
    }

    private func distance(_ lhs: Color, _ rhs: Color, _ scheme: ColorScheme) -> Float {
        zip(rgb(lhs, scheme), rgb(rhs, scheme)).map { abs($0 - $1) }.reduce(0, +)
    }

    private let bothSchemes: [ColorScheme] = [.light, .dark]

    // MARK: - 正文与三级文字

    @Test("两档下：正文 / 次要文字在 surface 与 background 上都满足 WCAG AA（≥ 4.5:1）")
    func bodyTextContrast() {
        for scheme in bothSchemes {
            for surface in [Theme.Palette.surface, Theme.Palette.background] {
                #expect(contrast(Theme.Palette.textPrimary, on: surface, scheme: scheme) >= 4.5,
                        "\(scheme) 档 textPrimary 对比不足")
                #expect(contrast(Theme.Palette.textSecondary, on: surface, scheme: scheme) >= 4.5,
                        "\(scheme) 档 textSecondary 对比不足")
            }
        }
    }

    @Test("两档下：三级文字在两种底上都达标（浅色档保留 2.85 下界护栏的既有偏差）")
    func tertiaryTextContrast() {
        // 深色档（#6e7681 压 #161b22 / #0d1117）两项都在 3.5 以上 —— 深色没有这个偏差。
        // 浅色档保留原登记：#8B949E 压页面底 2.89:1，已接受（TECH_SPEC §10.7），只钉下界。
        #expect(contrast(Theme.Palette.textTertiary, on: Theme.Palette.surface, scheme: .light) >= 3.0)
        #expect(contrast(Theme.Palette.textTertiary, on: Theme.Palette.background, scheme: .light) >= 2.85)
        #expect(contrast(Theme.Palette.textTertiary, on: Theme.Palette.surface, scheme: .dark) >= 3.0)
        #expect(contrast(Theme.Palette.textTertiary, on: Theme.Palette.background, scheme: .dark) >= 2.85)
    }

    // MARK: - 状态色

    @Test("两档下：互斥状态色两两可辨（开放 / 已合并 / 已关闭不得撞色）")
    func stateColorsAreDistinct() {
        for scheme in bothSchemes {
            let mutual = [
                rgb(Theme.Palette.stateOpen, scheme),
                rgb(Theme.Palette.stateMerged, scheme),
                rgb(Theme.Palette.stateClosed, scheme),
            ]
            for i in mutual.indices {
                for j in mutual.indices where j > i {
                    let d = zip(mutual[i], mutual[j]).map { abs($0 - $1) }.reduce(0, +)
                    #expect(d > 0.15, "\(scheme) 档状态色 \(i) 与 \(j) 过于接近，色弱用户无法区分")
                }
            }
        }
    }

    @Test("两档下：已合并与已发布同色属**有意为之**（紫族），改动必须同时改文档")
    func mergedAndReleasedSharePurple() {
        // ⚠️ 动态色时代不能再用 `Color ==`：两个令牌各自构造 provider 实例，
        // 同值也会带不同的平台标识（`#$customDynamic <UUID>`）—— 比较的是"身份"不是"值"。
        // 改成比两档 resolve 分量：值相等才是这条不变式的本意。
        for scheme in bothSchemes {
            #expect(rgb(Theme.Palette.stateMerged, scheme) == rgb(Theme.Palette.stateReleased, scheme),
                    "\(scheme) 档已合并与已发布不同色 —— 同色是有意的（改动必须同时改文档）")
        }
    }

    // MARK: - diff

    @Test("两档下：diff 增删文字压在（合成后的）底色上可读，且增删底色互不相同")
    func diffColors() {
        for scheme in bothSchemes {
            // 表面色带透明度（深色档 #2ea04326 那类）⇒ 先合成到卡面上，见类型说明。
            #expect(contrast(Theme.Palette.diffAddedText, on: Theme.Palette.diffAddedSurface, scheme: scheme) >= 4.5,
                    "\(scheme) 档 diffAdded 对比不足")
            #expect(contrast(Theme.Palette.diffDeletedText, on: Theme.Palette.diffDeletedSurface, scheme: scheme) >= 4.5,
                    "\(scheme) 档 diffDeleted 对比不足")

            let added = flattened(Theme.Palette.diffAddedSurface, over: Theme.Palette.surface, scheme)
            let deleted = flattened(Theme.Palette.diffDeletedSurface, over: Theme.Palette.surface, scheme)
            #expect(added[1] != deleted[1] || added[0] != deleted[0], "\(scheme) 档增删底色撞了")
        }
    }

    // MARK: - 玻璃

    @Test("玻璃 tint 走令牌且两档混合比例不同（§10.4 #4：浅 30% / 深 50%）")
    func glassTintIsTokenized() {
        let lightTint = resolved(Theme.Palette.glassTint, .light)
        let darkTint = resolved(Theme.Palette.glassTint, .dark)
        #expect(lightTint.alpha > 0.2 && lightTint.alpha < 0.4)
        #expect(darkTint.alpha > 0.4 && darkTint.alpha < 0.6)
        #expect(lightTint.alpha != darkTint.alpha, "两档混合比例不同是既定口径，别顺手统一")
    }

    // MARK: - 间距 / 圆角

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

    /// 已 Star 的金色（原型 `.stat-btn.starred svg{fill:#eac54f}`）。
    ///
    /// 两条都是真会踩到的坑：
    /// ① 它与三个**互斥状态色**混用 —— 金色与"已合并 / 已发布"的紫在色弱视觉下并不远，
    ///    而状态色是要用户一眼分辨的；
    /// ② 它被拿去当文字色 —— 金色在白底上对比度只有 1.5 左右，正文必然读不清。
    ///
    /// ⚠️ ②只对**浅色档**成立：深色档（`#e3b341` 压深底）对比度天然很高，
    /// "高对比"在那里是好事，不该被误判成"偏差没登记"。
    @Test("两档下 Star 金与状态色可辨；「不可作文字色」的偏差登记只属于浅色档")
    func starActiveIsNotAStateColorNorTextColor() {
        for scheme in bothSchemes {
            for state in [Theme.Palette.stateOpen, Theme.Palette.stateMerged, Theme.Palette.stateClosed] {
                #expect(distance(Theme.Palette.starActive, state, scheme) > 0.15,
                        "\(scheme) 档星标金与状态色过于接近")
            }
        }

        // 已知偏差【已定 2026-10-06，见 TECH_SPEC §10.7 末】：浅色档达不到非文字图形 3:1 的门槛，
        // 但它**不是唯一线索** —— 已 Star 同时由文案与星形是否填充表达。
        // 下界护栏：将来若把它调得更浅，必须连同 §10.7 的偏差一起重新评估。
        let onChip = contrast(Theme.Palette.starActive, on: Theme.Palette.surfaceSunken, scheme: .light)
        #expect(onChip >= 1.4, "浅色档星标金在控件底色上掉到了不可辨的程度：\(onChip)")
        #expect(onChip < 3.0, "若哪天它达标了，请删掉 §10.7 的已知偏差登记")
    }

    @Test("两档下：「其他」段的中性灰与两种底都分得开，且不抢眼（方向随档反转）")
    func shareNeutralIsVisibleButQuiet() {
        for scheme in bothSchemes {
            #expect(distance(Theme.Palette.shareNeutral, Theme.Palette.background, scheme) > 0.1,
                    "\(scheme) 档与页面底分不开")
            #expect(distance(Theme.Palette.shareNeutral, Theme.Palette.surface, scheme) > 0.1,
                    "\(scheme) 档与卡面分不开")
        }

        // "不抢眼"的方向两档相反：浅色下安静 = 比正文灰**浅**，深色下 = 比"正文次级"**暗**。
        #expect(luminance(rgb(Theme.Palette.shareNeutral, .light)) > luminance(rgb(Theme.Palette.textSecondary, .light)))
        #expect(luminance(rgb(Theme.Palette.shareNeutral, .dark)) < luminance(rgb(Theme.Palette.textSecondary, .dark)))
    }

    @Test("两档下：仓库图标块是独立令牌、白字形压得读出、与卡面分得开")
    func repoAvatarSurfaceIsItsOwnToken() {
        for scheme in bothSchemes {
            #expect(Theme.Palette.repoAvatarSurface != Theme.Palette.textPrimary)

            // 白字形压在块底上要读得出来（≥ 7:1，远超非文字图形的 3:1）。
            // ⚠️ 对比的双方是"白字形 vs 块底"—— 不是卡面 vs 块底（浅色档原断言写反了语义，
            // 恰好白卡 ≈ 白字形才没炸；深色档卡面是深灰，一改就炸了出来）。
            let whiteOnBlock = contrast(rgb(Theme.Palette.toastText, scheme),
                                        rgb(Theme.Palette.repoAvatarSurface, scheme))
            #expect(whiteOnBlock >= 7, "\(scheme) 档白字形压图标块读不出：\(whiteOnBlock)")

            // 块要与嵌着它的卡面分得开（否则图标块整个隐形）。
            #expect(distance(Theme.Palette.repoAvatarSurface, Theme.Palette.surface, scheme) > 0.02,
                    "\(scheme) 档图标块与卡面分不开")
        }
    }

    // MARK: - 4.4 表现层新增的令牌

    @Test("两档下：Toast 文字压在自己的底上远超 AA，且底色带一点透明")
    func toastColorsAreReadableAndTranslucent() {
        for scheme in bothSchemes {
            #expect(contrast(Theme.Palette.toastText, on: Theme.Palette.toastSurface, scheme: scheme) >= 7,
                    "\(scheme) 档 Toast 文字对比不足")

            // 8% 透明不是笔误：浮层要透出一点下面的内容。断言上界挡住"顺手把 opacity 去掉"。
            let surface = resolved(Theme.Palette.toastSurface, scheme)
            #expect(surface.alpha > 0.85)
            #expect(surface.alpha < 1.0)

            // ⚠️ 它与仓库图标底是两个来源不同的值，别因为"看着差不多"而合并。
            // ⚠️ 动态色时代 `Color !=` 恒真（实例必不同）⇒ 改比 resolve 分量。
            #expect(rgb(Theme.Palette.toastSurface, scheme) != rgb(Theme.Palette.repoAvatarSurface, scheme),
                    "\(scheme) 档 Toast 底与图标块底撞了")
        }
    }

    @Test("两档下：筛选 chip 的已选底是**强调色系的淡底**，不是中性灰")
    func accentSurfaceIsTintedNotNeutral() {
        for scheme in bothSchemes {
            // ① 与中性 sunken 底分得开。
            #expect(distance(Theme.Palette.accentSurface, Theme.Palette.surfaceSunken, scheme) > 0.02,
                    "\(scheme) 档已选底与中性底分不开")

            // ② 是"暖底"：红色通道明显高于蓝色（中性灰的三通道几乎相等）。
            // ⚠️ 2026-10-17 主色由蓝统一为橙 ⇒ 这一条从 `blue > red` **反了过来**。
            // 它钉的从来不是"蓝"，而是"**它跟中性灰不是一个族**"这个意思 —— 换成橙之后
            // 由红通道承担这个信号（判据本身没变，只是方向的来源从 `--link` 换成主色橙）。
            let c = resolved(Theme.Palette.accentSurface, scheme)
            #expect(c.red > c.blue, "\(scheme) 档已选底不是暖色族")

            // ③ 强调色文字压在（合成后的）已选底上要达到正文 AA。
            #expect(contrast(Theme.Palette.accent, on: Theme.Palette.accentSurface, scheme: scheme) >= 4.5,
                    "\(scheme) 档强调文字压已选底对比不足")
        }
    }

    // MARK: - 语法四色（深色档，走查第 69 条补）

    @Test("两档下：语法四色互不相同、且都不等于 textPrimary（取错一个不报错、只让代码看着怪）")
    func syntaxColorsAreDistinctInBothSchemes() {
        for scheme in bothSchemes {
            let four = [
                rgb(Theme.Palette.syntaxKeyword, scheme),
                rgb(Theme.Palette.syntaxFunction, scheme),
                rgb(Theme.Palette.syntaxString, scheme),
                rgb(Theme.Palette.syntaxComment, scheme),
            ]
            for i in four.indices {
                for j in four.indices where j > i {
                    let d = zip(four[i], four[j]).map { abs($0 - $1) }.reduce(0, +)
                    #expect(d > 0.05, "\(scheme) 档语法色 \(i) 与 \(j) 过于接近")
                }
            }
            for color in [Theme.Palette.syntaxKeyword, Theme.Palette.syntaxFunction,
                          Theme.Palette.syntaxString, Theme.Palette.syntaxComment] {
                #expect(distance(color, Theme.Palette.textPrimary, scheme) > 0.05,
                        "\(scheme) 档有语法色与正文同色")
            }
        }
    }
}
