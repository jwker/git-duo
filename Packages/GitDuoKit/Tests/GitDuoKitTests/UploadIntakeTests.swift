import Foundation
import GitDuoCore
import Testing

@testable import GitDuoKit

/// 上传取件与预处理（**决策 #71** / `PRD §5.8` 的两个上传出口）。
///
/// ## 这一套测的是**策略**，不是压缩算法
///
/// 真压得下来压不下来，取决于 ImageIO 的实际输出 —— 那部分在
/// `GitDuoCoreTests.ImageCompressorTests` 里（真的编一张图、再读回来验证）。
/// 这里全部用**桩件**，因为本类型的三条行为里有两条**根本造不出来**：
///
/// 1. **"≤1MB 时压缩器一次都没被调用"** —— 真的拿一张小图去调，压缩器会走它自己
///    那句"≤ target 就原样返回"，测试**照样绿**，而 `UploadIntake` 里那条判据
///    删掉也照样绿。要断言"没被调用"，只能数调用次数。
/// 2. **"压完仍然超限"** —— 真实的压缩器不会这么干（它自己会判），
///    但契约是要有人守的（`UploadIntake.prepare` 里那句"再判一次"）；
///    只有桩件能造出这个**不合约的压缩器**。
///
/// ## ⚠️ 桩件是 actor，不是类
///
/// 与 `URLProtocol` 那批桩件同一个坑的反面：`ImageCompressing: Sendable`，
/// 而这个方法**真的是 `async`**（协议就这么要求的，为的是让压缩跑在主线程外）。
/// 用 `final class` + 一把锁也能过编译，但那就把一个"本来就异步"的接缝
/// 写成了"加锁假装异步"。actor 是这里的正确默认。
@Suite("上传取件 · ≤1MB 原样 / 压过带摘要 / 压不动拒绝（决策 #71）")
struct UploadIntakeTests {

    // MARK: - 桩件

    /// 记下每一次调用、并返回事先说好的结果。
    private actor CompressorStub: ImageCompressing {

        private(set) var calls: [Int] = []

        /// 返回什么（`nil` = 压不动）。
        private let reply: Data?

        init(replying reply: Data?) {
            self.reply = reply
        }

        func compress(_ data: Data, targetBytes: Int) async -> Data? {
            calls.append(targetBytes)
            return reply
        }
    }

    private let small = Data(repeating: 0x41, count: 10)

    // MARK: - ① 本来就够小：原样放行，**一次都不编码**

    @Test("⚠️ ≤ 上限时压缩器**一次都没被调用**（这条判据不能被交给压缩器）")
    func smallInputNeverTouchesTheCompressor() async {
        // 桩件故意返回一段**不一样**的字节：如果 `UploadIntake` 把判据交给它，
        // 用户拿到的就不是他选的那份了 —— 而"用户上传的就是这张图片"这句承诺
        //（决策 #70③）会在没有任何人察觉的情况下被打破。
        let stub = CompressorStub(replying: Data(repeating: 0x42, count: 5))
        let intake = UploadIntake(compressor: stub, targetBytes: 1_000)

        let outcome = await intake.prepare(small, fileName: "a.png")

        #expect(outcome == .accepted(data: small, compression: nil))
        // ⚠️ `await` **必须先取出来**再进 `#expect`：它是 autoclosure，
        //    直接写 `#expect(await stub.calls.isEmpty)` 会得到
        //    "async call in an autoclosure that does not support concurrency"。
        let calls = await stub.calls
        #expect(calls.isEmpty, "没超限就不该走压缩 —— 它连被调用都不该被调用")
    }

    @Test("⚠️ 边界是**闭区间**：正好等于上限算「够小」（同一个数，不该有两种判法）")
    func exactlyAtTargetIsAccepted() async {
        let stub = CompressorStub(replying: nil)
        let intake = UploadIntake(compressor: stub, targetBytes: small.count)

        let outcome = await intake.prepare(small, fileName: "a.png")

        #expect(outcome == .accepted(data: small, compression: nil))
        // ⚠️ 这里与 `SaveFile` 那条写通道的判据必须是**同一侧**（`<=`）：
        //    否则会出现"取件说太大、写通道说能写"这种自相矛盾的中间态。
        let calls = await stub.calls
        #expect(calls.isEmpty)
    }

    // MARK: - ② 超了、压得下来：带上摘要

