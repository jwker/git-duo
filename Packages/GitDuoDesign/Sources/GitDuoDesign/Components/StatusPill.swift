import SwiftUI

/// 状态胶囊 —— 原型 `styles/03-components.css` 的 `.pill`（PRD §4.2 结果行、§4.15）。
///
/// ```css
/// .pill{display:inline-flex;align-items:center;gap:4px;font-size:11px;font-weight:600;
///       padding:2.5px 9px;border-radius:20px;border:1px solid}
/// .pill.open{color:var(--open);border-color:#a4d8b0;background:#f0fff4}
/// .pill.closed-i{color:var(--closed-i);border-color:#d1bcf5;background:#faf5ff}
/// .pill.closed-p{color:var(--closed-p);border-color:#f1b8bf;background:#fff1f2}
/// .pill.merged{color:var(--merge);border-color:#d1bcf5;background:#faf5ff}
/// ```
///
/// ## 三处颜色同时变，这是"状态"的全部表达
///
/// 前景 / 底 / 边**同族**取色（都来自 `Theme.Palette.state*` 那两组）。
/// 只换其中一处会得到一颗"看起来像渲染坏了"的胶囊 —— 例如红字配绿底。
///
/// ## ⚠️ 只有三族，不是四族
///
/// 原型有四个类名（`.open` / `.closed-i` / `.merged` / `.closed-p`），但**只有三种配色**：
/// `.closed-i`（已关闭的 Issue）与 `.merged` 的底 / 边 / 前景**逐字相同**（都是紫族）。
/// 所以 `Tone` 只有三档 —— 按**族**命名，不按单个状态命名，
/// 免得下一次"另一颗紫胶囊"又要冒出一个同值异名的档位（沿 `stateCompletedIcon` 的先例）。
///
/// ## 它不认识"已合并 / 已关闭"
///
/// 收 `title` 与 `tone`，不收 `PullRequestState`：设计包不依赖领域层。
/// "哪种状态配哪一档 tone"是调用方的事 —— 与 `FilterChip` 收 `isHighlighted`
/// 而不是 `ExploreFilters` 是同一条纪律。
///
/// ## 它是内容层
///
/// 胶囊嵌在列表行里，**实色，不加 Liquid Glass**（§10.2）。
public struct StatusPill: View {

    /// 三族配色 —— 与 `Theme.Palette` 里已经存在的 `stateOpen` / `stateMerged` /
    /// `stateClosed` 三族前景色**一一对应**（为免两套词汇各自漂移，名字直接沿用）。
    public enum Tone: Sendable, Hashable, CaseIterable {

        /// 绿族：进行中 / 正向。原型 `.pill.open`。
        case open

        /// 紫族：已完成那一族。原型 `.pill.merged`**与** `.pill.closed-i`。
        ///
        /// ⚠️ 它不只管"已合并"—— 原型里凡是**紫族**的状态都用它：
        /// 已合并的 PR、已关闭的 Issue、已发布的版本、已批准的评审、以及仓库的「私有」标记。
        case merged

        /// 红族：已终止 / 否定。原型 `.pill.closed-p`（已关闭**且未合并**的 PR）。
        case closed
    }

    public let title: String
    public let tone: Tone

    public init(title: String, tone: Tone) {
        self.title = title
        self.tone = tone
    }

    public var body: some View {
        Text(title)
            .font(Theme.Font.tag)
            .foregroundStyle(Self.foreground(tone))
            // 2.5 / 9 是原型原值（`padding:2.5px 9px`）—— 4pt 间距阶里没有这两档，
            // 故写原值并注明出处（沿 `SegmentedBar` 的 7 / 14 同一做法）。
            .padding(.vertical, 2.5)
            .padding(.horizontal, 9)
            // 原型 `border-radius:20px` 在 11pt 的文字上就是胶囊的两端半圆。
            .background(Capsule().fill(Self.surface(tone)))
            .overlay(Capsule().stroke(Self.border(tone), lineWidth: 1))
            // 读屏把整颗胶囊念成一句；不带这一句，读屏会只念出"Open"而没有上下文。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
    }

    // MARK: - Tone → 三处配色（纯函数，可单测）

    // 三个都标 `nonisolated`：它们不碰 UI 状态，而 `View` 的成员默认继承主 actor 隔离。
    // 不标的话，任何非隔离上下文（例如领域层的映射测试）调它们都会被挡下。

    /// 前景色。复用 `state*` 那三个 —— **不新开一套同值的 token**。
    public nonisolated static func foreground(_ tone: Tone) -> Color {
        switch tone {
        case .open: Theme.Palette.stateOpen
        case .merged: Theme.Palette.stateMerged
        case .closed: Theme.Palette.stateClosed
        }
    }

    /// 底色。
    public nonisolated static func surface(_ tone: Tone) -> Color {
        switch tone {
        case .open: Theme.Palette.stateOpenSurface
        case .merged: Theme.Palette.stateMergedSurface
        case .closed: Theme.Palette.stateClosedSurface
        }
    }

    /// 边框色。
    public nonisolated static func border(_ tone: Tone) -> Color {
        switch tone {
        case .open: Theme.Palette.stateOpenBorder
        case .merged: Theme.Palette.stateMergedBorder
        case .closed: Theme.Palette.stateClosedBorder
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
        // 搜索「Issue · PR」结果行上的三档（PRD §4.2）。
        HStack(spacing: Theme.Spacing.s) {
            StatusPill(title: "Open", tone: .open)
            StatusPill(title: "Merged", tone: .merged)
            StatusPill(title: "Closed", tone: .closed)
        }
        // 同属紫族的另外两处（原型都走 `.pill.closed-i` / `.pill.merged` 的配色）。
        HStack(spacing: Theme.Spacing.s) {
            StatusPill(title: "私有", tone: .merged)
            StatusPill(title: "当前", tone: .open)
        }
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
