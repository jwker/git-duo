import GitDuoKit
import UIKit

/// 一处 markdown 正文**在哪儿** —— 取它里面那些"仓库内的图"所需的全部上下文
/// （2026-10-12 新增，`REVIEW-CHECKLIST` **第 58 条**）。
///
/// ## 为什么必须由调用方给
///
/// `MarkdownBody` 只拿到**解析好的块**（`[MarkdownBlock]`），它不知道自己在哪个仓库、
/// 哪个分支、哪一层目录下。而正文里那些相对地址的图（`../images/x.png`）**不取字节
/// 就画不出来** —— 这与链接不同：链接可以"点下去那一刻"才解析（`onOpenLink`），
/// 图片必须**提前**知道去哪儿取。
///
/// 三件事缺一不可：
/// - `fullName`：去哪个仓库取（相对地址本身不含仓库）；
/// - `ref`：取哪个分支的那一份 —— 不传就拿到默认分支，**切了分支图不变**；
/// - `baseDirectory`：相对地址的基准。README 是**仓库根**，文件页里是**该文件所在目录**
///   （`docs/guide.md` 里写 `../images/x.png` 指的是 `images/x.png`，不是 `docs/images/x.png`）。
struct MarkdownImageContext {

    let fullName: String

    /// 当前分支；`nil` = 默认分支（与 `LoadFileContent` 的 `ref` 同一语义）。
    let ref: String?

    /// 文档所在目录（**不是**文档自己的路径）。
    let baseDirectory: RepoPath

    let store: MarkdownImageStore
}

/// 一次取图的**结果**（2026-10-14 新增）。
///
/// ## ⚠️ 为什么不是 `UIImage?`
///
/// 2026-10-12 那一版返回 `UIImage?`，把两种情况合并成同一个 `nil`：
/// "这张图**取不到**"与"字节取到了、但**画不出来**"。
///
/// 2026-10-14 用户报回"README 里一部分图没出来"，取证之后发现那些图
/// **全都是 SVG**（`image/svg+xml`，见 `MarkdownImageBytes`）——
/// 也就是说合并成 `nil` 之后，占位块只能对用户说「图片加载失败」，
/// 而那句话**把排查方向指错了**：听起来像网络问题，实际网络上一切正常。
///
/// 三档现在的分工：
/// - `.failed` → 「图片加载失败」（取不到字节，或字节既不是位图也不是 SVG）；
/// - `.unsupportedFormat` → 「SVG 图片：xxx」（`MarkdownCopy` 那一句；空 alt 时为「SVG 图片」）。
enum MarkdownImageOutcome {

    /// 解出来了，可以直接画。
    case loaded(UIImage)

    /// 字节取到了、`UIImage` 解不出来，**且看起来是 SVG**。
    ///
    /// ⚠️ 「看起来是」的判据在 `MarkdownImageBytes.looksLikeSVG`（领域层、有单测）。
    ///
    /// - Parameter size: SVG **自己声明的**尺寸（`MarkdownImageBytes.declaredSize`）。
    ///   ⚠️ 2026-10-14 傍晚才带上它：此前占位块只能落"满宽 × 128"的兜底，
    ///   而 README 里那排徽章的 HTML **一个 `width` / `height` 都没写** ⇒
    ///   四块拼成一排大白条（用户截图里的样子）。
    ///   徽章自己声明的往往是 `98×20` 这种小尺寸 —— 浏览器就是读它来摆位的。
    case unsupportedFormat(MarkdownImageSize?)

    /// 取不到字节，或字节不是一张图、也不是 SVG。
    case failed
}

