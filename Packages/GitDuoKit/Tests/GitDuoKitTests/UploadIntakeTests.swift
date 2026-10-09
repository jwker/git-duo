import Foundation
import GitDuoCore
import Testing

@testable import GitDuoKit

/// 上传取件与预处理（**决策 #71 压缩 / #72 转码**、`PRD §5.8` 的两个上传出口）。
///
/// ## 这一套测的是**策略**，不是压缩算法
///
/// 真压得下来 / 转得对不对，取决于 ImageIO 的实际输出 —— 那部分在
/// `GitDuoCoreTests.ImageProcessorTests` 里（真的编一张图、再读回来验证）。
/// 这里全部用**桩件**，因为这一层有两条行为**根本造不出来**：
///
/// 1. **"原样"与"动过了"这两档** —— 真的拿一张小图去调，预处理会走它自己那句
///    "原样返回"，测试**照样绿**；而"动过了"要真造一张超限的大图，慢且脆。
/// 2. **"处理后仍然超限"** —— 真实的实现不会这么干（它自己会判），
///    但契约是要有人守的（`UploadIntake.prepare` 里那句"再判一次"）；
///    只有桩件能造出这个**不合约**的实现。
///
/// ## ⚠️ 两条在 #72 之后**变了样**的判据
///
/// - **这一层不再按大小短路**。曾经这里有一句"≤1MB 就原样放行"，而 #72 让
///   **≤1MB 的 HEIC 也必须要转** ⇒ 那句话会把它整个绕过。
///   现在"要不要动"只在 `ImageProcessing` 的实现里判一次（它才看得见字节的类型）。
///   `processorIsAlwaysConsulted` 把这一点钉住。
/// - **文件名由这一层产出**（扩展名可能被换掉）。两个调用点各换一次必然分叉，
///   所以改名规则收在这里，`transcodeRewritesTheExtension` 钉住它。
///
/// ## ⚠️ 桩件是 actor，不是类
///
/// 与 `URLProtocol` 那批桩件同一个坑的反面：`ImageProcessing: Sendable`，
/// 而这个方法**真的是 `async`**（协议就这么要求的，为的是让压缩 / 转码跑在主线程外）。
/// 用 `final class` + 一把锁也能过编译，但那就把一个"本来就异步"的接缝
/// 写成了"加锁假装异步"。actor 是这里的正确默认。
@Suite("上传取件 · 原样 / 压缩 / 转码改名 / 处理不动拒绝（决策 #71 · #72）")
struct UploadIntakeTests {

    // MARK: - 桩件

    /// 记下每一次调用的目标值、并返回事先说好的结果。
    private actor ProcessorStub: ImageProcessing {

        private(set) var calls: [Int] = []

        /// 返回什么（`nil` = 处理不动）。
        private let reply: ImageProcessingResult?

        init(replying reply: ImageProcessingResult?) {
            self.reply = reply
        }

        func process(_ data: Data, targetBytes: Int) async -> ImageProcessingResult? {
            calls.append(targetBytes)
            return reply
        }
    }

    /// 三个构造子，名字直接说明那一档的语义（比在测试里手写 `ImageProcessingResult`
    /// 更不容易把 `didChangeFormat` 写反）。
    private func untouched(_ data: Data) -> ImageProcessingResult {
        ImageProcessingResult(data: data, outputFormat: nil, didChangeFormat: false)
    }

    private func recompressed(_ data: Data, as format: ImageOutputFormat) -> ImageProcessingResult {
        ImageProcessingResult(data: data, outputFormat: format, didChangeFormat: false)
    }

    private func transcoded(_ data: Data, as format: ImageOutputFormat) -> ImageProcessingResult {
        ImageProcessingResult(data: data, outputFormat: format, didChangeFormat: true)
    }

    private let small = Data(repeating: 0x41, count: 10)

    // MARK: - ① 原样：没有摘要、文件名不动

    @Test("原样放行 ⇒ `adjustment == nil`（那两句 caption 一句都不该出现）")
    func untouchedOutcomeHasNoAdjustment() async {
        let stub = ProcessorStub(replying: untouched(small))
        let intake = UploadIntake(processor: stub, targetBytes: 1_000)

        let outcome = await intake.prepare(small, fileName: "a.png")

        #expect(outcome == .accepted(fileName: "a.png", data: small, adjustment: nil))
        // ⚠️ `await` **必须先取出来**再进 `#expect`：它是 autoclosure，
        //    直接写 `#expect(await stub.calls.isEmpty)` 会得到
        //    "async call in an autoclosure that does not support concurrency"。
        let calls = await stub.calls
        #expect(calls == [1_000], "这一层交给预处理的**目标**就是写通道的上限")
    }

