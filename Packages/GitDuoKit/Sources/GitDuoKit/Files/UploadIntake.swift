import Foundation
import GitDuoCore
import UniformTypeIdentifiers

/// 一次上传的**取件与预处理**（`PRD §5.8` 的两个上传出口，决策 #71 压缩 / #72 转码）。
///
/// ## 它做三件事，顺序固定
///
/// 1. **交给预处理**（`ImageProcessing`）—— 那一步同时管"体积"（#71）与"格式"（#72）；
/// 2. **再判一次大小**（见下：契约是要有人守的）；
/// 3. **给出最终要写上去的三样东西** —— 字节 · **文件名**（扩展名可能被换掉）· "动过什么"的摘要。
///
/// ## ⚠️ 为什么"要不要动"这条判据**不在这一层**
///
/// 决策 #70③ 说"相册图片取原始字节、不重编码"，#71 / #72 把它连着收窄了两次，
/// 现在剩下的那一档是：**≤1MB 且格式在网页端显示得出来**。
///
/// 判据必须在**看得见字节类型**的那一层（= `ImageProcessing` 的实现里）——
/// 而这一层手里只有文件名，扩展名可以是错的。曾经这里有一句"`data.count <= targetBytes`
/// 就原样放行"的短路：#72 一来它就成了 bug（≤1MB 的 HEIC 会**绕过**转码）。
/// ⇒ 记一条判据：**短路条件要写在"信息最全"的那一层**，否则每加一条治理都会漏一次。
///
/// ## ⚠️ 为什么文件名在这一层定（而不是让调用方自己换）
///
/// "换成哪个扩展名"是预处理的**结论**（它才知道输出是什么格式）。两个调用点
///（相册 / 文件 App）各换一次 = 同一个规则写两遍，而它们必然分叉。
/// 这一层拿到结论，一处换好，两条通道共用。
///
/// ## ⚠️ 它**不**判路径合不合法
///
/// 空 / 非法由 `RepoPath.resolveNewFile` 判（`RepoDetailViewModel.upload` 那一步），
/// 本类型只管字节与扩展名。两件事合成一处会让"名字不对"与"太大"给出同一句话。
public struct UploadIntake: Sendable {

    /// 图片预处理（接缝 —— 测试里塞桩件）。
    public let processor: any ImageProcessing

    /// 写通道的上限；压缩的目标也是它（**同一个数**：`SaveFile.maxContentBytes`）。
    public let targetBytes: Int

    public init(
        processor: any ImageProcessing,
        targetBytes: Int = SaveFile.maxContentBytes
    ) {
        self.processor = processor
        self.targetBytes = targetBytes
    }

