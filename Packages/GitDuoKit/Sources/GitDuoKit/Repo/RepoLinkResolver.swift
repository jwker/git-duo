import Foundation

/// 一个链接**在 App 里该去哪儿**（TECH_SPEC §11.1 的链接支持范围落到行为这一层）。
///
/// ## 为什么不是 `Bool`（"是不是外部链接"）
///
/// 五档里每一档的**落点都不同**，而把其中几档合成一档，必然有一档被处理错：
///
/// | 档 | 落点 |
/// |---|---|
/// | `.file` | 推入文件查看页（§4.5）—— 图片链接也走它，那一页本来就会画图片 |
/// | `.directory` | 推入该路径的代码分区（§4.4 / §4.13） |
/// | `.external` | 交给系统 `openURL` |
/// | `.anchor` | **页内锚点**：解析得出来，但本期的块级模型不带 id ⇒ 没有落点 |
/// | `.unresolved` | 相对地址跳出了仓库根，或形状不认识 ⇒ 没有落点 |
///
/// ⚠️ `.anchor` 与 `.unresolved` **必须分开**：前者是"这个地址是对的，
/// 只是我们这一版不做井内跳转"，后者是"这个地址我们看不懂"。
/// 合成一档之后，两件事在界面上的表现会一模一样，而它们该说的话完全不同。
public enum RepoLinkTarget: Equatable, Sendable {

    /// 仓库内的文件。
    case file(RepoPath)

    /// 仓库内的目录。
    case directory(RepoPath)

    /// 仓库之外 —— 交给系统打开。
    case external(URL)

    /// 页内锚点（`#run`）。
    case anchor

    /// 解析不出落点。
    case unresolved
}

/// 把 README 里的一个链接解析成 `RepoLinkTarget`（纯函数，可单测）。
///
/// ## 它解决的是什么问题（2026-10-07 目视发现的第 3 条）
///
/// `[中文](README_zh.md)` 这种**仓库内相对链接**在 README 里遍地都是
/// （`anywhere-labs/dsh-desktop` 的 README 里就有几十条）。
/// `MarkdownInline` 会把它解析成一个 `URL` —— 但那个 `URL` 是**相对的**
/// （没有 scheme），赋给 `AttributedString.link` 之后系统**打不开**，
/// 表现是"点了没反应"。而源码里看不出任何异常：`URL(string: "README_zh.md")`
/// 是合法的，`piece.link = url` 也是合法的。
///
/// 所以要在"点下去"那一刻做一次解析，把相对地址**拼成仓库内的绝对路径**。
///
/// ## 为什么落点在领域层（不是视图里）
///
/// 判据同决策 #34：**App target 没有测试 target**。路径拼接恰好是那种
/// "写错了不报错、只是到了另一个地方"的活（`..` 多退一层、多一个斜杠、
/// 大小写不同的仓库名），必须有单测钉住。
///
/// ## ⚠️ 两条与"文件系统直觉"相反、但照 GitHub 网页端来的规则
///
/// 1. **以 `/` 开头的地址是站点根，不是仓库根** —— `/owner/repo/issues`
///    指的是 `https://github.com/owner/repo/issues`。按文件系统直觉把它当成
///    "仓库内的绝对路径"会让一多半站内链接落到错误的文件上。
/// 2. **`github.com` 的地址按 `blob` / `tree` 分辨文件与目录**，
///    而不是"结尾有没有斜杠"（GitHub 自己的 URL 就是这么区分的）。
public enum RepoLinkResolver {

