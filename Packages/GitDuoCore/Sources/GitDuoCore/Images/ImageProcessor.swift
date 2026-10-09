import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 一次图片预处理的**结局**（决策 #71 压缩 / #72 转码）。
///
/// 三件事各自有一个消费者，所以三件事都要带出来：
/// ① **字节**（要写上去的东西）· ② **格式**（文案里那句"转成了什么"）·
/// ③ **格式变没变**（文件名扩展名要不要跟着换）。
public struct ImageProcessingResult: Sendable, Equatable {

    /// 要写上去的字节（**可能就是原样的那一份**）。
    public let data: Data

    /// 输出格式；**`nil` = 原样**（一个字节都没动，`PRD §5.8` 那张表的第一档）。
    ///
    /// ⚠️ 它给**文案**用。非 `nil` **不等于**"格式变了" —— 一张 >1MB 的 PNG
    /// 压完还是 PNG，这一格是 `.png` 而 `didChangeFormat` 是 `false`。
    public let outputFormat: ImageOutputFormat?

    /// 输出格式与**源格式不同**吗（= 文件名扩展名要跟着换）。
    ///
    /// ⚠️ 只有本类型做得出这个判断：它同时看得见**源类型与输出类型**；
    /// 调用方手里只有文件名，而扩展名可以是错的（改过名的、没有扩展名的都见过）。
    public let didChangeFormat: Bool

    public init(data: Data, outputFormat: ImageOutputFormat?, didChangeFormat: Bool) {
        self.data = data
        self.outputFormat = outputFormat
        self.didChangeFormat = didChangeFormat
    }

    /// 一个字节都没动。
    ///
    /// ⚠️ 「原样」与「压过 / 转过」是**两种承诺**，调用方据此决定要不要给
    /// 那句 caption（`PRD §5.9①`）—— 所以这里给一个直白的名字，别让调用方去猜
    /// `outputFormat == nil` 是什么意思。
    public var isUntouched: Bool { outputFormat == nil }
}

/// 把一份用户选中的图片字节，处理成**能写进写通道、而且网页端显示得出来**的样子
///（**决策 #71 压缩** / **决策 #72 转码**，`PRD §5.8`）。
///
/// ## 它解决的是两件不同的事
///
/// | 事 | 谁提出来的 | 判据 |
/// |---|---|---|
/// | **体积**：写通道只有 Contents API 一条，上限 **1MB**（`SaveFile.maxContentBytes`），而真实照片动辄好几 MB | 决策 #71 | `data.count <= targetBytes` |
/// | **格式**：iPhone 相机默认拍 **HEIC**，浏览器根本渲染不出来 ⇒ 传上去在 GitHub 页面上是一块破图 | 决策 #72 | **不在** `renderableTypes` 里 |
///
/// ## 策略：先判"要不要动"，再分两族、各自沿一条阶梯往下走
///
/// | 情况 | 怎么办 |
/// |---|---|
/// | ≤1MB **且**格式已经在白名单里 | **原样返回**（`outputFormat == nil`）—— 一个字节都不许动 |
/// | 白名单**外**（HEIC / TIFF / BMP / RAW…） | **必转**，无论多大都转（#72③：用户明确要求"小于 1m 的也要转"） |
/// | 白名单内但 >1MB | **必压** |
///
/// 要重编码时，按源图属于哪一族选阶梯：
///
/// | 源图 | 阶梯 | 为什么 |
/// |---|---|---|
/// | **本该无损的**（PNG / 带 alpha / TIFF / BMP / 单帧 GIF） | **先只缩最长边**（2048 → 1600 → 1200 → 800），穷尽后接有损族 | 截图的价值全在"字锐利 + 背景透明" —— 转 JPEG 两样都毁。缩边是**无损**的，先用便宜的那一手；且无损源转 PNG 多数还**更小** |
/// | **其余**（HEIC / JPEG / WebP…） | **先逐档降画质**（2048 上 0.9 → 0.8 → 0.7），**再缩边** | 同尺寸下降画质比缩边更"看不出"，先把便宜的那一手用尽；反之把一张 2MB 的 HEIC 转成 PNG 可能到 15MB，画质还不会更好 |
///
/// 两族合起来最多 **13 次编码**（4 + 9）—— 这是"尽量少损失"的代价，故调用方要给等待反馈。
///
/// ## ⚠️ 四条不许忘的边界
///
/// 1. **不承诺一定压得下来**。超大像素图、以及**已经重度压缩过的 JPEG**（再压就是往一个
///    已经很小的包里继续榨），到阶梯末端仍可能超限 ⇒ 返回 `nil`，由调用方给"引导网页端"那句。
///    ⚠️ 对 #72 那几档来说这条**更要紧**：一个 ≤1MB 的源也可能转完之后反而装不进 1MB
///    （无损源尤其），那时它同样是"传不了"而不是"传个显示不出来的"。
/// 2. **动图不压也不转**。多帧图压完只剩第一帧 —— 那是**改内容**，不是压体积。判据 `CGImageSourceGetCount > 1`。
///    同上，返回 `nil` 让调用方走"引导网页端"。
/// 3. **它是有损的、而且会剥掉 EXIF（含 GPS 位置）**。传上去的不再是相册里那一份 ——
///    所以调用方**必须把"已压缩 / 已转换"这件事说给用户**（`CommitSheetCopy.adjustmentNotice`）。
/// 4. **体积可能反而变大**（#72 特有的那一档：HEIC 转 PNG、或无损源转 PNG 时）。
///    那**不是缺陷**，是"能显示出来"的代价 —— 但文案**必须说实话**，不许管它叫"已压缩"。
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
public struct ImageProcessor: Sendable {

