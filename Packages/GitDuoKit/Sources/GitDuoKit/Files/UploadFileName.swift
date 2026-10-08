import Foundation

/// 上传来源那两条通道**落在仓库根的文件名**（§5.8 的两个上传出口）。
///
/// ## ⚠️ 相册那一条：PRD 写的做法**做不到**（2026-10-08 核实）
///
/// PRD §5.8 那张表写的是「上传图片 · 相册 → **选中图片的文件名**，落在仓库根」。
/// 而系统相册选择器**不提供文件名** —— 核实过的公开 API：
///
/// | iOS 27.0 SDK（`_PhotosUI_SwiftUI`）里 `PhotosPickerItem` 的全部成员 |
/// |---|
/// | `itemIdentifier: String?`（相册内部的资源标识，形如 `UUID/L0/001`，**不是文件名**） |
/// | `supportedContentTypes: [UTType]` |
/// | `loadTransferable(type:)`（拿到字节，**不附名字**） |
///
/// 也就是说"用选中图片的文件名"这条规格**在当前 API 下没有落点**。
/// 所以这里自拟一条规则（**规格做不到 ⇒ 自拟，已登记**）：`photo-{时间戳}.{扩展名}`。
///
/// ⚠️ 为什么带时间戳而不是序号 / 随机串：
/// - **序号**（`image-1.jpg`）每一张都从一个新的计数开始，第二次上传必然与第一次重名，
///   而"重名"在这条通道上是一条**硬失败**（服务端 422，不静默覆盖，§5.8）——
///   于是用户每次上传第二张图都要先碰一次壁；
/// - **随机串**（`a3f9c1.jpg`）不会重名，但仓库里那串名字对谁都没有意义。
///
/// ⚠️ 时间戳用的是**秒**：同一秒内连选两张的概率极低，而精确到毫秒的名字
/// （`photo-20261008-142530123.jpg`）读起来像一串编号。两者权衡取秒。
public enum UploadFileName {

    /// 相册图片的落点文件名。
    ///
    /// - Parameters:
    ///   - fileExtension: 扩展名，来自 `PhotosPickerItem.supportedContentTypes`
    ///     第一项的 `preferredFilenameExtension`。**给 `nil` 或空串时回落 `jpg`** ——
    ///     一个没有扩展名的文件在 GitHub 上是"二进制文件"，看不见也预览不了。
    ///   - now: 时间戳。**必传**（同 `FileWriteTarget.defaultNewBranchName(now:)`）：
    ///     名字里带时间 ⇒ 它必须能被测试钉住，而不是"跑测试时恰好是几点"。
    public static func photo(fileExtension: String?, now: Date) -> String {
        "photo-\(stamp(now)).\(normalized(fileExtension) ?? fallbackExtension)"
    }

    /// 扩展名落空时的兜底。
    ///
    /// `jpg` 而不是 `png`：相册里绝大多数是照片（HEIC / JPEG），
    /// 而这一档只会在"系统没告诉我们它是什么格式"时用到 ——
    /// 那时给一个所有平台都认的位图扩展名，比给一个大概率不对的要好。
    private static let fallbackExtension = "jpg"

    /// 归一化扩展名：小写、去空白，并把 `jpeg` 收成 `jpg`。
    ///
    /// ⚠️ `jpeg` → `jpg` 这一个特例是**给人看的**：`UTType.jpeg.preferredFilenameExtension`
    /// 返回 `jpeg`，而用户在网页端、在别的项目里看到的都是 `jpg`。
    /// 不归一化的代价不是报错，是仓库里出现一批 `photo-….jpeg` —— 它们完全合法，
    /// 只是和所有人的习惯不一样。
    private static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        return trimmed == "jpeg" ? "jpg" : trimmed
    }

    /// `yyyyMMdd-HHmmss`（本地时区）。
    ///
    /// ⚠️ `Locale(identifier: "en_US_POSIX")` 不是可有可无的：`DateFormatter` 默认跟随
    /// 当前区域，而在某些区域下 `yyyy` 会按各自的历法渲染 —— 那个 bug 只在
    /// 那些区域的真机上出现，名字看起来仍然"像个时间戳"。
    ///
    /// ⚠️ 不用 `static let formatter`：`DateFormatter` 不是 `Sendable`，
    /// 而本仓开着 Swift 6 严格并发（一个全局 `let` 会在编译期被拦下）。
    /// 每次现造一个的开销在这一条通道上可以忽略（一次上传只问一次）。
    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
