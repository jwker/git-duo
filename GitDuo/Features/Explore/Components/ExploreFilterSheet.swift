import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 探索页的筛选弹层内容（PRD §5.4、TECH_SPEC §8.4）。
///
/// ## 它是一个**内容视图**，不是一个 `isPresented` 开关
///
/// `TECH_SPEC §8.4` 要求弹层由调用方以 `.sheet(item:)` 呈现，**用 `Identifiable` 的路由枚举
/// 驱动**，避免多个 `isPresented` 布尔量互相打架。所以这里只画内容，
/// 由 `ExploreView` 拿一个 `ExploreSheet` 决定什么时候呈现哪一张。
///
/// ## ⚠️ 底部提示照抄 PRD，尽管它在日期那份上读着别扭
///
/// 原型 `scripts/09-explore.js` 的 `openFilterSheet` 里，提示文案**不分维度**：
///
/// ```js
/// const hint = cur ? '再次点击已选语言可取消，取消后显示全部' : '不选则显示全部';
/// ```
///
/// 于是「日期范围」那张弹层也会说"已选**语言**"。PRD §5.4 逐字照抄了这句。
/// **这里也照抄** —— 理由是 `AGENTS.md §1`：原型是文案的最终裁决者，改文案要 grep 全仓并同步文档；
/// 顺手"改通顺"会让实现与文档立刻不一致，而评审者只能看到两份东西打架。
/// （已作为候选文案修订上报，等拍板后三处一起改。）
struct ExploreFilterSheet: View {

    let kind: ExploreFilterKind

    /// 当前选中的值（`nil` = 未选 ⇒ 显示全部）。
    let selected: String?

    /// 点某一项。**取消语义不在这个视图里** —— "再点当前项 = 取消"是
    /// `ExploreFilters.select(_:)` 的规则（领域层，已单测），这里只把点击报上去。
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private var options: [String] {
        switch kind {
        case .range: ExploreDateRange.allCases.map(\.title)
        case .language: ExploreFilters.languageOptions
        }
    }

    /// PRD §5.4 的两句提示（逐字，含上面说明的那处不一致）。
    private var hint: String {
        selected == nil ? "不选则显示全部" : "再次点击已选语言可取消，取消后显示全部"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(kind.title)
                .font(Theme.Font.sectionLabel)
                .tracking(0.4)
                .foregroundStyle(Theme.Palette.textTertiary)
                .textCase(.uppercase)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, 6)

            // ⚠️ 选项里**没有「全部」那一行** —— 取消靠"再点一次当前项"（PRD §5.4、harness 断言过）。
            //    加一行"全部"会多出一种取消方式，而两种方式里必然有一种先被写错。
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                row(option)
            }

            Text(hint)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.top, 6)
                .padding(.bottom, Theme.Spacing.xxs)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface)
    }

    private func row(_ option: String) -> some View {
        Button {
            onPick(option)
            dismiss()
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Text(option)
                    .font(Theme.Font.rowTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)

                Spacer(minLength: 0)

                // ✓ 用强调绿（原型 `color:var(--green)`）—— `accentStrong` 就是那个值。
                if selected == option {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.Palette.accentStrong)
                }
            }
            .padding(.vertical, Theme.Spacing.m)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == option ? [.isSelected] : [])
    }
}

#Preview {
    ExploreFilterSheet(kind: .range, selected: "本周") { _ in }
}
