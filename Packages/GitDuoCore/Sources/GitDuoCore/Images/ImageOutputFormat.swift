import Foundation
import UniformTypeIdentifiers

/// 图片处理**能输出**的两种格式（决策 #71 / #72）。
///
/// ## 为什么只有两种
///
/// 它们要同时满足三个条件：① **GitHub 网页端显示得出来**（这是 #72 存在的全部理由）；
/// ② **ImageIO 编得出来**（`CGImageDestinationCreateWithData` 认）；③ **体积可控**。
/// PNG（无损、带透明）与 JPEG（有损、体积最优）是唯二同时满足的。
///
/// ⚠️ **它描述的是"我们产出的东西"，不是"用户选中的东西"** —— 源图可能是 HEIC /
/// TIFF / BMP，那些**不在**这个枚举里（它们只有"被读进来"的份，没有"被写出去"的份）。
/// 判"源图属于哪一族"用的是 `UTType` 的具体类型，见 `ImageProcessor`。
public enum ImageOutputFormat: String, Sendable, Equatable, CaseIterable {

    /// 无损、带透明通道（PNG 没有质量旋钮）。
    case png

    /// 有损、体积最优（装不下透明通道 ⇒ 转它之前要摊白底）。
    case jpeg

    /// ImageIO 认的类型标识（`public.png` / `public.jpeg`）。
    public var identifier: String {
        switch self {
        case .png: UTType.png.identifier
        case .jpeg: UTType.jpeg.identifier
        }
    }

    /// 写进文件名的**小写扩展名、不带点**（`png` / `jpg`）。
    ///
    /// ⚠️ JPEG 这一档给的是 `jpg` 而不是 `jpeg`：换扩展名是为了让 GitHub 认得出来，
    /// 而 `jpg` 是那个更常见、更不会让人以为是另一种格式的写法（`UploadFileName`
    /// 的小写归一化也是这个口径）。
    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }

    /// 印给用户看的（`PNG` / `JPEG`）—— 提交弹层里那句 caption 用（`PRD §5.9①`）。
    ///
    /// ⚠️ 与 `fileExtension` **是两个量**：这一档是"别人怎么读这个格式名"，
    /// 那一档是"文件系统怎么认它"。合成一个必然有一处说错（`JPEG` 与 `jpg` 就是现成的例子）。
    public var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        }
    }
}

/// 一次编码尝试：输出什么格式、最长边压到多少、JPEG 画质取多少（决策 #71）。
///
/// ⚠️ 它**是纯数据**，抽出来是为了让"档位表长什么样"能被单测钉住 ——
/// 真正的编码在 `ImageProcessor` 里，而那张表是这条路上**唯一**会漂的东西
///（改了它，"同一张图压出来多大"就变了，而没有任何编译期信号）。
public struct ImageCompressionStep: Sendable, Equatable {

    /// 输出格式（`ImageOutputFormat`）。
    public let format: ImageOutputFormat

    /// 输出图的**最长边**上限（像素）。短边按原比例算。
    public let maxEdge: Int

    /// JPEG 画质（`0...1`）；**PNG 没有这个旋钮** ⇒ `nil`。
    public let quality: Double?

    public init(format: ImageOutputFormat, maxEdge: Int, quality: Double?) {
        self.format = format
        self.maxEdge = maxEdge
        self.quality = quality
    }
}
