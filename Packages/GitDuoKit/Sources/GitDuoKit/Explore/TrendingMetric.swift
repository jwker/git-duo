import Foundation
import GitDuoCore

/// 趋势卡片的三个指标文案（原型 `scripts/09-explore.js` 的 `trendRows()`）。
///
/// 三处都是**可见契约**，所以放在领域层而不是 View 里 —— harness 直接断言
/// `新星榜行含「创建」`（`harness.js:358`）与 `活跃榜行含「推送」`（`harness.js:355`）。
///
/// 原型的对应代码：
/// ```js
/// // 新星榜
/// `<span class="chip">🆕 ${t.created.slice(5)} 创建</span>`
/// // 活跃榜
/// `<span class="chip">⚡ ${t.upd}推送</span>`
/// ```
public enum TrendingMetric {

    /// 新星榜：创建日角标 —— `🆕 08-05 创建`。
    ///
    /// 用 **`MM-DD`**（原型 `t.created.slice(5)` 取的就是 `YYYY-MM-DD` 的后 5 位）：
    /// 新星榜只看近 90 天，年份是冗余信息，省下来的宽度留给仓库名。
    /// 按 **UTC** 取日 —— 与限定符 `created:>=YYYY-MM-DD` 同一套时区，否则
    /// "限定符说 8 月 5 日之后、卡片却显示 08-04" 会自相矛盾。
    public static func createdLabel(createdAt: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.gmt
        let parts = calendar.dateComponents([.month, .day], from: createdAt)
        return String(format: "🆕 %02d-%02d 创建", parts.month ?? 1, parts.day ?? 1)
    }

    /// 活跃榜：最近推送角标 —— `⚡ 30 分钟前推送`。
    ///
    /// ⚠️ 与原型**有意不同**：原型写的是 `⚡ ${t.upd}推送`（`t.upd` 是 `'30 分钟前'`，
    /// 拼出来是"30 分钟前推送"）。保留相同的拼法，只是把 `upd` 换成现算的 `RelativeTime` ——
    /// 原型把相对时间**存成了字符串**，那会让"30 分钟前"永远停在"30 分钟前"。
    public static func lastPushLabel(pushedAt: Date, now: Date) -> String {
        "⚡ \(RelativeTime.string(from: pushedAt, now: now))推送"
    }
}