    public init() {}

    // MARK: - 白名单（决策 #72①）

    /// **网页端显示得出来**的格式 —— 在这张单子里的，一个字节都不动。
    ///
    /// ⚠️ **这是外部事实，会变，用前复查**：它抄的是 GitHub 的 markdown 渲染器
    /// 明确支持的五个 —— **PNG / JPG / GIF / WebP / SVG**（另外四个的浏览器支持
    /// 早已是共识，只有 WebP 稍晚，Safari 14 起也已跟上）。
    ///
    /// ⚠️ **加这一条要慎重**：名单**短一点**的代价是"多转了一次"（用户看到一句
    /// caption、体积可能变一点），名单**长一点**的代价是"传上去显示不出来"
    ///（用户什么提示都没有，只看到一块破图）。**两种错法里短的更轻**，
    /// 所以拿不准的格式**不要**往里加。
    ///
    /// ⚠️ **有意留在名单外的两个**（2026-10-09 实测过 `UTType`，都不是笔误）：
    /// - **AVIF**：现代浏览器确实渲染得出来，但 `UTType` 里**没有编译期常量**
    ///   （`UTType.avif` 不存在，只能在运行时用 `UTType("public.avif")` 查），
    ///   而它又不在 GitHub 那份文档里 ⇒ **不留**。代价只是"AVIF 会被转成 JPEG"
    ///   （画质损失有限、体积略增），而收益是这张单子**全是编译期常量**、改不动都难。
    /// - **JPEG XL / JPEG 2000**：同理（`UTType.jpeg2000` 也不存在）—— 这类格式
    ///   两边都拿不准，按上面的原则一律转。
    public static let renderableTypes: [UTType] = [.png, .jpeg, .gif, .webP, .svg]

    /// 这个类型在网页端显示得出来吗（= 不用转）。
    ///
    /// ⚠️ 认不出来的类型（`UTType` 解不出）**当作显示不出来** —— 那是保守的那一侧
    /// （多转一次 vs 传上去一块破图，见 `renderableTypes` 的说明）。
    public static func isRenderable(_ type: UTType) -> Bool {
        renderableTypes.contains { type.conforms(to: $0) }
    }

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
    /// - Parameter losslessFirst: 该先走无损族吗 —— 源图是本该无损的那一类
    ///   （PNG / 带 alpha / TIFF / BMP / 单帧 GIF），见 `isLosslessSource(_:)` 与
    ///   `preservesLossless(_:)`。
    public static func steps(losslessFirst: Bool) -> [ImageCompressionStep] {
        let lossy = lossyLadder.map {
            ImageCompressionStep(format: .jpeg, maxEdge: $0.edge, quality: $0.quality)
        }
        guard losslessFirst else { return lossy }
        return losslessEdges.map {
            ImageCompressionStep(format: .png, maxEdge: $0, quality: nil)
        } + lossy
    }

    // MARK: - 处理