    /// 扩展名**像不像图片** —— 只用于「要不要先把它读进内存」这一步的**预检**。
    ///
    /// ## ⚠️ 它不是判据，别拿它做判断
    ///
    /// 它服务的唯一场景是「文件 App」那一支：一个 100MB 的 zip 不该为了"待会儿会被拒绝"
    /// 而先进内存一趟（`AddFileSheet.readImported` 的先看大小）。而**真判据**在
    /// `ImageProcessing` 那一侧 —— ImageIO 从**字节本身**读出来的类型，紧接着就会跑。
    ///
    /// ⚠️ 扩展名可以是错的（改过名的、没有扩展名的）。两种错法之间取**宁可多读**那一边：
    /// 把一个没扩展名的 PNG 读进来只是浪费一次内存，而反过来"该转的没转"会让用户
    /// 拿到一个网页端显示不出来的文件（#72），或者看到一句没头没尾的"请到 GitHub 网页端处理"。
    ///
    /// ⚠️ 它**认不出**的图片格式会走到"先拒绝"那一边（例：把 HEIC 改名成 `.bin`
    /// 且超过 1MB ⇒ 当场提示引导网页端）。这是上面那条取舍的**另一半代价**，已登记 ——
    /// 要根治得先读一段文件头再判，而那是另一个量级的事。
    public static func mightBeImage(pathExtension: String) -> Bool {
        guard let type = UTType(filenameExtension: pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// 判这份字节能不能用；要动的话（压缩 / 转码）先动完，再给出最终的文件名。
    ///
    /// ⚠️ 它是 `async` 且**不带任何 actor 标注**：按 SE-0338，nonisolated 的 async 函数
    /// 不继承调用方的 actor ⇒ 从 View 里 `await` 它，压缩 / 转码这段 CPU 活不在主线程上跑。
    public func prepare(_ data: Data, fileName: String) async -> UploadOutcome {
        // ⚠️ `nil` 有好几档：不是图片 / 动图（压了只剩第一帧）/ 阶梯走完仍超限。
        //    它们在**这一层不必区分** —— 用户能做的动作是同一个（去网页端）。
        guard let result = await processor.process(data, targetBytes: targetBytes) else {
            return .tooLarge
        }

        // ⚠️ **先判大小**（而不是先看"原样"那一格）。压缩器的契约是"不超过 target"，
        //    但**契约是要有人守的**：一个返回了仍然超限字节的实现（桩件写错、或将来加了
        //    新档忘了判），照单全收的后果是用户在提交弹层里填完信息、按下提交，
        //    才收到服务端 422 —— 错误出现在离原因最远的地方。
        guard result.data.count <= targetBytes else { return .tooLarge }

        // 一个字节都没动 ⇒ 没有摘要、文件名也不用换（`PRD §5.8` 那张表的第一档）。
        guard !result.isUntouched else {
            return .accepted(fileName: fileName, data: result.data, adjustment: nil)
        }

        // ⚠️ 摘要里的"新格式"只在**真的换了格式**时给：一张 >1MB 的 PNG 压完还是 PNG，
        //    那时候说"已转为 PNG"就是假话（`CommitSheetCopy.adjustmentNotice` 分三种说法）。
        let newFormat = result.didChangeFormat ? result.outputFormat : nil
        return .accepted(
            fileName: newFormat.map {
                UploadFileName.replacingExtension(of: fileName, with: $0.fileExtension)
            } ?? fileName,
            data: result.data,
            adjustment: UploadAdjustment(
                originalBytes: data.count,
                finalBytes: result.data.count,
                newFormat: newFormat
            )
        )
    }
}

/// `UploadIntake.prepare(_:fileName:)` 的两种结局。
///
/// ⚠️ 只有两种，且**第二种没有关联值** —— 那一档的文案是
/// `CommitSheetCopy.tooLargeHint` 那一句（唯一落点），几种原因（不是图片 / 动图 / 处理不动）
/// **给的是同一句话**：用户能做的动作是同一个（去网页端），而"为什么没成"对他没有第二个用处。
/// 分成几种会让几处调用点各写一次 `switch`，而它们必然只覆盖其中两种。
public enum UploadOutcome: Sendable, Equatable {

    /// 可以用 —— `adjustment == nil` 表示**原样**（没压过也没转过）。
    ///
    /// ⚠️ `fileName` 由本类型给出（**可能已经换过扩展名**，决策 #72④）——
    /// 调用方**不要**再自己用原来那个名字，否则会写出"内容转了、名字没转"的文件，
    /// 而那正好是"白转"（GitHub 按扩展名渲染）。
    case accepted(fileName: String, data: Data, adjustment: UploadAdjustment?)

    /// 处理不动 ⇒ 调用方给"引导网页端"那句提示。
    case tooLarge
}

/// "我们动了用户选中的东西"这件事的**摘要**（`PRD §5.9①` / 决策 #71⑤ · #72⑤：
/// **要印给用户看**）。
///
/// ## ⚠️ 它为什么要同时带"字节数"与"新格式"
///
/// 因为发生的可能是**两件不同的事**：
/// - **压小了**（体积变了）—— 决策 #71；
/// - **换了格式**（内容能显示了）—— 决策 #72，⚠️ **体积还可能反而变大**。
///
/// 只带一个数就没法区分"已压缩 1.2MB → 1.4MB"（假话）与"已转为 JPEG"（实话）。
///
/// ⚠️ 它携带的是**事实**而不是算好的那句话：文案属于 `CommitSheetCopy`
///（同 `FileSaveReceipt` 与 `CommitSheetCopy.toast` 的分工）。
public struct UploadAdjustment: Sendable, Equatable {

    /// 选中那一刻的原始字节数。
    public let originalBytes: Int

    /// 真正要写上去的字节数。
    public let finalBytes: Int

    /// **转成的新格式**；`nil` = 只是压小了、格式没变（决策 #72：只在这一档给）。
    ///
    /// ⚠️ 它与"输出格式"不是一回事：一张 >1MB 的 PNG 压完还是 PNG（输出格式是 `.png`），
    /// 但**格式没变** ⇒ 这一格是 `nil`（文件名也不用换）。
    public let newFormat: ImageOutputFormat?

    public init(originalBytes: Int, finalBytes: Int, newFormat: ImageOutputFormat?) {
        self.originalBytes = originalBytes
        self.finalBytes = finalBytes
        self.newFormat = newFormat
    }

    /// 体积变小了吗。
    ///
    /// ⚠️ 拿它挑文案的那一句（"已压缩" vs "已转为"）—— **转过之后变大的情况是真实存在的**，
    /// 那时说"已压缩"就是假话（`PRD §5.9①` 那张三行的表）。
    public var didShrink: Bool { finalBytes < originalBytes }
}
