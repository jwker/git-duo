import SwiftUI
import GitDuoDesign
import GitDuoKit

/// 探索榜列表的骨架（TECH_SPEC §8.5）。
///
/// ## ⚠️ 2026-10-16 起它是**行**，不是一个 `VStack`（NATIVE-MIGRATION P3）
///
/// 同 `RepoCardSkeleton`：一行就是一个 `List` 行，本件只负责把 N 行吐出去，
/// 行间距与卡面由 `List` 给（`body` 因此从 `VStack` 变成 `ForEach`）。
///
/// ## ⚠️ 2026-10-16（P1）它不再自己画灰条
///
/// 渲染**真实的 `TrendCard`** + `.redacted(reason: .placeholder)`（那个自绘件已删）。
/// 理由与收益写在 `RepoCardSkeleton` 那边 —— 关键是"骨架与真实卡片失配"
/// 这件事从此在结构上不可能发生。
///
/// ⚠️ 角标数组给**一条**（真实行在"还没取到 Star 基线"时也是一条，见 `TrendCard` 的说明）
/// ⇒ 占位块的宽度与那种情形一致。
struct ExploreBoardSkeleton: View {

    /// 占位几张卡。一屏大约放得下 4 张。
    var count: Int = 4

    var body: some View {
        ForEach(0..<count, id: \.self) { _ in
            TrendCard(summary: .placeholder, badges: [.init("占位占位")])
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}

#Preview {
    List {
        ExploreBoardSkeleton()
    }
}