    /// 解析一个链接。
    ///
    /// - Parameters:
    ///   - url: `MarkdownInline` 解析出来的地址（已经过 `URL(string:)` 校验）。
    ///   - fullName: 当前仓库全名（`owner/name`）—— 用来判"这是不是同一个仓库"。
    ///   - baseDirectory: **文档所在目录**（不是文档自己的路径）。README 在根目录，
    ///     所以调用方传当前目录。相对地址以它为基准。
    public static func target(
        for url: URL,
        fullName: String,
        baseDirectory: RepoPath = .root
    ) -> RepoLinkTarget {
        let raw = url.absoluteString

        // ① 空地址与纯锚点。（`href="#"` 也会到这一支。）
        if raw.isEmpty || raw.hasPrefix("#") { return .anchor }

        // ② 带协议的绝对地址。
        if let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                return github(url: url, fullName: fullName)
            default:
                // `mailto:` / `tel:` / 其他 —— 系统认得的协议比我们多，别自己判。
                return .external(url)
            }
        }

        // ③ 协议相对（`//github.com/…`）：稀有，按 https 补全。
        if raw.hasPrefix("//") {
            guard let absolute = URL(string: "https:" + raw) else { return .unresolved }
            return github(url: absolute, fullName: fullName)
        }

        // ④ 相对地址：先切掉 `?query` 与 `#fragment` —— 两者都不参与路径解析。
        var path = raw
        if let hash = path.firstIndex(of: "#") { path = String(path[..<hash]) }
        if let query = path.firstIndex(of: "?") { path = String(path[..<query]) }
        if path.isEmpty { return .anchor }
        // `%20` 这类转义要还原之后才是真实路径（服务端的 `contents` 端点吃原文）。
        if let decoded = path.removingPercentEncoding { path = decoded }

        // ⑤ 站点根相对（见类型说明第 1 条）。
        if path.hasPrefix("/") {
            guard let absolute = URL(string: "https://github.com" + path) else { return .unresolved }
            return github(url: absolute, fullName: fullName)
        }

        // ⑥ 仓库内相对路径：以文档所在目录为基准，逐段解析。
        //    ⚠️ 不用 `URLComponents` 拼 —— 那是为网络地址设计的，对"仓库内路径"
        //       它会补上 scheme / host，反而要再拆回来。
        let isDirectory = path.hasSuffix("/")
        var segments = baseDirectory.components

        for segment in path.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            switch segment {
            case ".":
                continue

            case "..":
                // 退到仓库根之上 ⇒ 这个地址指向仓库之外，而相对地址没有 host，
                // 猜不出它想去哪个网站 ⇒ 明确地"解析不出来"，不瞎跳。
                guard !segments.isEmpty else { return .unresolved }
                segments.removeLast()

            default:
                // `RepoPath.appending` 的那套校验（非空 / 不含 `/` / 不是 `.` `..`）
                // 在这里同样适用，而它是路径拼接唯一防得住"跨两级"的地方。
                guard RepoPath.isValidComponent(segment) else { return .unresolved }
                segments.append(segment)
            }
        }

        guard !segments.isEmpty else { return .anchor }
        let resolved = RepoPath(path: segments.joined(separator: "/"))
        return isDirectory ? .directory(resolved) : .file(resolved)
    }

    // MARK: - github.com 的地址

    /// `github.com` 上的地址：**同一个仓库**的 `blob` / `tree` 收回 App，其余交给系统。
    ///
    /// ⚠️ 只收同一个仓库。指向**别的**仓库的地址照旧进浏览器 —— 收进来的话，
    /// 这个新页面会以"当前仓库"的身份去取数，而它拿到的路径属于另一个仓库，
    /// 结果是 404 而不是"跳过去"（那比不跳更难解释）。
    private static func github(url: URL, fullName: String) -> RepoLinkTarget {
        guard let host = url.host?.lowercased(), host == "github.com" || host == "www.github.com" else {
            return .external(url)
        }

        // 路径形状：`/{owner}/{repo}/{blob|tree}/{ref}/{path…}`
        let segments = url.path.split(separator: "/").map(String.init)
        guard segments.count >= 4 else { return .external(url) }

        guard "\(segments[0])/\(segments[1])".caseInsensitiveCompare(fullName) == .orderedSame else {
            return .external(url)
        }

        switch segments[2] {
        case "blob", "tree":
            let path = RepoPath(path: segments.dropFirst(4)
                .map { $0.removingPercentEncoding ?? $0 }
                .joined(separator: "/"))
            return segments[2] == "tree" ? .directory(path) : .file(path)

        default:
            // `/issues` / `/releases` / `/pull/12` … 本 App 收不了这些地址。
            return .external(url)
        }
    }
}
