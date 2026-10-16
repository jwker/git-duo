import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 「我的 Star」列表的骨架（TECH_SPEC §8.5）。
///
/// ## ⚠️ 2026-10-16 起它是**行**，不是一个 `VStack`（NATIVE-MIGRATION P3）
///
/// 同 `RepoCardSkeleton`：一行就是一个 `List` 行，本件只负责把 N 行吐出去，
/// 行间距与卡面由 `List` 给（`body` 因此从 `VStack` 变成 `ForEach`）。
///
/// ## ⚠️ 2026-10-16（P1）它不再自己画灰条
///
/// 渲染**真实的 `StarRow`** + `.redacted(reason: .placeholder)`，而不是照着它抄一份几何。
/// 理由与收益写在 `RepoCardSkeleton` 那边 —— 关键是"骨架与真实行失配"
/// 这件事从此在结构上不可能发生。
///
/// ⚠️ P3 起 `StarRow` 对外不再有 `onOpen`（整行由 `List` 包进 `NavigationLink`），
/// 这条占位行**不可点**由 `.allowsHitTesting(false)` 单独保证。
struct StarRowSkeleton: View {

    /// 占位的行数。默认 4 行 —— 首屏大约一屏多一点，够铺出"还有更多"的样子。
    var rows: Int = 4

    var body: some View {
        ForEach(0..<rows, id: \.self) { _ in
            StarRow(
                repository: .placeholder,
                state: .placeholder(fullName: Repository.placeholder.fullName)
            )
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}

#Preview {
    List {
        StarRowSkeleton()
    }
}