/// markdown 里**仓库内图片**的取数与解码缓存（2026-10-12，走查第 58 条）。
///
/// ## ⚠️ 字节层不另写缓存：HTTP 层已经有一份
///
/// `contents.rawFile` 走的是 `HTTPTransport`，它自带 `HTTPResponseCache`
/// （内存 + 磁盘，**自建** —— 决策 #32 禁掉的只是系统 `URLCache`），
/// 且 `cachesResponse` 默认 `true`、GET 默认带 ETag 条件请求
/// ⇒ 第二次取**同一张图**会走 **304，不额外计配额**。
///
/// 所以这里**不叠第二层字节缓存** —— 两层缓存迟早会在"什么时候失效"上对不上，
/// 而那种不一致表现为"图没跟着分支变"，很难查。
///
/// ## 它只做一件 HTTP 层做不了的事：留住 `UIImage`
///
/// `UIImage(data:)` 每次调用都会**重新解码**，而 `MarkdownBody` 在滚动 / 状态变化时
/// 会反复重绘 ⇒ 不缓存实例的话每帧解一次（一张 200KB 的 PNG 几毫秒，一屏几张
/// 就是肉眼可见的掉帧）。HTTP 层缓存的是字节，帮不上这一步。
///
/// ⚠️ **它必须有单例般的生命周期**（由 `AppEnvironment` 持有一个、随环境传给各处）——
/// 每个视图各 `new` 一个的话，缓存等于没有。
///
/// ## ⚠️ 它**只管仓库内的图**（2026-10-14 明确）
///
/// 仓库外的绝对地址（`https://img.shields.io/...`）不需要令牌、也不需要仓库与分支，
/// 由 `MarkdownImage` 自己用 `URLSession.shared` 取（那里把两条路的结果收成同一个
/// `MarkdownImageOutcome`，理由写在 `MarkdownImage` 的类型说明里）。
@MainActor
final class MarkdownImageStore {

    private let contents: any RepoContentsDataSource

    /// ⚠️ `NSCache` 而不是字典：内存吃紧时**系统自己清它**，而那一步不需要我们参与
    /// （图片随时能重新解码，代价只是几毫秒）。
    private let decoded = NSCache<NSString, UIImage>()

    init(contents: any RepoContentsDataSource) {
        self.contents = contents
    }

    /// 取一张仓库内的图。取不到时 `.failed`。
    ///
    /// ⚠️ **失败不进缓存**（只缓存成功解出来的那些）：失败可能是暂时的
    /// （断网、GitHub 抽风），把它记下来会让"过一会儿就好"的那张图**再也回不来**。
    /// `.unsupportedFormat` 同理 —— 代价只是重试时多走一次 HTTP 缓存命中的请求。
    func repositoryImage(fullName: String, ref: String?, path: RepoPath) async -> MarkdownImageOutcome {
        let key = Self.key(fullName: fullName, ref: ref, path: path)
        if let cached = decoded.object(forKey: key as NSString) { return .loaded(cached) }

        guard let (owner, repo) = try? RepositoryMapper.splitFullName(fullName) else { return .failed }
        guard let data = try? await contents.rawFile(
            owner: owner, repo: repo, path: path.raw, ref: ref
        ) else { return .failed }

        return Self.decode(data, cacheKey: key, into: decoded)
    }

    /// 字节 → 结果；解出来就进缓存。
    ///
    /// ## ⚠️ 两步的顺序不能反（先解码、后判格式）
    ///
    /// SVG 嗅探是**启发式**（找 `<svg` 字样），而 `UIImage(data:)` 是**确定**的。
    /// 先猜后解会让一张"恰好含 `<svg` 字样的坏 PNG"被报成 SVG ——
    /// 而那种错误没人会报回来，它看起来只是"这句话说得怪"。
    /// 判据与理由详见 `MarkdownImageBytes`。
    private static func decode(
        _ data: Data,
        cacheKey: String,
        into cache: NSCache<NSString, UIImage>
    ) -> MarkdownImageOutcome {
        guard let image = UIImage(data: data) else {
            // ⚠️ 顺序：先判"是不是 SVG"、再量"它有多大"（理由见 `MarkdownImageBytes`）。
            return MarkdownImageBytes.looksLikeSVG(data)
                ? .unsupportedFormat(MarkdownImageBytes.declaredSize(in: data))
                : .failed
        }
        cache.setObject(image, forKey: cacheKey as NSString)
        return .loaded(image)
    }

    /// 解码缓存的键。
    ///
    /// ⚠️ **必须带上仓库与分支**：同一个相对路径在两个仓库、两个分支下是
    /// **两张不同的图**（切分支后 `README.md` 里的图会跟着变）。
    /// 只按 `path` 存的话，切分支之后看到的仍是上一个分支的图 ——
    /// 而"图没跟着换"这件事极像"这个仓库的图本来就长这样"，不会有人报回来。
    private static func key(fullName: String, ref: String?, path: RepoPath) -> String {
        "\(fullName)@\(ref ?? "HEAD"):\(path.raw)"
    }
}
