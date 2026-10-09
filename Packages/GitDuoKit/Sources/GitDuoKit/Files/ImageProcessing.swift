import Foundation
import GitDuoCore

/// 图片预处理在**领域层与本地基础设施之间的接缝**（决策 #71 压缩 / #72 转码、`PRD §5.8`）。
///
/// ## 为什么要有这层协议（而不是直接 `import GitDuoCore` 调）
///
/// 与 `RepoEndpoints` 同一个理由：**把"这个用例到底依赖哪个动作"从类型上看得见**，
/// 且测试不必真的跑一遍 ImageIO。
///
/// `UploadIntake` 需要的能力只有一件 —— "把这段字节处理成能写上去的样子"。
/// 有了这条协议，那几档行为（原样不编码 / 压或转成功 / 处理不动）都能用一个
/// 记下调用参数的桩件测出来；直接调具体类型的话，测试就得**真的**造一张大图，
/// 而"该原样放行的有没有被白编码一遍"这类性质**根本断言不了**。
///
/// ## 协议在 `GitDuoKit`、被扩展的类型在 `GitDuoCore`
///
/// 同 `RepoDetailDataSource` 那一批的做法（先例见 `RepoEndpoints.swift` 的类型说明）：
/// 协议是我们自己声明的，不存在追溯适配（retroactive conformance）的冲突风险。
///
/// ⚠️ 结果类型 `ImageProcessingResult` **必须住在 `GitDuoCore`**（不能是本包的）——
/// 依赖方向是 `GitDuoKit → GitDuoCore` 单向的，`GitDuoCore` 不能说 `GitDuoKit` 的名字。
///
/// ⚠️ 扩展体是**空的**，条件是 `GitDuoCore.ImageProcessor` 的方法签名**逐字一致**
/// （含参数标签）—— 任何一处改了，这里会**编译不过**。那正是我们想要的。
/// ⚠️ 但"空扩展体被整条删掉"编译是不会有反应的 ⇒ 专门有一条测试把它**当作协议用一次**
/// （`UploadIntakeTests.imageSeam`），同 `RepoEndpointsContractTests` 的处置。
public protocol ImageProcessing: Sendable {

    /// 把 `data` 处理到 `targetBytes` 以内、且格式在网页端显示得出来。
    ///
    /// - Returns: 结果（字节 + 输出格式 + 格式变没变）；**`nil` = 处理不动**
    ///   （不是图片 / 动图 / 阶梯走完仍超限）。
    ///
    /// ⚠️ **≤ `targetBytes` 且格式已经显示得出来时原样返回**（`isUntouched`）——
    /// 但 `UploadIntake` **不会**依赖这一点：它自己还要再判一次大小（见那里的说明）。
    func process(_ data: Data, targetBytes: Int) async -> ImageProcessingResult?
}

extension ImageProcessor: ImageProcessing {}
