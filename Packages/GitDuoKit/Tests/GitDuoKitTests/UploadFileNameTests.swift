import Foundation
import Testing

@testable import GitDuoKit

/// §5.8 相册出口的文件名规则（切片 8.4 自拟）。
///
/// ## 为什么这条规则值得被测试钉住
///
/// PRD §5.8 写的是"用**选中图片的文件名**"，而系统相册选择器**不提供文件名**
/// （iOS 27.0 SDK 里 `PhotosPickerItem` 只有 `itemIdentifier` / `supportedContentTypes` /
/// `loadTransferable`）。所以这一条不是"规格未给"，是**规格做不到** ——
/// 自拟的规则因此更需要被钉住：它是这条路上唯一由我们自己定下来的东西，
/// 而它错了（重名 / 没有扩展名）的表现是**每一次上传都要先碰一次壁**。
///
/// ⚠️ 断言里**不写死具体的时间戳字符串**：格式里的时分秒跟随设备时区，
/// 写死它会让这套测试在一台时区不同的机器上红掉 —— 而它红的时候，
/// 看代码的人会以为"文件名规则坏了"，实际只是测试与实现共享了同一个错误假设。
@Suite("上传文件名 · 自拟规则（§5.8 相册那条 PRD 做不到）")
struct UploadFileNameTests {

    /// 一个固定的时刻（不依赖"跑测试时是几点"）。
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("⚠️ 形状是 `photo-{yyyyMMdd-HHmmss}.{ext}`，且**全是 ASCII**")
    func photoNameShape() {
        let name = UploadFileName.photo(fileExtension: "png", now: base)

        #expect(name.hasPrefix("photo-"))
        #expect(name.hasSuffix(".png"))
        // ⚠️ 用 `range(of:options:.regularExpression)` 而不是正则字面量（`/…/`）：
        //    后者依赖 `BareSlashRegexLiterals` 这个语言特性开关，
        //    而本包的 `Package.swift` 没有显式打开它 —— 在本机编得过、换台机器就编不过。
        #expect(
            name.range(of: #"^photo-[0-9]{8}-[0-9]{6}\.png$"#, options: .regularExpression) != nil,
            "时间戳必须是定长数字 —— 名字出现在仓库文件列表里，形状不稳会看着像随手打的"
        )
        // ⚠️ 用闭包而不是 `allSatisfy(\.isASCII)`：后者在 `#expect` 的宏展开里会撞上
        //    "call is to 'rethrows' function, but argument function can throw"
        //    —— 一个与真实错误无关、但足以让整个测试文件编不过的假错。
        #expect(name.allSatisfy { $0.isASCII },
                "仓库文件名不该混进非 ASCII（会让部分工具链出乱码）")
    }

    @Test("⚠️ 扩展名归一化：`jpeg` → `jpg`（其余只做小写与去空白）")
    func extensionNormalization() {
        // `UTType.jpeg.preferredFilenameExtension` 返回的是 `jpeg`，而用户在网页端
        // 见到的都是 `jpg` —— 不归一化的代价不是报错，是仓库里多出一批写法不同的文件。
        #expect(UploadFileName.photo(fileExtension: "jpeg", now: base).hasSuffix(".jpg"))
        #expect(UploadFileName.photo(fileExtension: "JPEG", now: base).hasSuffix(".jpg"))
        #expect(UploadFileName.photo(fileExtension: "  jpeg ", now: base).hasSuffix(".jpg"))
        // ⚠️ `heic` **不**改成 `jpg`：§5.8 明写"取原始字节、不重编码"，
        //    改了名字而字节还是 HEIC，就是让名字说谎。
        #expect(UploadFileName.photo(fileExtension: "HEIC", now: base).hasSuffix(".heic"))
        #expect(UploadFileName.photo(fileExtension: "PNG", now: base).hasSuffix(".png"))
    }

    @Test("⚠️ 扩展名落空时兜底 `jpg` —— 一个没有扩展名的文件在 GitHub 上是二进制文件")
    func extensionFallback() {
        #expect(UploadFileName.photo(fileExtension: nil, now: base).hasSuffix(".jpg"))
        #expect(UploadFileName.photo(fileExtension: "", now: base).hasSuffix(".jpg"))
        #expect(UploadFileName.photo(fileExtension: "   ", now: base).hasSuffix(".jpg"))
    }

    @Test("⚠️ 相隔一秒的两张图**不同名** —— 重名在这条通道上是一条硬失败（服务端 422）")
    func namesDifferAcrossSeconds() {
        let first = UploadFileName.photo(fileExtension: "jpg", now: base)
        let second = UploadFileName.photo(fileExtension: "jpg", now: base.addingTimeInterval(1))
        #expect(first != second)
    }

    @Test("同一个时刻 + 同一个扩展名 ⇒ **同一个名字**（这条规则是纯函数，没有隐藏状态）")
    func deterministicForSameMoment() {
        let a = UploadFileName.photo(fileExtension: "jpg", now: base)
        let b = UploadFileName.photo(fileExtension: "jpg", now: base)
        #expect(a == b)
    }
}
