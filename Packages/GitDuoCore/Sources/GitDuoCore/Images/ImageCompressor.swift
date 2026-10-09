import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 一次编码尝试：输出什么格式、最长边压到多少、JPEG 画质取多少（决策 #71）。
///
/// ⚠️ 它**是纯数据**，抽出来是为了让"档位表长什么样"能被单测钉住 ——
/// 真正的编码在 `ImageCompressor` 里，而那张表是这条路上**唯一**会漂的东西
///（改了它，"同一张图压出来多大"就变了，而没有任何编译期信号）。
public struct ImageCompressionStep: Sendable, Equatable {

    /// 输出格式。**只有两种**：PNG（无损、带透明）与 JPEG（有损、体积最优）。
    public enum Format: String, Sendable, Equatable {
        case png
        case jpeg

        /// ImageIO 认的类型标识。
        var identifier: String {
            switch self {
            case .png: UTType.png.identifier
            case .jpeg: UTType.jpeg.identifier
            }
        }
    }

    public let format: Format

    /// 输出图的**最长边**上限（像素）。短边按原比例算。
    public let maxEdge: Int

    /// JPEG 画质（`0...1`）；**PNG 没有这个旋钮** ⇒ `nil`。
    public let quality: Double?

    public init(format: Format, maxEdge: Int, quality: Double?) {
        self.format = format
        self.maxEdge = maxEdge
        self.quality = quality
    }
}

/// 把一张图片压到给定字节数以内（**决策 #71** / `PRD §5.8`）。
///
/// ## 它解决的是一件具体的事
///
/// 写通道只有 Contents API 一条，上限 **1MB**（`SaveFile.maxContentBytes`）。
/// 而真实照片动辄好几 MB ⇒ 不加这一步，相册那条上传出口对大多数照片**形同虚设**
/// （用户选完只得到一句"请到 GitHub 网页端处理"）。
///
/// ## 策略：分两族、各自沿一条阶梯往下走
///
/// | 源图 | 阶梯 | 为什么 |
/// |---|---|---|
/// | **PNG / 带 alpha** | **只缩最长边**（2048 → 1600 → 1200 → 800），穷尽后接有损族 | 截图的价值全在"字锐利 + 背景透明" —— 转 JPEG 两样都毁。缩边是**无损**的，先用便宜的那一手 |
/// | **其余**（HEIC / JPEG / WebP…） | **先逐档降画质**（2048 上 0.9 → 0.8 → 0.7），**再缩边** | 同尺寸下降画质比缩边更"看不出"，先把便宜的那一手用尽 |
///
/// 两族合起来最多 **13 次编码**（4 + 9）—— 这是"尽量少损失"的代价，故调用方要给等待反馈。
///
/// ## ⚠️ 三条不许忘的边界
///
/// 1. **不承诺一定压得下来**。超大像素图、以及**已经重度压缩过的 JPEG**（再压就是往一个
///    已经很小的包里继续榨），到阶梯末端仍可能超限 ⇒ 返回 `nil`，由调用方给"引导网页端"那句。
/// 2. **动图不压**。多帧图压完只剩第一帧 —— 那是**改内容**，不是压体积。判据 `CGImageSourceGetCount > 1`。
///    同上，返回 `nil` 让调用方走"引导网页端"。
/// 3. **它是有损的、而且会剥掉 EXIF（含 GPS 位置）**。传上去的不再是相册里那一份 ——
///    所以调用方**必须把"已压缩"这件事说给用户**（`CommitSheetCopy.compressedNotice`）。
///
/// ## 为什么用 ImageIO 而不是 UIKit
///
/// 本包（`GitDuoCore`）为**宿主 macOS 也构建**（`Package.swift` 的 platforms 注释写明：
/// 那是为了能在 Mac 上跑 `swift test`）⇒ 不能 `import UIKit`。`CoreGraphics` / `ImageIO`
/// 两个平台都有，且都是系统框架 ⇒ **零第三方依赖**（决策 #12）不破。
///
/// ## ⚠️ 缩略图 API 顺带把"方向"烘焙进像素
///
/// `kCGImageSourceCreateThumbnailWithTransform: true` 会把 EXIF 的 `Orientation` 应用到像素上。
/// 少写这一个键，**竖着拍的照片传上去会躺倒**（而它在相册里是正的）——
/// 这类"我们改了用户的东西还没改对"的问题最难被发现。
public struct ImageCompressor: Sendable {

    public init() {}

    // MARK: - 档位表

    /// 有损族：**先降质、再缩边**。
    ///
    /// ⚠️ 顺序是刻意的：同一尺寸下先试高画质，降到底仍超才动尺寸 ——
    /// 反过来（先缩到 640 再降质）会把一张只超一点点的图缩成缩略图。
    static let lossyLadder: [(edge: Int, quality: Double)] = [
        (2048, 0.9), (2048, 0.8), (2048, 0.7),
        (1600, 0.7), (1600, 0.6),
        (1200, 0.6), (1200, 0.5),
        (800, 0.5),
        (640, 0.5),
    ]

    /// 无损族：PNG 没有质量旋钮 ⇒ **只有缩边**。
    static let losslessEdges = [2048, 1600, 1200, 800]

