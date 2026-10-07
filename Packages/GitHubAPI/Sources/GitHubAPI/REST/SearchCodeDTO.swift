import Foundation

/// 代码搜索结果 —— `GET /search/code` 的 `items` 元素（TECH_SPEC §4.6.1、§9.2、PRD §4.2）。
///
/// ## 它比别的搜索结果多一个前提：要带 `text-match` 媒体类型
///
/// `text_matches`（命中的那几行原文）**只在请求带**
/// `Accept: application/vnd.github.text-match+json` 时返回（§9.2）。
/// 不带也照样 200，只是没有它 —— 所以这里的 `textMatches` 是**可选**的，
/// 而 `CodeHit.snippet` 为 `nil` 的卡片**不渲染那一行**，不显示空框。
///
/// ## ⚠️ `language` 也是可选的
///
/// 官方 OpenAPI 的 `code-search-result-item` 把它列为 `string | null`，
/// 但官方文档的 200 示例里没有这个字段 —— 与 `SearchUserDTO` 同一情形，
/// 一律按可选处理，缺失时卡片副标题**整段去掉语言**（见 `CodeHit.metaLabel`）。
///
/// ⚠️ **不取 `repository` 的整个对象**：只需要 `full_name` 一个字符串，
/// 而 Minimal Repository 有六十来个字段 —— 多解一个字段就多一处会因为它的形状变化而炸的地方。
public struct SearchCodeDTO: Sendable, Equatable, Decodable {

    /// 文件在仓库里的路径（原型 `c.p`）。
    public let path: String

    /// 语言。**可以是 `null`**（GitHub 认不出的文件类型，见类型说明）。
    public let language: String?

    /// 所属仓库 —— 只取 `full_name`。
    public let repository: Repository

    /// 命中片段（原型 `.sr-code` 里那一行）。**不带 `text-match` 媒体类型时为 `nil`**。
    public let textMatches: [TextMatch]?

    public init(
        path: String,
        language: String? = nil,
        repository: Repository,
        textMatches: [TextMatch]? = nil
    ) {
        self.path = path
        self.language = language
        self.repository = repository
        self.textMatches = textMatches
    }

    public struct Repository: Sendable, Equatable, Decodable {
        public let fullName: String

        public init(fullName: String) {
            self.fullName = fullName
        }

        private enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
        }
    }

    /// 一处命中。只需要 `fragment`（命中所在的那段原文）。
    ///
    /// ⚠️ `fragment` 声明成**可选**：它是多行原文，官方 schema 把它标为必需，
    /// 但真缺了的时候"整页解不出"远比"这一行没有预览"糟糕。
    public struct TextMatch: Sendable, Equatable, Decodable {
        public let fragment: String?

        public init(fragment: String? = nil) {
            self.fragment = fragment
        }
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case language
        case repository
        case textMatches = "text_matches"
    }
}
