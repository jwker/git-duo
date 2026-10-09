import Foundation
import GitDuoCore

/// 图片压缩在**领域层与本地基础设施之间的接缝**（决策 #71、`PRD §5.8`）。
///
/// ## 为什么要有这层协议（而不是直接 `import GitDuoCore` 调）
///
/// 与 `RepoEndpoints` 同一个理由：**把"这个用例到底依赖哪个动作"从类型上看得见**，
/// 且测试不必真的跑一遍 ImageIO。
///
/// `UploadIntake` 需要的能力只有一件 —— "把这段字节压到 N 以内"。
/// 有了这条协议，那三档行为（≤1MB 原样不编码 / 压成功 / 压不动）都能用一个
/// 记下调用次数的桩件测出来；直接调静态方法的话，测试就得**真的**造一张大图，
/// 而"≤1MB 时一次都不该编码"这条**根本断言不了**（它要的是"没被调用"）。
///
/// ## 协议在 `GitDuoKit`、被扩展的类型在 `GitDuoCore`
///
/// 同 `RepoDetailDataSource` 那一批的做法（先例见 `RepoEndpoints.swift` 的类型说明）：
/// 协议是我们自己声明的，不存在追溯适配（retroactive conformance）的冲突风险。
///
/// ⚠️ 扩展体是**空的**，条件是 `GitDuoCore.ImageCompressor` 的方法签名**逐字一致**
/// （含参数标签）—— 任何一处改了，这里会**编译不过**。那正是我们想要的。
/// ⚠️ 但"空扩展体被整条删掉"编译是不会有反应的 ⇒ 专门有一条测试把它**当作协议用一次**
/// （`UploadIntakeTests.imageSeam`），同 `RepoEndpointsContractTests` 的处置。
public protocol ImageCompressing: Sendable {

    /// 把 `data` 压到 `targetBytes` 以内。
    ///
    /// - Returns: 不超过 `targetBytes` 的图片字节；**`nil` = 压不动**
    ///   （不是图片 / 动图 / 阶梯走完仍超限）。
    ///
    /// ⚠️ **输入本来就 ≤ `targetBytes` 时原样返回**（不重编码）——
    /// 但 `UploadIntake` **不会**依赖这一点：它在调用之前就判了（见那里的说明）。
    func compress(_ data: Data, targetBytes: Int) async -> Data?
}

extension ImageCompressor: ImageCompressing {}
