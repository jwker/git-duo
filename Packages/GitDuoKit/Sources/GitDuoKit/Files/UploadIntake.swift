import Foundation
import UniformTypeIdentifiers

/// 一次上传的**取件与预处理**（`PRD §5.8` 的两个上传出口、决策 #71）。
///
/// ## 它只做一件事：决定"这份字节能不能交给写通道"
///
/// 写通道（`SaveFile`）只认 ≤1MB 的字节，而两个系统选择器交过来的东西**可能很大**。
/// 三个出口在选中那一刻都要经过这里，结果只有两种：**能用**（可能被压过）或**太大**。
///
/// ## ⚠️ 为什么"≤1MB 就不压缩"这条要写在这里、而且要先判
///
/// 决策 #70③ 说"相册图片取原始字节、不重编码"，决策 #71 把那条收窄成**默认**：
/// ≤1MB 仍然原样。这条不是修辞 —— 它是"用户上传的就是这张图片"这句承诺在
/// **多数情况下仍然成立**的保证。
///
/// 判据必须写在这里（而不是交给压缩器）：压缩器的契约里确实有"≤ target 时原样返回"，
/// 但**依赖它**就等于把这句承诺挂在另一个类型上 —— 哪天有人给压缩器加一个
/// "即使很小也顺手优化一下"的档，用户的原图就会在没有任何人察觉的情况下被重编码。
/// `UploadIntakeTests` 有一条断言钉住"≤1MB 时压缩器**一次都没被调用**"。
///
/// ## ⚠️ 它**不**判文件名
///
/// 路径的空 / 非法由 `RepoPath.resolveNewFile` 判（`RepoDetailViewModel.upload` 那一步），
/// 本类型只管字节。两件事合成一处会让"名字不对"与"太大"给出同一句话。
public struct UploadIntake: Sendable {

    /// 压缩器（接缝 —— 测试里塞桩件）。
    public let compressor: any ImageCompressing

    /// 写通道的上限；压缩的目标也是它（**同一个数**：`SaveFile.maxContentBytes`）。
    public let targetBytes: Int

    public init(
        compressor: any ImageCompressing,
        targetBytes: Int = SaveFile.maxContentBytes
    ) {
        self.compressor = compressor
        self.targetBytes = targetBytes
    }

    /// 扩展名**像不像图片** —— 只用于「要不要先把它读进内存」这一步的**预检**。
    ///
    /// ## ⚠️ 它不是判据，别拿它做判断
    ///
    /// 它服务的唯一场景是「文件 App」那一支：一个 100MB 的 zip 不该为了"待会儿会被拒绝"
    /// 而先进内存一趟（`AddFileSheet.readImported` 的先看大小）。而**真判据**在
    /// `ImageCompressing` 那一侧 —— ImageIO 从**字节本身**读出来的类型，紧接着就会跑。
    ///
    /// ⚠️ 扩展名可以是错的（改过名的、没有扩展名的）。两种错法之间取**宁可多读**那一边：
    /// 把一个没扩展名的 PNG 读进来只是浪费一次内存，而反过来"该压的没压"会让用户
    /// 看到一句没头没尾的"请到 GitHub 网页端处理"，他根本不知道那张图其实压得动。
    public static func mightBeImage(pathExtension: String) -> Bool {
        guard let type = UTType(filenameExtension: pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// 判这份字节能不能用；太大时先试着压。
    ///
    /// ⚠️ 它是 `async` 且**不带任何 actor 标注**：按 SE-0338，nonisolated 的 async 函数
    /// 不继承调用方的 actor ⇒ 从 View 里 `await` 它，压缩这段 CPU 活不在主线程上跑。
    public func prepare(_ data: Data, fileName: String) async -> UploadOutcome {
        // ① ≤ 上限 ⇒ **原样**，一次都不编码（`PRD §5.8` 那张表的第一档）。
        if data.count <= targetBytes {
            return .accepted(data: data, compression: nil)
        }

        // ② 超了 ⇒ 交给压缩器。`nil` 有三档：不是图片 / 动图（压了只剩第一帧）/ 压不动。
        guard let compressed = await compressor.compress(data, targetBytes: targetBytes) else {
            return .tooLarge
        }

        // ⚠️ **再判一次**。压缩器的契约是"不超过 target"，但**契约是要有人守的**：
        //    一个返回了仍然超限字节的实现（桩件写错、或将来加了新档忘了判），
        //    照单全收的后果是用户在提交弹层里填完信息、按下提交，才收到服务端 422 ——
        //    错误出现在离原因最远的地方。这里判一次，"它到底能不能写"就有唯一答案。
        guard compressed.count <= targetBytes else { return .tooLarge }

        return .accepted(
            data: compressed,
            compression: UploadCompression(originalBytes: data.count, finalBytes: compressed.count)
        )
    }
}

/// `UploadIntake.prepare(_:fileName:)` 的两种结局。
///
/// ⚠️ 只有两种，且**第二种没有关联值** —— 那一档的文案是
/// `CommitSheetCopy.tooLargeHint` 那一句（唯一落点），三种原因（不是图片 / 动图 / 压不动）
/// **给的是同一句话**：用户能做的动作是同一个（去网页端），而"为什么没压成"对他没有第二个用处。
/// 分成三种会让三处调用点各写一次 `switch`，而它们必然只覆盖其中两种。
public enum UploadOutcome: Sendable, Equatable {

    /// 可以用 —— `compression == nil` 表示**原样**（没压过）。
    case accepted(data: Data, compression: UploadCompression?)

    /// 超限且没能压下来 ⇒ 调用方给"引导网页端"那句提示。
    case tooLarge
}

/// "压过了"这件事的两个数（`PRD §5.8` / 决策 #71⑤：**要印给用户看**）。
///
/// ⚠️ 它携带的是**字节数**而不是算好的那句话：文案属于 `CommitSheetCopy`
///（同 `FileSaveReceipt` 与 `CommitSheetCopy.toast` 的分工）。
public struct UploadCompression: Sendable, Equatable {

    /// 选中那一刻的原始字节数。
    public let originalBytes: Int

    /// 压完、真正要写上去的字节数。
    public let finalBytes: Int

    public init(originalBytes: Int, finalBytes: Int) {
        self.originalBytes = originalBytes
        self.finalBytes = finalBytes
    }
}
