import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 「我的 Star」列表的骨架（TECH_SPEC §8.5）。
///
/// ## ⚠️ 2026-10-16 起它**不再自己画灰条**（NATIVE-MIGRATION P1）
///
/// 同 `RepoCardSkeleton`：渲染**真实的 `StarRow`** + `.redacted(reason: .placeholder)`，
/// 而不是照着它抄一份几何。理由与收益写在那边 —— 关键是"骨架与真实行失配"
/// 这件事从此在结构上不可能发生。
///
/// ⚠️ `StarRow.onOpen` 传空闭包：占位行**不可点**（整片还加了 `allowsHitTesting(false)`），
/// 而"点一下什么都不发生"比"点不动"更难解释。
struct StarRowSkeleton: View {

    /// 占位的行数。默认 4 行 —— 首屏大约一屏多一点，够铺出"还有更多"的样子。
    var rows: Int = 4

    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<rows, id: \.self) { _ in
                StarRow(
                    repository: .placeholder,
                    state: .placeholder(fullName: Repository.placeholder.fullName),
                    onOpen: {}
                )
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}

#Preview {
    StarRowSkeleton()
        .padding(Theme.Spacing.page)
        .background(Theme.Palette.background)
}
