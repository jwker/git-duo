import SwiftUI

/// 对话头部 —— 原型 `styles/04-screens.css` 第 30–31 行的 `.conv-head`（PRD §4.9 / §4.11 页首）。
///
/// ```css
/// /* 2026-10-15 方案 D 起（走查第 73 条）—— 头部去卡形：名字与状态直接排版在页面上 */
/// .conv-head{background:var(--card);border:none;border-radius:18px;padding:14px;margin-bottom:10px}
/// .conv-head h2{font-size:17.5px;font-weight:720;line-height:1.35;margin:8px 0}
/// ```
///
/// 三行，从轻到重再到轻：
///
/// ```text
/// 〔● Open〕 该 Issue 仍然开放        ← 状态胶囊 + 一句说明（.t3）
/// 真机上 session.start() 返回 false…  ← 标题（h2）
/// #42 · my-git/gitduo · 由 reviewer-a 创建于 2 小时前  ← 元信息（.t3）
/// ```
///
/// ## 它的形状就是 `CardBox`，所以直接用它
///
/// `.conv-head` 与 `.card` 在方案 A 下**同为白卡**（都不画边框，圆角 18），
/// 只有内边距不同（`.card` 是 13、这里是 12 —— 原型两个值）。
/// 所以这里用 `CardBox()` 而不是再写一遍 ——
/// 抄一遍的代价不是多几行，而是"将来调条目形态时只改到一处"。
///
/// ## 五段文字全部由调用方给
///
/// 本组件**一个中文字都不产生**：状态胶囊的文案（`Open` / `已关闭`）、
/// 说明句、标题、元信息都是从领域层 `IssueCopy` / `PullCopy` 来的可测数据
/// （`IssueDetail.headNote(now:)` / `metaLabel(fullName:now:)` …）。
/// 这正是"文案 / 权限 / 产品承诺要提为可测领域数据"那条纪律——
/// 曾经出过"文案承诺撤销授权、实现却做不到"，原因就是那句话散在一个 `Text("…")` 里。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）；形状由 `CardBox` 收口。
public struct ConversationHeader: View {

    /// 状态胶囊的文案（`Open` / `Closed` / `Merged`）。
    public let stateTitle: String

    /// 状态胶囊的配色族（**.merged 那一族同时管"已关闭的 Issue"** —— 见 `StatusPill.Tone`）。
    public let stateTone: StatusPill.Tone

    /// 胶囊右边那句说明（`该 Issue 仍然开放` / `已由 dev-k 请求合并到 main`）。
    public let note: String

    /// 标题。
    public let title: String

    /// 元信息行（`#42 · my-git/gitduo · 由 reviewer-a 创建于 2 小时前`）。
    public let meta: String

    public init(
        stateTitle: String,
        stateTone: StatusPill.Tone,
        note: String,
        title: String,
        meta: String
    ) {
        self.stateTitle = stateTitle
        self.stateTone = stateTone
        self.note = note
        self.title = title
        self.meta = meta
    }

    public var body: some View {
        // 原型 `.conv-head{padding:14px}` ⇒ `CardBox` 的默认内边距（方案 A 与 `.card` 同值）。
        CardBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Theme.Spacing.m) {
                    StatusPill(title: stateTitle, tone: stateTone)

                    Text(note)
                        // 原型 `.t3{font-size:11.5px}` ⇒ `Font.caption`（`.caption2` 11）。
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                        // 说明句在窄屏上要能折行，而不是被胶囊挤成一串省略号。
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(title)
                    // 原型 `.conv-head h2{font-size:17.5px;font-weight:720}`。
                    .font(Theme.Font.conversationTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    // 原型 `margin:8px 0`。
                    .padding(.vertical, Theme.Spacing.s)

                Text(meta)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 三行都靠左、整块吃满卡片宽度（原型是块级流）。
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 读屏按"状态 → 标题 → 元信息"的顺序念，而不是把三行糊成一句。
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.l) {
        // §4.9 Issue 详情 · 开放
        ConversationHeader(
            stateTitle: "Open",
            stateTone: .open,
            note: "该 Issue 仍然开放",
            title: "真机上 session.start() 返回 false 后状态没有回退",
            meta: "#42 · my-git/gitduo · 由 reviewer-a 创建于 2 小时前"
        )
        // §4.9 Issue 详情 · 已关闭（⚠️ 紫族，与"已合并"共用一档）
        ConversationHeader(
            stateTitle: "Closed",
            stateTone: .merged,
            note: "已于 3 天前关闭",
            title: "README 里的相对链接点了没反应",
            meta: "#31 · my-git/gitduo · 由 dev-k 创建于 2 周前"
        )
        // §4.11 PR 详情 · 已合并（红族是"已关闭且未合并"那一档）
        ConversationHeader(
            stateTitle: "Merged",
            stateTone: .merged,
            note: "已由 dev-k 合并进 main",
            title: "仓库详情升级为四分区枢纽",
            meta: "#57 · feature/repo-hub → main · 更新于 2 小时前"
        )
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
