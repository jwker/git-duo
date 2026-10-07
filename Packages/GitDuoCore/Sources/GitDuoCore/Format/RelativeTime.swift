import Foundation

/// 相对时间文案 —— 首页「最近访问」与探索「活跃榜」共用。
///
/// 依据：原型 `scripts/01-data.js` 的近期时间串（`'昨天'` / `'2 天前'` / `'3 天前'`）、
/// `TRENDING[].upd`（`'30 分钟前'` / `'2 小时前'`），以及 harness 断言
/// 「访问后最近访问行显示 `刚刚`」（`harness.js:95`）。
///
/// **为什么单独成类型、而不是在 View 里就地算**：它是**文案契约**——
/// `刚刚` 这个词是 harness 守着的（原型侧断言的原文），不能随手改成「刚刚访问」或「现在」。
/// 放进 `GitDuoCore` 是为了让它能被单测钉住（App target 没有测试 target）。
///
/// ⚠️ **口径：按「经过时长」分档，不按自然日**。
/// 23 小时前可能落在昨天、也可能落在今天凌晨，若按自然日切档，同一时刻在两个时区会得到
/// 不同文案（服务器时区 / 设备时区 / 用户改过系统时间），而"访问于何时"对用户来说是个
/// 模糊印象，不值得引入这种不确定性。分档规则见 `string(from:now:)`。
public enum RelativeTime {

    /// 把时刻转成相对文案。`now` 显式传入（不内部取 `Date()`）—— 否则无法单测。
    ///
    /// 分档：
    /// | 距今 | 文案 |
    /// |---|---|
    /// | < 1 分钟（含**未来时刻**） | `刚刚` |
    /// | < 1 小时 | `{n} 分钟前` |
    /// | < 24 小时 | `{n} 小时前` |
    /// | < 48 小时 | `昨天` |
    /// | 其余 | `{n} 天前` |
    ///
    /// 「未来时刻」归入 `刚刚` 而不是显示负数：设备时钟回拨、或数据来自另一台设备时，
    /// `-3 分钟前` 只会让人怀疑 App 坏了。
    public static func string(from date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)

        // 未来（或同一瞬间）⇒ 刚刚
        guard seconds >= 60 else { return "刚刚" }

        if seconds < 3_600 {
            return "\(Int(seconds / 60)) 分钟前"
        }
        if seconds < 86_400 {
            return "\(Int(seconds / 3_600)) 小时前"
        }
        if seconds < 172_800 {
            return "昨天"
        }
        return "\(Int(seconds / 86_400)) 天前"
    }
}
