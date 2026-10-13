import SwiftUI

/// 热力图卡片顶部那一行 —— 左边总数、右边**年份切换器**
/// （PRD §4.17 第 3 条、2026-10-09 加，用户走查第 2 条）。
///
/// ## 为什么把它从 `ContributionHeatmap` 里抽出来
///
/// 因为**失败态也要有它**：某一年的贡献取不到时，卡片里换成一行灰字 + 重试，
/// 而那时用户最需要的东西恰恰是**切回能看的那一年**（或切到别的年份再试）。
/// 把这一行留在 `ContributionHeatmap` 内部、失败态另画一套，会出现两个几乎一样
/// 但对不齐的头部（间距差 2pt、年份字号不一致这类），而且"失败态没有切换器"
/// 这种缺口**只在离线时才看得见**。
///
/// ## 年份切换器为什么是 `Menu` 而不是分段控件
///
/// 分段控件（三个格子）要塞进这一行就得自己占一行（约 +32pt），而这一行的左边
/// 只有一个数 —— 空着一大片。`Menu` 的标签就是"当前是哪一年"这句话本身，
/// 点开才是选项，于是**范围声明与控件是同一个东西**（`ProfileCopy.yearLabel`）。
///
/// ## ⚠️ 选中之后**不是立刻**变成新值（2026-10-12 补记，走查第 61 条）
///
/// 这里的"当前是哪一年"来自**取数结果**（`ProfileView` 传的是 `overview.year`，
/// 那条纪律是"年份与总数必须来自同一份数据"），而切一年要发一次 GraphQL
/// ⇒ **点完到标题变，中间隔着一个往返**。这是有意的（宁可晚半秒，也不要
/// "写着 2025、画着 2026"）。
///
/// ⚠️ 但这个"晚半秒"决定了**菜单项不能用 `Picker` 去接**：受控控件要求 `set` 之后
/// 回读立刻拿到新值，而我们给不出。理由与症状详写在 `yearMenu` 里（那是本条的根因）。
///
/// ## 那个"晚半秒"要有可见的交代（2026-10-12 加，走查第 61 条的后半）
///
/// 上一节那个往返里，屏幕上**本来是没有任何变化的** —— 用户看不出自己是点上了还是
/// 点空了（那正是他反复点、然后报回"需要点两次"的第二个来源）。所以年份标签左边有
/// 一个**恒定占位**的小转圈，只在 `isLoading` 时显形。
///
/// ⚠️ **槽位恒在**（不在途时也留着那一小块）：这一行是右对齐的，插入一个视图会把
/// 标题与箭头推出去 16pt、取数回来再弹回来 —— 那比"没有反馈"更烦。槽位在 `Spacer`
/// 右边，吃的是本来就空着的地方 ⇒ 视觉上等于不存在（有渲染断言钉住这一点）。
///
/// ⚠️ **它说的是"上一次还没回来"，不是"这一次一定算数"**：菜单在途时**照常能开**，
/// 而那段里选中的年份会被 `ProfileViewModel.load` 的在途闸门挡掉（不排队是既有
/// 取舍，见那个方法的说明）—— 转圈只是把那段"点了没反应"的时间**先告诉你**。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。本件只画一行，背景由 `CardBox` 给。
public struct HeatmapHeader: View {

    /// 左边那个数（`1,024 次贡献`）。**`nil` = 这一年的数没拿到**（失败态）⇒ 那一侧不画。
    ///
    /// ⚠️ 不许填 `0 次贡献`：`0` 是"这一年确实没贡献"，`nil` 是"没拿到"
    /// （同 `ProfileStats` 那条"绝不把缺席填成 0"）。
    public let totalText: String?

    /// 切换器上显示的字（`2026 年`）。
    public let yearTitle: String

    /// 选项（顺序 = 菜单顺序）。
    public let yearOptions: [HeatmapYear]

    /// 当前选中的年份。
    public let selectedYear: Int

    /// 有一次取数在途（切年份 / 重试 / 下拉刷新）⇒ 年份标签左边画一个小转圈。
    ///
    /// ⚠️ **故意没有默认值**：给它 `= false` 的话，漏接的调用点会**静默**退化成
    /// "没有反馈"—— 那正是这一条要修的样子（用户看不出点上了没有）。宁可编译不过。
    public let isLoading: Bool

    /// 读屏标签（文案归领域层，见 `ProfileCopy.heatmapYearAccessibilityLabel(year:)`）。
    public let yearAccessibilityLabel: String

    /// 选了某一年。
    public let onSelectYear: (Int) -> Void