    @Test("⚠️ 压成功时摘要的两个数是**真的**（原始 / 最终），不是算出来的")
    func compressedOutcomeCarriesReceipt() async {
        let compressed = Data(repeating: 0x43, count: 40)
        let stub = CompressorStub(replying: compressed)
        let intake = UploadIntake(compressor: stub, targetBytes: 100)
        let big = Data(repeating: 0x41, count: 5_000)

        let outcome = await intake.prepare(big, fileName: "photo.jpg")

        #expect(outcome == .accepted(
            data: compressed,
            compression: UploadCompression(originalBytes: 5_000, finalBytes: 40)
        ))
        // 压缩目标必须**就是**写通道的上限：两个数若不同源，
        // "取件说能写、写通道说太大"会在服务端 422 那一刻才暴露出来。
        let calls = await stub.calls
        #expect(calls == [100])
    }

    @Test("⚠️ 交给压缩器的 `targetBytes` 就是 `targetBytes`（不是别的数）")
    func compressorReceivesTheSameTarget() async {
        let stub = CompressorStub(replying: Data(repeating: 0x43, count: 1))
        let intake = UploadIntake(compressor: stub, targetBytes: 7)
        _ = await intake.prepare(Data(repeating: 0x41, count: 5_000), fileName: "a.png")
        let calls = await stub.calls
        #expect(calls == [7])
    }

    // MARK: - ③ 压不动 / 不合约：一律 .tooLarge

    @Test("压不动（桩件回 nil）⇒ `.tooLarge`，由调用方给「引导网页端」那一句")
    func refusedCompressionFallsBackToTooLarge() async {
        // 三档原因（不是图片 / 动图 / 阶梯走完仍超限）在 `UploadIntake` 这一层
        // **不必区分** —— 用户能做的动作是同一个，所以三条都长这样。
        let stub = CompressorStub(replying: nil)
        let intake = UploadIntake(compressor: stub, targetBytes: 100)

        let outcome = await intake.prepare(Data(repeating: 0x41, count: 5_000), fileName: "a.bin")

        #expect(outcome == .tooLarge)
        let calls = await stub.calls
        #expect(calls.count == 1, "压不动也要真的试过一次")
    }

    @Test("⚠️ 压缩器**不合约**（返回的仍然超限）也拦得住 —— 不能照单全收")
    func overSizedReplyIsStillRejected() async {
        // 真实的 `ImageCompressor` 不会这么干，但这道判据防的是**将来**：
        // 一个新增的档位忘了判、或某个平台的 ImageIO 行为和预期不同。
        // 放行的后果是用户在提交弹层里填完信息、按下提交，才收到服务端 422 ——
        // 错误出现在离原因最远的地方。
        let stub = CompressorStub(replying: Data(repeating: 0x43, count: 101))
        let intake = UploadIntake(compressor: stub, targetBytes: 100)

        let outcome = await intake.prepare(Data(repeating: 0x41, count: 5_000), fileName: "a.png")

        #expect(outcome == .tooLarge)
    }

    // MARK: - ④ `targetBytes` 的默认值

    @Test("默认目标 = `SaveFile.maxContentBytes`（一处常量，两处用）")
    func defaultTargetIsTheWriteLimit() {
        let intake = UploadIntake(compressor: CompressorStub(replying: nil))
        #expect(intake.targetBytes == SaveFile.maxContentBytes)
    }

    // MARK: - ⑤ 预检（只按扩展名猜，宁可多读）

    @Test("`mightBeImage`：常见图片扩展名认得出，其余不认")
    func mightBeImageByExtension() {
        for ext in ["png", "jpg", "jpeg", "heic", "HEIC", "gif", "webp", "tiff", "bmp"] {
            #expect(UploadIntake.mightBeImage(pathExtension: ext), "\(ext) 应当算图片")
        }
        for ext in ["zip", "pdf", "swift", "txt", "md", "", "unknown-ext"] {
            #expect(!UploadIntake.mightBeImage(pathExtension: ext), "\(ext) 不该算图片")
        }
    }

    // MARK: - ⑥ 接缝清点

    @Test("⚠️ 接缝：`GitDuoCore.ImageCompressor` 还在、签名仍然逐字对得上")
    func imageSeam() {
        // 与 `RepoEndpointsContractTests` 同一个理由：`extension ImageCompressor: ImageCompressing {}`
        // 的**扩展体是空的**，删掉它编译照样过、其余测试照样绿，
        // 一直到组合根真正装配时才炸（错误信息还指向 `AppEnvironment`）。
        // 这一行把"某天有人顺手删掉那个空扩展体"从**静默**变成**当场红**。
        let _: any ImageCompressing = ImageCompressor()
    }
}
