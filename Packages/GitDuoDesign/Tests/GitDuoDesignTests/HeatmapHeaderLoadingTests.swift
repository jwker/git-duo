import CoreGraphics
import SwiftUI
import Testing

@testable import GitDuoDesign

/// 年份切换器那枚**在途指示器**（2026-10-12 加，走查第 61 条的**后半**）。
///
/// ## 为什么这一条要"渲染"才测得出
///
/// 它要守的性质是**几何**的：`HeatmapHeader` 的年份标签左边有一个**恒占位**的槽位，
/// 在途时里面才画转圈 —— 好让标题与箭头在"点完 → 取数回来"那一段里**一动不动**。
/// 而"槽位有没有真的占住地方"**在源码里看不出来**：写成"外面永远包一层 `frame`"
/// 与写成"在途才嵌进去"是两行差不多长的代码，而后者会让右对齐的标题左右横跳
/// `loadingSlot + xs = 16pt`（正是用户报"点了没反应 / 要点两次"那一类观感问题的温床）。
///
/// ⇒ 借 `ImageRenderer` 把这一行**真渲染出来**，拿**理想尺寸**比两个状态。
/// ⚠️ 本包其余测试只测纯函数（"不测长相"），这一条测的也不是长相，是**几何**：
/// 它不关心画出来什么样，只关心"多留的那一块地方在不在"。
///
/// ## 四条边界（都是实测踩出来的，别绕开）
///
/// ⚠️ **比的是"不给宽度时的理想尺寸"**，不是给死宽度之后的：`HeatmapHeader` 这一行
/// 右对齐（左边一个 `Spacer`），给死宽度之后插入一个视图会被 `Spacer` 吸收掉、
/// 总量不变 ⇒ **量不出"标题被推走了"**。不给宽度时，理想宽度 = 左边那个数 + 槽位 +
/// 标题 + 箭头 ⇒ 槽位一少就是少 `loadingSlot + xs`。
/// ⚠️ **不比像素**：宿主机上**同一个状态连着渲染两次都会差出一大片**（`Menu` 的外观
/// 由系统决定，渲染进程里会变 —— 实测差异框能到 628 × 48）⇒ 像素断言必然是假红的。
/// ⚠️ 跑在宿主机上 ⇒ 这里是 **macOS 的 `Menu` 外观**，而且 `ProgressView` 会画成一个
/// "不支持"的占位符 ⇒ **"iOS 上那枚转圈长什么样"这一条测不了**。那件事在
/// `HeatmapHeader` 的 `#Preview` 里看（那一份特意把"在途"与"不在途"两张并排摆着）。
/// ⚠️ **别把这里的渲染连成一串**：`ImageRenderer` 必须在主线程上跑、一张约 90ms，
/// 而同一进程里还有**计时**用例（`ToastCenter` 那几条 80ms 倒计时等 300ms）
/// —— 连量四张 = 一次 ~350ms 的主线程独占，实测让那条计时用例假红过一次
/// （`make verify` 里 `到时间自动消失` 失败）。所以每张之间 `await Task.yield()`。
@MainActor
@Suite("热力图头部的在途指示器 · 槽位恒占位")
struct HeatmapHeaderLoadingTests {

    @Test("⚠️ 在途 / 不在途，这一行的**理想尺寸逐字相同**（槽位恒占位）")
    func loadingIndicatorReservesItsSlot() async throws {
        // 两档都量：有总数那一档 + 失败态那一档。失败态最矮（左边那个数不画），
        // 槽位一旦不占位，它在两个状态之间的差也最露馅。
        let cases: [(label: String, totalText: String?)] = [
            ("有总数那一档", "1,024 次贡献"),
            ("失败态那一档", nil),
        ]

        for item in cases {
            let idle = try #require(idealSize(totalText: item.totalText, isLoading: false))
            // ⚠️ 每张之间**让出主线程**：渲染是主线程上的同步活儿（一张约 90ms），
            //    连着量四张就是一次 ~350ms 的独占。同一进程里还跑着**计时**用例
            //    （`ToastCenter` 那几条 80ms 倒计时等 300ms），实测撞过一次假红
            //    （`make verify` 里 `到时间自动消失` 报 `isShowing == false` 失败）。
            //    `yield` 之后那段时间被切成一格一格，排队的续体有机会插进来。
            await Task.yield()
            let loading = try #require(idealSize(totalText: item.totalText, isLoading: true))
            await Task.yield()

            // 先确认"量到了东西"：渲染器哪天量出个 0，这条断言会**静默失去意义**。
            #expect(idle.width > 0 && idle.height > 0)

            #expect(
                idle == loading,
                """
                \(item.label)：在途的理想尺寸 \(String(describing: loading)) 与不在途的 \(String(describing: idle)) 不同 \
                ⇒ 槽位没占住地方。若槽位写成"在途才嵌进去"，这一行会在两个状态之间差出 \
                \(HeatmapHeader.loadingSlot + Theme.Spacing.xs)pt，而这一行是右对齐的 \
                —— 那 16pt 就是标题与箭头的一次左右横跳。
                """
            )
        }
    }

    /// 渲染一次，返回**理想尺寸**（不给宽度、不给高度 ⇒ 量的是内容自己要多大）。
    ///
    /// 两侧都加同样的 8pt 内边距与白底：内边距让边界上的抗锯齿不落在裁剪线上，
    /// 白底只是因为本包是固定浅色一套（与断言无关）。
    private func idealSize(totalText: String?, isLoading: Bool) -> CGSize? {
        let header = HeatmapHeader(
            totalText: totalText,
            yearTitle: "2026 年",
            yearOptions: [
                HeatmapYear(year: 2026, title: "2026 年"),
                HeatmapYear(year: 2025, title: "2025 年"),
                HeatmapYear(year: 2024, title: "2024 年"),
            ],
            selectedYear: 2026,
            isLoading: isLoading,
            yearAccessibilityLabel: "切换年份，当前 2026 年",
            onSelectYear: { _ in }
        )
        .padding(8)
        .background(Theme.Palette.surface)

        let renderer = ImageRenderer(content: header)
        // scale = 1 ⇒ 像素尺寸就是 pt 尺寸，断言里不用再折算。
        renderer.scale = 1
        return renderer.cgImage.map { CGSize(width: $0.width, height: $0.height) }
    }
}
