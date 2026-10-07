import Foundation
import Testing

@testable import GitDuoCore

/// 相对时间文案（原型 `'刚刚'` / `'昨天'` / `'2 天前'` / `'30 分钟前'`）。
///
/// 这些词是**契约**：harness 直接断言访问后最近访问行显示 `刚刚`（`harness.js:95`），
/// 改词等于改需求。
@Suite("RelativeTime · 分档文案")
struct RelativeTimeTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func label(secondsAgo: TimeInterval) -> String {
        RelativeTime.string(from: now.addingTimeInterval(-secondsAgo), now: now)
    }

    @Test("一分钟以内是「刚刚」—— harness 断言的原词，不许改")
    func justNow() {
        #expect(label(secondsAgo: 0) == "刚刚")
        #expect(label(secondsAgo: 1) == "刚刚")
        #expect(label(secondsAgo: 59) == "刚刚")
    }

    @Test("**未来时刻也归入「刚刚」** —— 设备时钟回拨时不显示负数")
    func futureIsJustNow() {
        // 数据来自另一台快了 5 分钟的设备时，`-5 分钟前` 只会让人怀疑 App 坏了。
        #expect(label(secondsAgo: -300) == "刚刚")
        #expect(!label(secondsAgo: -300).contains("-"))
    }

    @Test("分钟档：60 秒起跳到「1 分钟前」，59 分 59 秒仍是分钟")
    func minutesBucket() {
        #expect(label(secondsAgo: 60) == "1 分钟前")
        #expect(label(secondsAgo: 3_599) == "59 分钟前")
    }

    @Test("小时档：3600 秒起跳到「1 小时前」，23 小时 59 分仍是小时")
    func hoursBucket() {
        #expect(label(secondsAgo: 3_600) == "1 小时前")
        #expect(label(secondsAgo: 86_399) == "23 小时前")
    }

    @Test("「昨天」只覆盖 24–48 小时这一档")
    func yesterdayBucket() {
        #expect(label(secondsAgo: 86_400) == "昨天")
        #expect(label(secondsAgo: 172_799) == "昨天")
        #expect(label(secondsAgo: 172_800) == "2 天前")
    }

    @Test("天档：从 2 天起往上累加")
    func daysBucket() {
        #expect(label(secondsAgo: 259_200) == "3 天前")
        #expect(label(secondsAgo: 604_800) == "7 天前")
    }

    @Test("每个档位都产出可读文案 —— 不会漏出裸数字或空串")
    func everyLabelIsReadable() {
        // 注意「昨天」不含「前」：它靠的是"日历感"而不是时长后缀。
        // （第一版这条断言漏了「昨天」，25 小时那档直接把自己判失败 —— 是实现对了、测试写错了。）
        let samples: [TimeInterval] = [0, 120, 7_200, 90_000, 300_000]

        for seconds in samples {
            let text = label(secondsAgo: seconds)
            let hasUnit = text.contains("前") || text == "刚刚" || text == "昨天"
            #expect(!text.isEmpty)
            #expect(hasUnit, "\(seconds) 秒这一档产出了裸文案：\(text)")
        }
    }
}
