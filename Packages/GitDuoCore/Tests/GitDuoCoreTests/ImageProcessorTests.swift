import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import GitDuoCore

/// 图片预处理：压缩（**决策 #71**）与转码（**决策 #72**），`PRD §5.8`。
///
/// ## 这些测试为什么不能只测"档位表"
///
/// 档位表是纯值，测它很便宜 —— 但这条路上真正会错的是**另外四件**：
/// ① 压完 / 转完**到底有没有**到目标以内（`ImageIO` 的实际输出我们改不动，只能实测）；
/// ② 该保住无损的那一档**有没有**真的保住（一张带透明的截图变成 JPEG 是**数据损失**，
///    而它在小尺寸缩略图上根本看不出来）；
/// ③ 该**拒绝**的那两档（不是图片 / 多帧动图）有没有老老实实回 `nil` ——
///    尤其动图：压了不会报错，只会**悄悄变成一张静图**；
/// ④ **#72 那一档：≤1MB 但格式显示不出来的，有没有真的还被转**（决策 #72③ 是本片的核心，
///    而它恰恰是"看起来什么都不用做"的那一档 —— 只看大小的话，这一条永远不会红）。
///
/// ⇒ 所以下面既有纯值的白名单 / 档位表断言，也有真的编码一张图、再读回来验证的断言。
@Suite("ImageProcessor · 白名单 / 档位表 / 压缩与转码边界（决策 #71 · #72）")
struct ImageProcessorTests {

    // MARK: - 造图

