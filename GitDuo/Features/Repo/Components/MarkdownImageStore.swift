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
@MainActor
final class MarkdownImageStore {

    private let contents: any RepoContentsDataSource

    /// ⚠️ `NSCache` 而不是字典：内存吃紧时**系统自己清它**，而那一步不需要我们参与
    /// （图片随时能重新解码，代价只是几毫秒）。
    private let decoded = NSCache<NSString, UIImage>()

    init(contents: any RepoContentsDataSource) {
        self.contents = contents
    }

    /// 取一张仓库内的图（已解码）。取不到时 `nil` —— 调用方画占位块，
    /// **不区分**"404 / 超限 / 不是图片 / 网络断了"：对着一屏正文里的一张小图，
    /// 那些原因的区别给不出不同的动作（都是"这张图没出来"）。
    func image(fullName: String, ref: String?, path: RepoPath) async -> UIImage? {
        let key = Self.key(fullName: fullName, ref: ref, path: path)
        if let cached = decoded.object(forKey: key as NSString) { return cached }

        guard let (owner, repo) = try? RepositoryMapper.splitFullName(fullName) else { return nil }
        guard let data = try? await contents.rawFile(
            owner: owner, repo: repo, path: path.raw, ref: ref
        ) else { return nil }
        guard let image = UIImage(data: data) else { return nil }

        decoded.setObject(image, forKey: key as NSString)
        return image
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
