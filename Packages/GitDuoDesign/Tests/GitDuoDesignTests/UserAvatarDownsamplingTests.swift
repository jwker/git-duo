import Foundation
import Testing

@testable import GitDuoDesign

/// `UserAvatar` 的**按显示尺寸降采样** —— `TECH_SPEC §5.3` 那条欠账的落地（2026-10-11）。
///
/// 欠账原文（文档 2026-10-09 亲口核实的："三处头像消费点**一处都还没做**"）：
/// 「头像按展示尺寸降采样后再入缓存（避免为 32pt 圆头像缓存 460px 原图）；
/// GitHub 头像 URL 支持 `?s=<size>` 参数，直接请求所需尺寸。」
///
/// 落地点刻意**只有一处**（本类型内部的 `downsampled`）：三处带 `avatarURL` 的调用点
/// （「我的」页 86pt / 提交行 28pt / 贡献者堆叠 34pt）**全都经过 `UserAvatar`**
/// ⇒ 不必三处各改一遍，也不会出现"同一个头像在两处走两种 URL"
/// （`ProfileMapper.avatarURL(from:)` 当初拒绝在领域层补尺寸，担心的正是后者）。
///
/// 同 `Slice4`–`Slice9` 的纪律：**不测长相**（那要靠逐屏对照），只钉算法与四条边界。
///
/// ⚠️ 本套件**不标 `@MainActor`**：被测的两个函数都是 `nonisolated static` 纯函数
/// （同 `UserAvatar.initial(for:)` / `colorIndex(for:)` 那两条既有断言），
/// 与主 actor 无关 —— 标上只是照抄邻座的样子。
@Suite("UserAvatar · 按显示尺寸降采样")
struct UserAvatarDownsamplingTests {

    // MARK: - 像素边长

    @Test("⚠️ 三处真实直径在 @3x 下的像素数")
    func pixelSizesForTheThreeRealCallSites() {
        // 这三个直径就是三个调用点各自的真值（改任一处，这条会跟着变）。
        #expect(UserAvatar.pixelSize(for: 86, scale: 3) == 258)  // 「我的」页大头像
        #expect(UserAvatar.pixelSize(for: 34, scale: 3) == 102)  // 贡献者堆叠
        #expect(UserAvatar.pixelSize(for: 28, scale: 3) == 84)   // 提交行作者
    }

    @Test("小数乘积**向上**取整")
    func roundsUp() {
        #expect(UserAvatar.pixelSize(for: 31, scale: 3.5) == 109)  // 108.5 ⇒ 109
        #expect(UserAvatar.pixelSize(for: 10, scale: 2) == 20)     // 整数乘积不被多加 1
    }

    @Test("scale ≤ 0 时按 1 倍算 —— 不产生 `?s=0`")
    func clampsScale() {
        // `?s=0` 会让端点返回一张 0 边的图；而 scale 为 0 只可能来自
        // 一个还没接上环境的渲染上下文 —— 那时候宁可按 1 倍算。
        #expect(UserAvatar.pixelSize(for: 34, scale: 0) == 34)
        #expect(UserAvatar.pixelSize(for: 34, scale: -3) == 34)
    }

    // MARK: - URL 改写

    @Test("裸地址 ⇒ 追一个 `?s=`")
    func appendsSizeToBareURL() {
        let url = URL(string: "https://avatars.githubusercontent.com/u/1")!
        #expect(
            UserAvatar.downsampled(url, pixels: 102).absoluteString
                == "https://avatars.githubusercontent.com/u/1?s=102"
        )
    }

    @Test("⚠️ 已有的 `s` 被**覆盖**，其余 query 原样保留")
    func overwritesExistingSizeKeepsOtherQuery() {
        // `v=4` 参与 CDN 的缓存键 —— 丢了它会拿到旧头像。
        let url = URL(string: "https://avatars.githubusercontent.com/u/1?v=4&s=460")!
        let out = UserAvatar.downsampled(url, pixels: 84).absoluteString
        #expect(out.contains("v=4"), "其余 query 不得被吃掉")
        #expect(out.contains("s=84"))
        #expect(!out.contains("s=460"), "旧的 s 必须被覆盖，不是并存")
    }

    @Test("⚠️ 非 `githubusercontent.com` 子域 ⇒ 原样返回")
    func leavesOtherHostsAlone() {
        for raw in [
            "https://example.com/a.png?v=4",
            // ⚠️ 形似但不是子域：判据若写成裸串 `hasSuffix("githubusercontent.com")`，
            //    这一条会被误判成 GitHub 头像，进而被塞进一个没人认的参数。
            "https://evil-githubusercontent.com/u/1",
        ] {
            let url = URL(string: raw)!
            #expect(UserAvatar.downsampled(url, pixels: 102) == url, "\(raw) 不该被改写")
        }
    }
}
