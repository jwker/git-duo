import Foundation

/// 仓库条目的类型 —— `contents` 响应里 `type` 字段的领域化形态。
///
/// ## ⚠️ 目录的取值是 **`"dir"`**，不是 `"directory"`
///
/// 这是本类型**不能**用 `enum ... : String` 自动合成 `init(rawValue:)` 的原因：
/// 按 GitHub 文档里的措辞（"directory"）写枚举，会让**每一个目录**都掉进兜底档 ——
/// 而兜底档的表现是"这点不动"，不是报错。一条都认不出来，页面上却看不出哪里坏了。
/// 沙箱里那次实测的返回是 `{"type":"dir"}`。
///
/// ⚠️ **留 `unknown` 兜底**，不把认不出的取值判成解码失败：这是个字符串枚举，
/// GitHub 将来多一个取值（它已经加过 `symlink` / `submodule`）时，
/// "整页打不开"是不可接受的。判成 `unknown` 的后果只是"这类条目在 App 里点不动"。
public enum RepoContentType: Sendable, Hashable {

    case file
    case directory

    /// 符号链接。⚠️ 它的 `content` 是**链接目标那串文本**（`../foo/bar`），不是文件内容。
    case symlink

    /// 子模块。⚠️ 它的 `sha` 是**另一个仓库的提交**，点进去请求 contents 只会 404。
    case submodule

    /// 认不出来的取值。
    case unknown

    /// 由服务端字符串构造。认不出 ⇒ `.unknown`（**不是** `.file`）。
    ///
    /// ⚠️ 兜底成 `.file` 会让 `symlink` / 未来新类型被当成普通文件打开 ——
    /// 用户会看到一行 `../foo/bar` 并以为那就是文件内容。
    /// 兜底成 `.unknown` 至少是"点不动"，而不是"显示错误的内容"。
    ///
    /// ⚠️ 同时认 `dir` 与 `directory`：前者是**实测**的取值（`contents` 端点），
    /// 后者是文档与 `git/trees` 语境下的措辞。两个都收的成本是零，
    /// 而漏掉前者的成本是"整个文件树点不动"。
    public init(rawType: String?) {
        switch (rawType ?? "").lowercased() {
        case "file":
            self = .file
        case "dir", "directory":
            self = .directory
        case "symlink":
            self = .symlink
        case "submodule":
            self = .submodule
        default:
            self = .unknown
        }
    }

    /// 能不能按"文件"打开（只有真正的 `file` 可以）。
    public var isFile: Bool { self == .file }

    /// 能不能进下一级。
    public var isDirectory: Bool { self == .directory }
}

/// **目录**清单的一项 —— `GET /repos/{owner}/{repo}/contents/{path}` 在 `path` 是目录时
/// 返回一个数组，元素形如本类型（TECH_SPEC §9.5、决策 #49）。
///
/// ## ⚠️ 这里**没有任何提交信息**（2026-10-07 实测）
///
/// 实测返回项只有 `name` / `path` / `sha` / `size` / `type` / `url` / `_links` /
/// `git_url` / `html_url` / `download_url` —— PRD §3.2 要的「最近提交信息」
/// **不在这个响应里**（`git/trees` 也没有），只能逐条补
/// `GET …/commits?path={p}&per_page=1`（决策 #49）。
/// 所以本类型**不收** `url` / `_links` / `git_url` / `html_url` / `download_url`：
/// 本切片没有任何界面要用它们，收了就是五个死字段
/// （同 `IssueDTO` "只声明卡片真正用到的字段"的取舍）。
public struct ContentEntryDTO: Sendable, Equatable, Decodable {

    /// 条目名（不含路径）。目录行显示的是它。
    public let name: String

    /// 仓库内**完整**路径（`docs/guide.md`）—— 进下一级 / 打开文件都用它。
    public let path: String

    /// blob（文件）或 tree（目录）的 SHA。⚠️ 编辑器保存时要拿它当"更新"的凭据（§9.6），
    /// 所以不能因为本页只读就丢掉。目录的 SHA 是那一层树的 SHA。
    public let sha: String

    /// 字节数。**目录为 `nil` 或 `0`**（服务端对目录不下发真实大小），
    /// 所以声明成可选：把它当"一定是 0"会在某天服务端不发该字段时整页解码失败。
    public let size: Int?

    public let type: RepoContentType

    public init(
        name: String,
        path: String,
        sha: String,
        size: Int? = nil,
        type: RepoContentType
    ) {
        self.name = name
        self.path = path
        self.sha = sha
        self.size = size
        self.type = type
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case path
        case sha
        case size
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        sha = try container.decode(String.self, forKey: .sha)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        // ⚠️ `type` 用 `decodeIfPresent` + 兜底 `unknown`：将来若某个条目没带 type，
        // 我们希望它是"这一条点不动"，而不是"整个目录打不开"。
        type = RepoContentType(
            rawType: try container.decodeIfPresent(String.self, forKey: .type)
        )
    }
}