    public init(
        totalText: String?,
        yearTitle: String,
        yearOptions: [HeatmapYear],
        selectedYear: Int,
        isLoading: Bool,
        yearAccessibilityLabel: String,
        onSelectYear: @escaping (Int) -> Void
    ) {
        self.totalText = totalText
        self.yearTitle = yearTitle
        self.yearOptions = yearOptions
        self.selectedYear = selectedYear
        self.isLoading = isLoading
        self.yearAccessibilityLabel = yearAccessibilityLabel
        self.onSelectYear = onSelectYear
    }

    /// 在途指示器那一小块槽位的边长（pt）—— **恒定占位**（见类型抬头）。
    ///
    /// 12 ⇒ 那枚转圈缩到 caption（11pt）那一档文字旁边不会显得大一圈、也不会把这一行
    /// 顶高（对比 `chevron.down` 那条"图标字号写死"的处置，同一个理由）。
    ///
    /// ⚠️ 它是 `internal` 而非 `private`：`GitDuoDesignTests` 的渲染断言要拿它算
    /// "这一行的尺寸与是否在途无关"。
    static let loadingSlot: CGFloat = 12

    /// 那枚转圈的绘制缩放 —— 20pt 见方 ⇒ 12pt。
    ///
    /// ⚠️ 得用 `scaleEffect` 而不是 `.frame`：`.frame` 只改**布局建议**，而系统那枚不定
    /// 转圈在 iOS 上只有 medium / large 两档（最小 20pt 见方）⇒ 它会**溢出**那个框
    /// （框住的是 12pt、画出来还是 20pt，直接压到年份那两个字上）。`scaleEffect`
    /// 只改绘制、不动布局 ⇒ 尺寸由槽位说了算。
    static let loadingScale: CGFloat = 0.6

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            if let totalText {
                // 原型 `.t1`（15px/650）被内联改成 `font-size:14px` ⇒
                // 最近的一档是 `rowTitle`（`.subheadline` 15），权重取 `.semibold`（600 ≈ 650）。
                Text(totalText)
                    .font(Theme.Font.rowTitle.weight(.semibold))
                    .foregroundStyle(Theme.Palette.textPrimary)
            }

            Spacer(minLength: 0)

            yearMenu
        }
        // 原型 `style="margin-bottom:10px"`（10 不在 4pt 阶里 ⇒ 写原值）。
        // ⚠️ 这一行**永远**在（失败态也在），所以这 10pt 不用按状态分支。
        .padding(.bottom, 10)
    }

    private var yearMenu: some View {
        Menu {
            // ## ⚠️ 这里**不用 `Picker`**（2026-10-12 改，用户报回「下拉选择年份后不生效，
            //    没选上，需要点两次」，走查第 61 条）
            //
            // `Picker.selection` 是一条**受控**绑定 —— 它的契约是"`set` 之后回读**立刻**
            // 就能拿到新值"（选完就是选了，控件自己画勾、自己记住）。而这里的选中值来自
            // **取数结果**（`ProfileView` 传的是 `overview.year`，那条纪律写着"年份与总数
            // 必须来自同一份数据"）：切一年要发一次 GraphQL，`set` 只是把意图交出去，
            // **一个往返之内回读拿到的必然还是旧值** ⇒ `Picker` 判定"这次选择没生效"、
            // 把菜单项退回原样，表现就是"选不中 / 要点两次"。
            //
            // 原先的注释写着"用的不是它挑值的本事，而是它自带的视觉信号"—— 而它偏偏
            // **就挑了值**：受控组件不允许"值要等一会儿才变"。这是本条的根因。
            //
            // `Button` 是**命令式**的：点一下就是一次 action，它不问"值变了没有"。
            // 代价是那枚勾号要自己画（勾在左，与系统单选菜单同侧；
            // `"checkmark"` 是本包既有的写法，见 `SheetRow` 的用法）。
            ForEach(yearOptions) { option in
                Button {
                    onSelectYear(option.year)
                } label: {
                    // 当前那一年带勾。⚠️ 这里比较的是**取数结果里的年份**（`selectedYear`），
                    // 所以它在"点完 → 取数返回"这一段里仍指着旧的那一年 —— 这是有意的，
                    // 见类型抬头"选中之后不是立刻变成新值"那一节。
                    if option.year == selectedYear {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                // 在途那一小枚转圈 —— **恒占位**，所以它出现/消失时标题与箭头一动不动。
                loadingIndicator

                // 原型 `.t3`（11.5px / `--text3`）那一档 —— 与卡片上那句范围声明同一档。
                Text(yearTitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)

                // ⚠️ 图标字号写死（与全项目 50 处 `.system(size:)` 同一处置，偏差第 41 条）：
                //    它是个图标、不随「更大字体」缩放，而 `chevron.down` 在 caption 那一档
                //    会显得比文字大一圈、把这一行顶高。
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            // 整块（含那枚小箭头）都可点 —— 只让文字可点会让这一行"看着能点、点不中"。
            .contentShape(Rectangle())
        }
        .accessibilityLabel(yearAccessibilityLabel)
    }

    /// 在途那一小枚转圈 —— 位置与尺寸**恒定**（不在途时就是一块空槽）。
    ///
    /// ⚠️ 别写成"在途才嵌进那个 `HStack`"：这一行是右对齐的，那样标题会随转圈出现与
    /// 消失左右横跳 16pt（`loadingSlot` + `xs`）—— 比"没有反馈"更烦。外面这层
    /// `frame` 永远在，槽位里有什么由 `isLoading` 决定。
    private var loadingIndicator: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(Self.loadingScale)
                    // 与年份、箭头同一档灰（那两处都是 `textTertiary`）。
                    .tint(Theme.Palette.textTertiary)
                    // 只是视觉：`Menu` 自己挂着 `accessibilityLabel`，别让转圈再单独
                    // 被念一句"正在载入"（那会把这个控件的名字挤掉）。
                    .accessibilityHidden(true)
            }
        }
        .frame(width: Self.loadingSlot, height: Self.loadingSlot)
    }
}