    /// 这一族会走哪几步（**唯一落点**，有单测）。
    ///
    /// - Parameter preservingLossless: 源图是否需要保住无损与透明
    ///   （PNG，或带 alpha 通道 —— 见 `preservesLossless(_:)`）。
    public static func steps(preservingLossless: Bool) -> [ImageCompressionStep] {
        let lossy = lossyLadder.map {
            ImageCompressionStep(format: .jpeg, maxEdge: $0.edge, quality: $0.quality)
        }
        guard preservingLossless else { return lossy }
        return losslessEdges.map {
            ImageCompressionStep(format: .png, maxEdge: $0, quality: nil)
        } + lossy
    }

    // MARK: - 压缩

    /// 把 `data` 压到 `targetBytes` 以内。
    ///
    /// - Returns: 不超过 `targetBytes` 的图片字节；**`nil` = 压不动**
    ///   （不是图片 / 动图 / 阶梯走完仍超限）。
    ///
    /// ⚠️ **输入本来就 ≤ `targetBytes` 时原样返回**（不重编码）——
    /// 那是"没必要压"，不是"压过了"。调用方据此判"要不要告诉用户已压缩"：
    /// 拿 `data.count` 与返回值比一下即可（`UploadIntake` 就是这么做的）。
    ///
    /// ⚠️ 它是 `async` 而**不是** `Task.detached`：本类型不是 actor、这个方法也不是
    /// `@MainActor`，按 SE-0338 它**不会继承调用方的 actor** —— 从 View 里 `await` 它，
    /// 这段 CPU 活就在协作线程池上跑，不会卡住界面。写成同步方法反而会（同步的
    /// `nonisolated` 函数在 MainActor 上下文里就是**在 MainActor 上**跑）。
    public func compress(_ data: Data, targetBytes: Int) async -> Data? {
        guard targetBytes > 0 else { return nil }
        if data.count <= targetBytes { return data }

        // 不是图片（PDF / zip / 陌生格式）⇒ 交给调用方走"引导网页端"。
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }

        // ⚠️ **动图不压**：多帧图（GIF / 动图 HEIC）压出来只剩第一帧。
        guard CGImageSourceGetCount(source) == 1 else { return nil }

        for step in Self.steps(preservingLossless: preservesLossless(source)) {
            guard let encoded = encode(source: source, step: step) else { continue }
            if encoded.count <= targetBytes { return encoded }
        }
        return nil
    }

    // MARK: - 判据

    /// 这张图需要保住无损与透明吗（= 走无损族）。
    ///
    /// 两个来源，任一成立即可：
    /// ① ImageIO 读出来的**类型**是 PNG（认类型不认扩展名 —— 扩展名可以是错的）；
    /// ② 属性里有 **alpha 通道**（截图不一定存成 PNG，但透明通道是"要保住"的硬信号）。
    func preservesLossless(_ source: CGImageSource) -> Bool {
        if let raw = CGImageSourceGetType(source) as String?,
           let type = UTType(raw),
           type.conforms(to: .png) {
            return true
        }
        // ⚠️ 走 `NSNumber` 而不是 `as? Bool`：ImageIO 这个键有时给 `CFBoolean`、
        //    有时给 `NSNumber(0/1)`，而后者 `as? Bool` 会**静默地**得到 `nil`
        //    （于是"带透明的图保住 PNG"这条判据永远不成立，且没有任何信号）。
        //    `CFBoolean` 与 `NSNumber` 免费桥接 ⇒ `as? NSNumber` 两种都吃得到。
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let hasAlpha = properties[kCGImagePropertyHasAlpha] as? NSNumber,
           hasAlpha.boolValue {
            return true
        }
        return false
    }

    // MARK: - 编码

    /// 按一步尝试编码；编不出来（这一步在这个源上做不到）返回 `nil`，由调用方试下一步。
    private func encode(source: CGImageSource, step: ImageCompressionStep) -> Data? {
        // ⚠️ 用缩略图 API 而不是"解码整图 + 自己缩放"：前者对超大图**不会**在内存里
        //    展开一整幅位图（一张 12000×9000 的图展开是 ~400MB），而后者会。
        //    `WithTransform` 顺带把 EXIF 方向烘焙进像素（见类型说明）。
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: step.maxEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(
            source, 0, thumbnailOptions as CFDictionary
        ) else { return nil }

        // JPEG 没有 alpha 通道 ⇒ 带透明的图要先摊到**白底**上。
        // ⚠️ 不摊的话，透明白的截图会变成黑底（透明像素底下的 RGB 通常是 0）。
        let image = step.format == .jpeg ? Self.flattenedOverWhite(decoded) : decoded

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, step.format.identifier as CFString, 1, nil
        ) else { return nil }

        var properties: [CFString: Any] = [:]
        if let quality = step.quality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// 把带 alpha 的图画到白底上，得到一张不透明的图（JPEG 用）。
    ///
    /// ⚠️ 尺寸**原样**（不缩放）：缩放在上一步已经由 `MaxPixelSize` 做完了，
    /// 这里只解决"JPEG 装不下透明"这一件事。
    private static func flattenedOverWhite(_ image: CGImage) -> CGImage {
        let alphaInfo = image.alphaInfo
        let isOpaque = alphaInfo == .none || alphaInfo == .noneSkipFirst || alphaInfo == .noneSkipLast
        if isOpaque { return image }

        let width = image.width
        let height = image.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
