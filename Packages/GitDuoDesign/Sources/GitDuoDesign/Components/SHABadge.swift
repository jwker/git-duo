import SwiftUI

/// **短哈希徽章** —— 提交的短 SHA（原型 `styles/04-screens.css` 的 `.sha`）。
///
/// ```css
/// .sha{font-family:Menlo,monospace;font-size:11.5px;color:var(--link);
///      background:#ddf4ff;padding:2px 7px;border-radius:6px;flex-shrink:0}
/// ```
///
/// ## 为什么值得单独一件
///
/// 现在有**两处**画它：提交列表行（§4.4 分区四）与提交详情页的头部（§4.7）。
/// 原型里它们本就是同一个类（`.sha`），而"同一个东西抄两遍"的代价在这一处
/// 有具体形态 —— 底色 `#ddf4ff`、字号 11.5、内边距 `2px 7px` 三个值里
/// 任何一个抄错，两页上的徽章就会**长得不一样**，而两页单看都对。
///
/// ## 判据 #43：它进设计包
///
/// 只收一个 `String`（`sha`），不认识 `CommitSummary` / `CommitDetail`
/// —— 那些是领域模型，归各 Feature。这与 `DiffRow` 只收 `number` / `text` / `tone`
/// 是同一条判据。
///
/// ## ⚠️ 它**不设** `accessibilityLabel`
///
/// 该念什么由调用方给（`CommitCopy.shaAccessibilityLabel(shortSHA:)`）——
/// 那是**文案**，而文案在领域层（App target 没有测试 target，
/// 散在视图里的句子没有任何东西钉得住）。
///
/// ## 它是内容层
///
/// **实色，不加 Liquid Glass**（§10.2）。
public struct SHABadge: View {

    public let sha: String

    public init(sha: String) {
        self.sha = sha
    }

    public var body: some View {
        Text(sha)
            // 原型用 Menlo ⇒ `monospacedPreview`（`.caption2` 等宽）就是这一档。
            .font(Theme.Font.monospacedPreview)
            .foregroundStyle(Theme.Palette.accent)
            // 原型 `padding:2px 7px`。
            .padding(.vertical, 2)
            .padding(.horizontal, 7)
            .background(
                // 原型 `border-radius:6px` ⇒ `Radius.chip`。
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Theme.Palette.accentSubtle)
            )
            // 原型 `flex-shrink:0`：徽章是定宽的东西，不许被文件名压扁
            // （压扁后 SHA 会变成 `a1b2…`，而"短 SHA"本来就是拿来对照的七位）。
            .fixedSize(horizontal: true, vertical: false)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.m) {
        SHABadge(sha: "a1b2c3d")
            .accessibilityLabel("提交 a1b2c3d")
    }
    .padding(Theme.Spacing.page)
    .background(Theme.Palette.background)
}