/// 年份切换器里的一个选项。
///
/// ⚠️ 它只有**数字 + 文案**：设计包不认识 `ContributionYear`（依赖铁律），
/// 而切换器需要的恰恰就是这两样（`id` 用来对勾选、`title` 用来写菜单项）。
public struct HeatmapYear: Identifiable, Hashable, Sendable {

    /// 年份（同时也是菜单项的 `id` —— 用来对出哪一项是当前那一年）。
    public let year: Int

    /// 菜单里那一行字（`2026 年`）。
    public let title: String

    public var id: Int { year }

    public init(year: Int, title: String) {
        self.year = year
        self.title = title
    }
}

#Preview {
    // ⚠️ 这份 Preview **故意让点击同步生效**（`onSelectYear` 直接改 `selected`）：
    //    真实调用方做不到这一点（值要等一次取数），而这里没有取数 —— 于是
    //    "**点一下菜单项，勾与标题是否当场就换**"在 Xcode 里可以直接验。
    //    2026-10-12 那次缺陷（走查第 61 条，`Picker` 需要点两次）就是靠这一条
    //    才看得出来：真机上值要等一个往返、看不出是控件的毛病还是网络的毛病。
    //
    // ⚠️ **第一张与第三张要并排看**：第三张是"在途"（`isLoading: true`），
    //    它只该多出一枚小转圈 —— 年份那两个字与右侧箭头**一格都不许挪**
    //    （这就是槽位恒占位的意义；`GitDuoDesignTests` 里有一条渲染断言钉着它）。
    @Previewable @State var selected = 2026
    let years = [
        HeatmapYear(year: 2026, title: "2026 年"),
        HeatmapYear(year: 2025, title: "2025 年"),
        HeatmapYear(year: 2024, title: "2024 年"),
    ]

    return VStack(spacing: Theme.Spacing.m) {
        CardBox(vertical: 14) {
            HeatmapHeader(
                totalText: "1,024 次贡献",
                yearTitle: years.first { $0.year == selected }?.title ?? "",
                yearOptions: years,
                selectedYear: selected,
                isLoading: false,
                yearAccessibilityLabel: "切换年份，当前 \(selected) 年",
                onSelectYear: { selected = $0 }
            )
        }

        // 在途：只多一枚小转圈，标题与箭头不动（与上一张对照着看）。
        CardBox(vertical: 14) {
            HeatmapHeader(
                totalText: "1,024 次贡献",
                yearTitle: years.first { $0.year == selected }?.title ?? "",
                yearOptions: years,
                selectedYear: selected,
                isLoading: true,
                yearAccessibilityLabel: "切换年份，当前 \(selected) 年",
                onSelectYear: { selected = $0 }
            )
        }

        // 失败态：左边那个数**不画**（不是 `0 次贡献`），而切换器照常在。
        CardBox(vertical: 14) {
            HeatmapHeader(
                totalText: nil,
                yearTitle: years.first { $0.year == selected }?.title ?? "",
                yearOptions: years,
                selectedYear: selected,
                isLoading: false,
                yearAccessibilityLabel: "切换年份，当前 \(selected) 年",
                onSelectYear: { selected = $0 }
            )
        }

        // 失败态 + 在途：按了那一行「重试」之后的样子（这张卡最矮，转圈最容易被顶高，
        // 所以它也一起摆出来）。
        CardBox(vertical: 14) {
            HeatmapHeader(
                totalText: nil,
                yearTitle: years.first { $0.year == selected }?.title ?? "",
                yearOptions: years,
                selectedYear: selected,
                isLoading: true,
                yearAccessibilityLabel: "切换年份，当前 \(selected) 年",
                onSelectYear: { selected = $0 }
            )
        }
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