    /// 一张**噪声图**：不可压（PNG 编出来接近原始大小）。
    ///
    /// ⚠️ 噪声是必须的。纯色图 PNG / JPEG 都能压到几 KB，
    /// 那样"压缩"这条路**根本没被走到**，测试会永远绿。
    private func noiseImage(edge: Int, alpha: Bool) -> CGImage {
        let bytesPerRow = edge * 4
        var bytes = [UInt8](repeating: 255, count: bytesPerRow * edge)
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for index in stride(from: 0, to: bytes.count, by: 4) {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            bytes[index] = UInt8(truncatingIfNeeded: seed >> 33)
            bytes[index + 1] = UInt8(truncatingIfNeeded: seed >> 41)
            bytes[index + 2] = UInt8(truncatingIfNeeded: seed >> 49)
            // ⚠️ 一半像素给个半透明值：**alpha 通道要有真实内容**，
            //    否则 ImageIO 报的 `hasAlpha` 可能是假，第二条判据就白测了。
            bytes[index + 3] = alpha ? (index % 8 == 0 ? 128 : 255) : 255
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: edge,
            height: edge,
            bitsPerComponent: 8,
            // ⚠️ RGBA ⇒ 每像素 32 位。这个参数**没有默认值**（`CGImageCreate` 的
            //    `bitsPerPixel` 是必传的），漏了当场编不过 —— 好在它编不过。
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private func encode(_ image: CGImage, as type: UTType, quality: Double? = nil) -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, type.identifier as CFString, 1, nil
        ) else {
            Issue.record("造不出 \(type.identifier) 的编码器")
            return Data()
        }
        var properties: [CFString: Any] = [:]
        if let quality {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination), "编码 \(type.identifier) 失败")
        return output as Data
    }

    /// 回读一段字节：它是什么类型、最长边多大。
    private func inspect(_ data: Data) -> (type: String?, edge: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        else { return nil }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        return (CGImageSourceGetType(source) as String?, max(width, height))
    }

    /// 多帧 GIF（两帧）。
    private func animatedGIF(edge: Int) -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.gif.identifier as CFString, 2, nil
        ) else {
            Issue.record("造不出 GIF 编码器")
            return Data()
        }
        // ⚠️ 不设 GIF 的循环 / 延时字典：这里只要"帧数 = 2"这一件事，
        //    而嵌套字典桥接到 `CFDictionary` 是这条路上最容易编不过的一处
        //   （写它换来的信息对断言没有半点帮助）。
        let frame = noiseImage(edge: edge, alpha: false)
        for _ in 0 ..< 2 {
            CGImageDestinationAddImage(destination, frame, nil)
        }
        #expect(CGImageDestinationFinalize(destination), "编码 GIF 失败")
        return output as Data
    }

    // MARK: - 白名单（决策 #72①，纯值）

    @Test("⚠️ 白名单：网页端显示得出来的**不转**，其余一律转（名单错了没有任何信号）")
    func renderableWhitelist() {
        // ⚠️ 这一条是**外部事实**（GitHub 的 markdown 渲染器 + 现代浏览器），会变。
        //    它错的时候**没有任何信号** —— 只表现为"某类图传上去是一块破图"，
        //    所以这里逐条钉住：改动它必须是有意为之。
        //    ⚠️ 顺带钉住 `svg` 那个反直觉的真标识：`public.svg-image` 而不是 `public.svg`。
        for type in [UTType.png, .jpeg, .gif, .webP, .svg] {
            #expect(ImageProcessor.isRenderable(type), "\(type.identifier) 应当在白名单里（不转）")
        }
        #expect(UTType.svg.identifier == "public.svg-image")
        // HEIC / TIFF / BMP / ICO / RAW 浏览器一律渲染不出来。
        for type in [UTType.heic, .heif, .tiff, .bmp, .ico, .dng, .rawImage] {
            #expect(!ImageProcessor.isRenderable(type), "\(type.identifier) 不在白名单里（**要转**）")
        }
        // ⚠️ AVIF **有意**留在名单外（`UTType` 没有它的编译期常量），
        //    所以它走的是"转成 JPEG"那条路 —— 这条断言把那个取舍钉住。
        #expect(UTType(filenameExtension: "avif") != nil, "运行时查得到 AVIF（这不是查不到才不留的）")
        #expect(!ImageProcessor.isRenderable(UTType(filenameExtension: "avif")!))
    }

    @Test("无损源（转 PNG 两全其美）与有损源的分档")
    func losslessSourceTypes() {
        for type in [UTType.png, .tiff, .bmp, .gif] {
            #expect(ImageProcessor.isLosslessSource(type), "\(type.identifier) 的编码本身是无损的")
        }
        for type in [UTType.heic, .heif, .jpeg, .webP, .dng] {
            #expect(!ImageProcessor.isLosslessSource(type), "\(type.identifier) 不是无损编码")
        }
        // ⚠️ 这两条合起来**就决定了 HEIC 的归宿**，不必真造一张 HEIC：
        //    不在白名单（必转）× 有损编码（走有损族）⇒ 转成 JPEG。
        #expect(!ImageProcessor.isRenderable(.heic) && !ImageProcessor.isLosslessSource(.heic))
    }

    @Test("`declaredFormat`：源本身是不是 PNG / JPEG —— 它决定格式变没变")
    func declaredFormatOfSource() {
        #expect(ImageProcessor.declaredFormat(of: .png) == .png)
        #expect(ImageProcessor.declaredFormat(of: .jpeg) == .jpeg)
        // ⚠️ `nil` 的含义是"源既不是 PNG 也不是 JPEG"⇒ 输出**一定**换了格式。
        #expect(ImageProcessor.declaredFormat(of: .heic) == nil)
        #expect(ImageProcessor.declaredFormat(of: .tiff) == nil)
        #expect(ImageProcessor.declaredFormat(of: nil) == nil, "解不出来的类型同样算换了格式")
    }

    // MARK: - 档位表（纯值）

    @Test("无损族在**最前面**、而且整族都只有缩边（PNG 没有质量旋钮）")
    func losslessStepsComeFirst() {
        let steps = ImageProcessor.steps(losslessFirst: true)
        let losslessCount = ImageProcessor.losslessEdges.count

        #expect(steps.count > losslessCount)
        for step in steps.prefix(losslessCount) {
            #expect(step.format == .png)
            #expect(step.quality == nil)
        }
        // 穷尽无损之后**必须**留一条有损的路 —— 否则一张超大 PNG 会直接走到"压不动"，
        // 而它其实转成 JPEG 就装得下（决策 #71 的"穷尽后转 JPEG"）。
        #expect(steps.dropFirst(losslessCount).allSatisfy { $0.format == .jpeg })
        #expect(steps.dropFirst(losslessCount).allSatisfy { $0.quality != nil })
    }

    @Test("有损族：尺寸与画质都**单调不增**（顺序错了会让能压下来的图反而压不下来）")
    func lossyLadderIsMonotonic() {
        let steps = ImageProcessor.steps(losslessFirst: false)
        #expect(steps.count > 1)
        #expect(steps.allSatisfy { $0.format == .jpeg })

        for (previous, next) in zip(steps, steps.dropFirst()) {
            #expect(next.maxEdge <= previous.maxEdge)
            #expect((next.quality ?? 0) <= (previous.quality ?? 0))
            // 同一档里**不许同时**放宽两个维度：那会让"到底哪一步起作用"看不出来。
            #expect(next.maxEdge < previous.maxEdge || (next.quality ?? 0) < (previous.quality ?? 0))
        }

        // 最后一步必须是**最狠的那一档**（阶梯的末端 = 它还压不下来就真压不下来了）。
        #expect(steps.last?.maxEdge == ImageProcessor.lossyLadder.last?.edge)
        #expect(steps.last?.quality == ImageProcessor.lossyLadder.last?.quality)
    }

    @Test("源图不是无损那一类时，就**只有**有损族（PNG 那几步白跑一遍是纯浪费）")
    func lossyOnlyWhenNotLossless() {
        let lossless = ImageProcessor.steps(losslessFirst: true)
        let lossy = ImageProcessor.steps(losslessFirst: false)
        #expect(lossless.count == lossy.count + ImageProcessor.losslessEdges.count)
        #expect(lossless.suffix(lossy.count).elementsEqual(lossy))
    }

    // MARK: - 真的压 / 真的转

    @Test("一张几 MB 的 JPEG 照片：压得到目标以内，输出仍是 JPEG、格式没变")
    func largePhotoGetsUnderTarget() async {
        let source = encode(noiseImage(edge: 1600, alpha: false), as: .jpeg, quality: 0.95)
        #expect(inspect(source)?.type == UTType.jpeg.identifier)

        // ⚠️ 目标取**四分之一**而不是"小到极限"：噪声 JPEG 的有损族要走好几档才够，
        //    取太狠会让这条测试变成"阶梯末端正好压得下/压不下"的边界赌博 ——
        //    它红的时候看起来像实现坏了，实际只是我给的目标数太贴近末端。
        let target = source.count / 4
        let processed = await ImageProcessor().process(source, targetBytes: target)

        // ⚠️ 不用 `try? #require(...)`：那会换来一条"'#require(_:_:)' is redundant
        //    because 'processed' never equals 'nil'" 的**假警告**（与本项目记过的
        //    "`try #require` 别写在 `#expect` 里面"同一族）—— 零警告是提交门槛，
        //    而这条警告指向的原因并不存在。`guard` 说的是同一件事，且说得更直。
        guard let result = processed else {
            Issue.record("这张图应该压得动（噪声 JPEG 是有损族的正例）")
            return
        }
        #expect(result.data.count <= target)
        #expect(!result.isUntouched, "压过了就不该报「原样」")
        // ⚠️ JPEG 进、JPEG 出 ⇒ **扩展名不用换**（这一位错了会把 .jpg 又"换"一次，
        //    看起来没坏，但判据本身已经失真）。
        #expect(result.outputFormat == .jpeg)
        #expect(!result.didChangeFormat)

        let info = inspect(result.data)
        #expect(info?.type == UTType.jpeg.identifier, "有损那一族输出的是 JPEG")
        // 最长边不许比原图还大（`MaxPixelSize` 不该放大任何东西）。
        #expect((info?.edge ?? .max) <= 1600)
    }

    @Test("带透明的 PNG：**先缩边、保住 PNG**（转成 JPEG 就是丢了透明通道）")
    func transparentPNGStaysPNG() async {
        // 噪声 PNG（带 alpha）：1400² 编出来约 7.5MB（噪声几乎不可压，≈ 4 字节/像素）。
        // 目标 4MB ⇒ 2048 / 1600 / 1200 三档无损都装不下，**800 那一档**才够（≈2.5MB）。
        // 留这么大余量是刻意的：这条测的是"**还会不会**是 PNG"，
        // 不该同时变成"800 这一档正好压不压得下"的边界赌博。
        let source = encode(noiseImage(edge: 1400, alpha: true), as: .png)
        #expect(inspect(source)?.type == UTType.png.identifier)

        let target = 4_000_000
        #expect(source.count > target, "源图得真的超限，否则这一步什么都没测到")

        let processed = await ImageProcessor().process(source, targetBytes: target)
        guard let result = processed else {
            Issue.record("缩边之后应该装得下")
            return
        }
        #expect(result.data.count <= target)
        #expect(!result.didChangeFormat, "PNG 进 PNG 出 ⇒ 文件名一个字都不用动")
        #expect(inspect(result.data)?.type == UTType.png.identifier, "无损那一档**不该**被换成 JPEG")
    }

    @Test("本来就够小、且格式显示得出来 ⇒ **原样返回**（不重编码）")
    func smallRenderableComesBackUntouched() async {
        let source = encode(noiseImage(edge: 64, alpha: false), as: .jpeg)
        let processed = await ImageProcessor().process(source, targetBytes: 1_000_000)

        #expect(processed?.isUntouched == true, "没超限的字节应当被原样放行")
        #expect(processed?.data == source, "而且**一模一样**（一个字节都不许动）")
        #expect(processed?.didChangeFormat == false)
    }

    // MARK: - #72 的核心：≤1MB 也要转

    @Test("⚠️ **≤1MB 的 TIFF 照样被转**（决策 #72③ —— 只看大小的话这一档永远绿）")
    func smallTranscodableIsStillTranscoded() async {
        // TIFF 是**无损**且**不在白名单**里的格式 ⇒ 两个条件都命中：
        // 必转，且转成 PNG（无损→无损）。
        let source = encode(noiseImage(edge: 300, alpha: false), as: .tiff)
        #expect(inspect(source)?.type == UTType.tiff.identifier)

        // ⚠️ 目标取得比源图**大** —— 这样一来"要不要处理"就只剩**格式**这一个理由。
        //    如果哪天有人把 #72 那一条删了（"小图不用动"看起来太合理了），
        //    这条会立刻红。
        let target = 1_000_000
        #expect(source.count <= target, "源图必须**不超限**，否则这条测的就变成压缩了")

        let processed = await ImageProcessor().process(source, targetBytes: target)
        guard let result = processed else {
            Issue.record("TIFF 应当转得动")
            return
        }
        #expect(!result.isUntouched, "≤1MB 也要转 —— 这正是决策 #72③ 那一条")
        #expect(result.outputFormat == .png, "TIFF 无损 ⇒ 走 PNG（转 JPEG 是白丢一次质量）")
        #expect(result.didChangeFormat, "TIFF → PNG 是换了格式 ⇒ 文件名扩展名要跟着换")
        #expect(result.data != source, "转过了就不该还是那串字节")
        #expect(inspect(result.data)?.type == UTType.png.identifier)
        #expect(result.data.count <= target)
    }

    @Test("⚠️ BMP 同理：小也要转成 PNG（老格式，浏览器显示不出来）")
    func smallBMPIsTranscodedToPNG() async {
        let source = encode(noiseImage(edge: 200, alpha: false), as: .bmp)
        let processed = await ImageProcessor().process(source, targetBytes: 1_000_000)
        guard let result = processed else {
            Issue.record("BMP 应当转得动")
            return
        }
        #expect(result.outputFormat == .png)
        #expect(result.didChangeFormat)
        #expect(inspect(result.data)?.type == UTType.png.identifier)
    }

    @Test("⚠️ 多帧动图**不压也不转**：压完只剩第一帧，那是改内容不是改体积")
    func animatedSourceIsRefused() async {
        let source = animatedGIF(edge: 64)
        let count = CGImageSourceCreateWithData(source as CFData, nil)
            .map { CGImageSourceGetCount($0) } ?? 0
        #expect(count == 2, "造出来的得真的是动图")

        // ⚠️ 目标必须比源图小 —— 否则会在"本来就不超限"那一档提前返回，这测就成了空的。
        let result = await ImageProcessor().process(source, targetBytes: 1)
        #expect(result == nil, "动图应当拒绝，交给调用方去给「引导网页端」那句")
    }

    @Test("不是图片 ⇒ 返回 nil（由调用方给同一句提示）")
    func nonImageReturnsNil() async {
        let result = await ImageProcessor()
            .process(Data("这不是一张图片，只是一串文字".utf8), targetBytes: 1)
        #expect(result == nil)
    }
}