    /// 把 `data` 处理成"能写上去"的样子。
    ///
    /// - Returns: 结果（字节 + 输出格式 + 格式变没变）；**`nil` = 处理不动**
    ///   （不是图片 / 动图 / 阶梯走完仍超限）。
    ///
    /// ⚠️ **输入 ≤ `targetBytes` 且格式本来就在白名单里时原样返回**（`isUntouched`）——
    /// 那是"没必要动"，不是"动过了"。调用方据此判"要不要告诉用户东西被改过"。
    ///
    /// ⚠️ 它是 `async` 而**不是** `Task.detached`：本类型不是 actor、这个方法也不是
    /// `@MainActor`，按 SE-0338 它**不会继承调用方的 actor** —— 从 View 里 `await` 它，
    /// 这段 CPU 活就在协作线程池上跑，不会卡住界面。写成同步方法反而会（同步的
    /// `nonisolated` 函数在 MainActor 上下文里就是**在 MainActor 上**跑）。
    public func process(_ data: Data, targetBytes: Int) async -> ImageProcessingResult? {
        guard targetBytes > 0 else { return nil }

        // 不是图片（PDF / zip / 陌生格式）⇒ 交给调用方走"引导网页端"。
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }

        // ⚠️ **动图不压也不转**：多帧图（GIF / 动图 HEIC）压出来只剩第一帧。
        guard CGImageSourceGetCount(source) == 1 else { return nil }

        let sourceType = (CGImageSourceGetType(source) as String?).flatMap(UTType.init)
        // ⚠️ 源类型认不出来时（`sourceType == nil`）**当作显示不出来** —— 保守那一侧。
        let mustTranscode = !(sourceType.map(Self.isRenderable) ?? false)

        // ① 原样那一档：够小 **且** 格式已经在白名单里。
        //    ⚠️ #72③ 明确推翻了以前那种"只看大小"的写法 —— ≤1MB 的 HEIC 也**要转**。
        if !mustTranscode, data.count <= targetBytes {
            return ImageProcessingResult(data: data, outputFormat: nil, didChangeFormat: false)
        }

        // ② 要动。先定走哪一族：本来就是无损那一类（PNG / 带 alpha），
        //    或者"源本身无损"（TIFF / BMP / 单帧 GIF）—— 后者转 PNG 既无损又多数更小。
        let losslessFirst = preservesLossless(source, sourceType: sourceType)
            || (mustTranscode && sourceType.map(Self.isLosslessSource) == true)

        for step in Self.steps(losslessFirst: losslessFirst) {
            guard let encoded = encode(source: source, step: step) else { continue }
            guard encoded.count <= targetBytes else { continue }
            return ImageProcessingResult(
                data: encoded,
                outputFormat: step.format,
                didChangeFormat: step.format != Self.declaredFormat(of: sourceType)
            )
        }
        return nil
    }

    // MARK: - 判据

    /// 这张图**本该是无损的**吗（= 该先走无损族）。
    ///
    /// 两个来源，任一成立即可：
    /// ① ImageIO 读出来的**类型**是 PNG（认类型不认扩展名 —— 扩展名可以是错的）；
    /// ② 属性里有 **alpha 通道**（截图不一定存成 PNG，但透明通道是"要保住"的硬信号）。
    func preservesLossless(_ source: CGImageSource, sourceType: UTType?) -> Bool {
        if let sourceType, sourceType.conforms(to: .png) { return true }
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

    /// 这个类型的**编码本身是无损的**吗（#72②：无损源 → PNG 两全其美）。
    ///
    /// ⚠️ 只列真正无损的那几档。**TIFF 有例外**（它可以是 JPEG 压缩的），但那属于
    /// 边角中的边角，而"TIFF 走 PNG"在绝大多数情况下是对的 —— 判不准时就按无损处理，
    /// 因为错的那一侧只是"多做一次无损编码"，不是丢数据。
    static func isLosslessSource(_ type: UTType) -> Bool {
        type.conforms(to: .png) || type.conforms(to: .tiff)
            || type.conforms(to: .bmp) || type.conforms(to: .gif)
    }

    /// 这个类型**本身**是不是 PNG / JPEG（用来判"格式变没变"）。
    ///
    /// ⚠️ 返回 `nil` 表示"源既不是 PNG 也不是 JPEG"—— 那意味着输出**一定是换了格式的**
    /// （HEIC / TIFF / BMP… 都落在这一档），故 `didChangeFormat` 为 `true`。
    static func declaredFormat(of type: UTType?) -> ImageOutputFormat? {
        guard let type else { return nil }
        if type.conforms(to: .png) { return .png }
        if type.conforms(to: .jpeg) { return .jpeg }
        return nil
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