/// **单个文件**的 payload —— `GET /repos/{owner}/{repo}/contents/{path}` 在 `path` 是文件时
/// 返回一个**对象**（不是数组），形如本类型。TECH_SPEC §9.5、决策 #54。
///
/// ## ⚠️ 两个字段是"大文件降级"的判据，一个都不能少
///
/// - `size` —— 决定走哪条通道（≤1MB 走 base64，>1MB 走 raw）；
/// - `encoding` —— **`"none"`** 是"内容没给你"的**显式**信号。
///
/// 2026-10-07 实测：4,280,356 字节的文件回 **200 + `encoding:"none"` + `content: ""`**
/// —— HTTP 状态码是 200、不是错误，所以**只看状态码会把空串当成文件内容**。
public struct RepoFileDTO: Sendable, Equatable, Decodable {

    public let name: String
    public let path: String
    public let sha: String

    /// 字节数。
    ///
    /// ⚠️ **刻意声明为必需**：它是"走哪条通道"的判据（决策 #54），
    /// 缺席时补 `0` 会被判成"小文件"⇒ 拿一个空 `content` 渲染出一页**空白**
    /// （而用户以为文件是空的）。宁可解码失败，也不给出一个错误的档位。
    /// 实测该字段在单文件响应里恒存在（`symlink` / `submodule` 回 `0`）。
    public let size: Int

    /// `"base64"`（默认）或 **`"none"`**（文件 >1MB，见类型说明）。
    ///
    /// 用 `String?` 而不是枚举：它是个字符串字段，枚举化会让某个新取值
    /// 变成"整页解码失败"（同 `IssueDTO.state` 的处理）。
    public let encoding: String?

    /// base64 编码的文件内容。`encoding == "none"` 时是**空串**。
    public let content: String?

    public let type: RepoContentType

    public init(
        name: String,
        path: String,
        sha: String,
        size: Int,
        encoding: String? = nil,
        content: String? = nil,
        type: RepoContentType = .file
    ) {
        self.name = name
        self.path = path
        self.sha = sha
        self.size = size
        self.encoding = encoding
        self.content = content
        self.type = type
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case path
        case sha
        case size
        case encoding
        case content
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        sha = try container.decode(String.self, forKey: .sha)
        size = try container.decode(Int.self, forKey: .size)
        encoding = try container.decodeIfPresent(String.self, forKey: .encoding)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        type = RepoContentType(
            rawType: try container.decodeIfPresent(String.self, forKey: .type)
        )
    }

    /// 服务端**明确说**内容没给（`encoding == "none"`）。
    ///
    /// ⚠️ 判据只有这一条 —— 不要写成"`content` 是空串就算没给"：
    /// 一个**真正的空文件**也回空串，而那种情况应当正常显示成空文件，
    /// 不是"内容太大、去看网页端"。空壳判定的完整规则在领域层
    /// `FileContentCodec.isContentOmitted`（切片 6.1），两处判据必须一致。
    public var isContentOmitted: Bool {
        encoding?.lowercased() == "none"
    }
}

/// `GET …/contents/{path}` 的两种**形状**。
///
/// ## ⚠️ 同一个端点，`path` 是目录时回数组、是文件时回对象
///
/// 这不是两个端点，是同一个路由的两种响应形状。选项只有两个：
///
/// 1. **让端点返回这个枚举**（本类型的做法）—— 调用方一眼看清"两种可能"，
///    且"目录里点一个文件"这条路径不会不小心用错重载；
/// 2. 拆成两个方法、各自解各自的形状 —— 但那样"该调哪个"就变成了调用方要记得的事，
///    而在 `path` 是运行时才知道的字符串时，忘了判就得到一次
///    "看着像网络错误的解码失败"。
///
/// 还有第三条路（先试数组、失败再试对象）藏在实现里，是**同一个类型内部**的事，
/// 不该泄漏成调用方的分支 —— 那正是本类型存在的意义。
public enum ContentsPayload: Sendable, Equatable {

    /// `path` 是目录 ⇒ 一页条目。
    case directory([ContentEntryDTO])

    /// `path` 是文件 ⇒ 单个文件的 payload。
    case file(RepoFileDTO)

    /// 目录条目（不是目录时为空数组 —— 调用方拿不到误导性的 `nil`）。
    public var entries: [ContentEntryDTO] {
        if case .directory(let entries) = self { return entries }
        return []
    }

    /// 单文件 payload（不是文件时为 `nil`）。
    public var file: RepoFileDTO? {
        if case .file(let file) = self { return file }
        return nil
    }
}

extension ContentsPayload: Decodable {

    /// 先按**数组**试，失败再按**对象**试。
    ///
    /// ⚠️ 顺序不能反：两种形状的字段集不重叠（数组元素没有 `encoding` / `content`），
    /// 但"对象先试"在一个目录响应上会失败得更晚、错误信息也更难读。
    /// 反过来在单文件响应上试数组是**立刻**失败的，所以数组放前面。
    ///
    /// ⚠️ 两次解码用的是**同一个** `singleValueContainer` —— 它是无状态的转发，
    /// 不存在"第一次解码把游标走掉了"的问题（`JSONDecoder` 的实现如此）。
    /// 这里仍然只解一次数组：`try?` 掉了失败的那次，不会污染后续。
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let entries = try? container.decode([ContentEntryDTO].self) {
            self = .directory(entries)
            return
        }
        self = .file(try container.decode(RepoFileDTO.self))
    }
}