    @Test("⚠️ **≤1MB 也照样交给预处理**（决策 #72③ —— 这一层不许按大小短路）")
    func processorIsAlwaysConsulted() async {
        // ⚠️ 这一条钉的是一个**删掉之后所有测试都还绿**的判据：#72 之后
        //    "要不要转"只有看得见字节类型的那一层判得出（≤1MB 的 HEIC 必须转），
        //    所以在这一层写 `if data.count <= targetBytes { 直接放行 }`
        //    会让那类文件**绕过转码**，而用户在网页端看到的仍是一块破图。
        //    输入故意**远小于**上限：那条短路一旦加回来，下面这个调用就不会发生。
        let stub = ProcessorStub(replying: untouched(small))
        let intake = UploadIntake(processor: stub, targetBytes: 1_000_000)

        _ = await intake.prepare(small, fileName: "a.heic")

        let calls = await stub.calls
        #expect(calls.count == 1, "没超限也必须问一次 —— 判据不在这里")
    }

    // MARK: - ② 压小了、格式没变：文件名不动，摘要有两个真数

    @Test("⚠️ 压成功时摘要的两个数是**真的**（原始 / 最终），而且文件名不动")
    func compressedOutcomeCarriesReceipt() async {
        let compressed = Data(repeating: 0x43, count: 40)
        let stub = ProcessorStub(replying: recompressed(compressed, as: .jpeg))
        let intake = UploadIntake(processor: stub, targetBytes: 100)
        let big = Data(repeating: 0x41, count: 5_000)

        let outcome = await intake.prepare(big, fileName: "photo.jpg")

        #expect(outcome == .accepted(
            fileName: "photo.jpg",
            data: compressed,
            adjustment: UploadAdjustment(originalBytes: 5_000, finalBytes: 40, newFormat: nil)
        ))
        // 压缩目标必须**就是**写通道的上限：两个数若不同源，
        // "取件说能写、写通道说太大"会在服务端 422 那一刻才暴露出来。
        let calls = await stub.calls
        #expect(calls == [100])
    }

    @Test("⚠️ 交给预处理的 `targetBytes` 就是 `targetBytes`（不是别的数）")
    func processorReceivesTheSameTarget() async {
        let stub = ProcessorStub(replying: untouched(small))
        let intake = UploadIntake(processor: stub, targetBytes: 7)
        _ = await intake.prepare(Data(repeating: 0x41, count: 5_000), fileName: "a.png")
        let calls = await stub.calls
        #expect(calls == [7])
    }

    // MARK: - ③ 转码：文件名扩展名必须跟着换（决策 #72④）

    @Test("⚠️ 转码 ⇒ **文件名扩展名跟着换**，摘要里带上新格式")
    func transcodeRewritesTheExtension() async {
        // ⚠️ HEIC 进、JPEG 出：不换扩展名的话 GitHub 仍按 `.HEIC` 渲染 ⇒ **这次转换白做**。
        //    而"换成什么"是预处理的结论（它才知道输出格式），所以改名必须在这里做。
        let output = Data(repeating: 0x43, count: 40)
        let stub = ProcessorStub(replying: transcoded(output, as: .jpeg))
        let intake = UploadIntake(processor: stub, targetBytes: 100)

        let outcome = await intake.prepare(Data(repeating: 0x41, count: 5_000), fileName: "IMG_1234.HEIC")

        #expect(outcome == .accepted(
            fileName: "IMG_1234.jpg",
            data: output,
            adjustment: UploadAdjustment(originalBytes: 5_000, finalBytes: 40, newFormat: .jpeg)
        ))
    }

    @Test("⚠️ 转成 PNG 那一档：无损源（TIFF / BMP）走这条，扩展名换成 `png`")
    func transcodeToPNG() async {
        let output = Data(repeating: 0x43, count: 40)
        let stub = ProcessorStub(replying: transcoded(output, as: .png))
        let intake = UploadIntake(processor: stub, targetBytes: 100)

        let outcome = await intake.prepare(Data(repeating: 0x41, count: 5_000), fileName: "shot.tiff")

        #expect(outcome == .accepted(
            fileName: "shot.png",
            data: output,
            adjustment: UploadAdjustment(originalBytes: 5_000, finalBytes: 40, newFormat: .png)
        ))
    }

    @Test("⚠️ **转完之后体积反而变大**是真实存在的一档 —— 摘要照样要给（文案分三种）")
    func transcodeThatGrowsStillCarriesReceipt() async {
        // ⚠️ HEIC 转 PNG 会把体积涨上去。这一档如果连摘要都不给，用户就完全
        //    看不到"东西被换过"；而如果摘要只带字节数，`CommitSheetCopy` 只能印出
        //    `已压缩 1.2MB → 1.4MB` 这种**说反话**的句子（决策 #72⑤）。
        let output = Data(repeating: 0x43, count: 1_400_000)
        let stub = ProcessorStub(replying: transcoded(output, as: .png))
        let intake = UploadIntake(processor: stub, targetBytes: 2_000_000)
        let input = Data(repeating: 0x41, count: 1_200_000)

        guard case let .accepted(fileName, data, adjustment?) = await intake.prepare(input, fileName: "a.heic")
        else {
            Issue.record("转码成功应当给出摘要")
            return
        }
        #expect(fileName == "a.png")
        #expect(data == output)
        #expect(adjustment.newFormat == .png)
        #expect(adjustment.finalBytes > adjustment.originalBytes)
        #expect(!adjustment.didShrink, "没变小 ⇒ 文案**不许**说「已压缩」")
    }

    // MARK: - ④ 处理不动 / 不合约：一律 .tooLarge

    @Test("处理不动（桩件回 nil）⇒ `.tooLarge`，由调用方给「引导网页端」那一句")
    func refusedProcessingFallsBackToTooLarge() async {
        // 几档原因（不是图片 / 动图 / 阶梯走完仍超限）在 `UploadIntake` 这一层
        // **不必区分** —— 用户能做的动作是同一个，所以几条都长这样。
        let stub = ProcessorStub(replying: nil)
        let intake = UploadIntake(processor: stub, targetBytes: 100)

        let outcome = await intake.prepare(Data(repeating: 0x41, count: 5_000), fileName: "a.bin")

        #expect(outcome == .tooLarge)
        let calls = await stub.calls
        #expect(calls.count == 1, "处理不动也要真的试过一次")
    }

    @Test("⚠️ 预处理**不合约**（返回的仍然超限）也拦得住 —— 不能照单全收")
    func overSizedReplyIsStillRejected() async {
        // 真实的实现不会这么干，但这道判据防的是**将来**：
        // 一个新增的档位忘了判、或某个平台的 ImageIO 行为和预期不同。
        // 放行的后果是用户在提交弹层里填完信息、按下提交，才收到服务端 422 ——
        // 错误出现在离原因最远的地方。
        let stub = ProcessorStub(replying: untouched(Data(repeating: 0x43, count: 101)))
        let intake = UploadIntake(processor: stub, targetBytes: 100)

        let outcome = await intake.prepare(Data(repeating: 0x41, count: 5_000), fileName: "a.png")

        #expect(outcome == .tooLarge)
    }

    @Test("⚠️ 大小这一判要**先于**「原样」那一档（顺序反了这条就漏过去）")
    func sizeCheckRunsBeforeTheUntouchedShortcut() async {
        // ⚠️ 桩件回的是"**原样**、但字节数是 101 > 目标 100" —— 一个自相矛盾的结果。
        //    如果实现先看 `isUntouched` 再判大小，这个 101 字节会**直接放行**，
        //    而它在服务端会 422。顺序是这条判据的全部内容。
        let stub = ProcessorStub(replying: untouched(Data(repeating: 0x43, count: 101)))
        let intake = UploadIntake(processor: stub, targetBytes: 100)

        let outcome = await intake.prepare(Data(repeating: 0x41, count: 101), fileName: "a.png")

        #expect(outcome == .tooLarge)
    }

    // MARK: - ⑤ `targetBytes` 的默认值

    @Test("默认目标 = `SaveFile.maxContentBytes`（一处常量，两处用）")
    func defaultTargetIsTheWriteLimit() {
        let intake = UploadIntake(processor: ProcessorStub(replying: nil))
        #expect(intake.targetBytes == SaveFile.maxContentBytes)
    }

    // MARK: - ⑥ 预检（只按扩展名猜，宁可多读）

    @Test("`mightBeImage`：常见图片扩展名认得出，其余不认")
    func mightBeImageByExtension() {
        for ext in ["png", "jpg", "jpeg", "heic", "HEIC", "gif", "webp", "tiff", "bmp"] {
            #expect(UploadIntake.mightBeImage(pathExtension: ext), "\(ext) 应当算图片")
        }
        for ext in ["zip", "pdf", "swift", "txt", "md", "", "unknown-ext"] {
            #expect(!UploadIntake.mightBeImage(pathExtension: ext), "\(ext) 不该算图片")
        }
    }

    // MARK: - ⑦ 接缝清点

    @Test("⚠️ 接缝：`GitDuoCore.ImageProcessor` 还在、签名仍然逐字对得上")
    func imageSeam() {
        // 与 `RepoEndpointsContractTests` 同一个理由：`extension ImageProcessor: ImageProcessing {}`
        // 的**扩展体是空的**，删掉它编译照样过、其余测试照样绿，
        // 一直到组合根真正装配时才炸（错误信息还指向 `AppEnvironment`）。
        // 这一行把"某天有人顺手删掉那个空扩展体"从**静默**变成**当场红**。
        let _: any ImageProcessing = ImageProcessor()
    }
}
