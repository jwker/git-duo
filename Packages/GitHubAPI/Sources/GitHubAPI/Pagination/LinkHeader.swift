import Foundation

/// `Link` 响应头的解析（RFC 8288 的一种受限形式，GitHub 的分页就靠它）。
///
/// 依据：TECH_SPEC §4.4「REST 统一用 `Link` 响应头解析 `next`」。
///
/// GitHub 返回的形状：
/// ```
/// Link: <https://api.github.com/repositories/1300192/issues?page=2>; rel="next",
///       <https://api.github.com/repositories/1300192/issues?page=4>; rel="last"
/// ```
///
/// ⚠️ **不能用 `split(",")` 切**：URL 内部完全可能出现逗号（`?q=swift,ios`、
/// `?labels=bug,help wanted`），那样切会得到一堆残缺的 URL 且**静默**少一页。
/// 所以这里按 `<…>` 的括注来分段 —— 那是唯一可靠的分隔依据。
///
/// ⚠️ 畸形头**不抛错**：分页信息坏了最多是"少翻一页"，不该让整个请求失败。
public struct LinkHeader: Sendable, Equatable {

    /// `rel` 关系名。
    public enum Relation: Sendable, Hashable {
        case next
        case prev
        case first
        case last
        /// 其余关系名（`rel` 的取值是开放的，认不出就照原样收着）
        case other(String)

        public init(rawValue: String) {
            switch rawValue.lowercased() {
            case "next":
                self = .next
            case "prev", "previous":
                self = .prev
            case "first":
                self = .first
            case "last":
                self = .last
            default:
                self = .other(rawValue)
            }
        }
    }

    private let byRelation: [Relation: URL]

    public init(_ raw: String) {
        var parsed: [Relation: URL] = [:]

        var index = raw.startIndex
        while index < raw.endIndex {
            // 一段的形状是 `<URL>; rel="next"`；段与段以 `,` 分隔。
            // 用 `<` 作为"段开始"的锚点，就自然跳过了分隔逗号与 URL 内的逗号之争。
            guard let leftAngle = raw[index...].firstIndex(of: "<"),
                  let rightAngle = raw[raw.index(after: leftAngle)...].firstIndex(of: ">")
            else { break }

            let urlString = String(raw[raw.index(after: leftAngle)..<rightAngle])

            // 该段的参数部分：从 `>` 之后到下一个 `<`（或末尾）
            let afterAngle = raw.index(after: rightAngle)
            let segmentEnd = raw[afterAngle...].firstIndex(of: "<") ?? raw.endIndex
            let parameters = raw[afterAngle..<segmentEnd]

            if let relation = LinkHeader.relation(in: parameters),
               let url = URL(string: urlString) {
                // 同一 rel 重复出现时保留**第一个** —— 不确定时以先到的为准，
                // 而不是让后一个悄悄覆盖（那会让行为依赖响应头的顺序细节）
                if parsed[relation] == nil {
                    parsed[relation] = url
                }
            }

            index = segmentEnd
        }

        self.byRelation = parsed
    }

    public subscript(_ relation: Relation) -> URL? { byRelation[relation] }

    /// 下一页；`nil` 表示已经是最后一页（GitHub 在最后一页不再返回 `rel="next"`）。
    public var next: URL? { byRelation[.next] }

    public var prev: URL? { byRelation[.prev] }
    public var first: URL? { byRelation[.first] }
    public var last: URL? { byRelation[.last] }

    public var isEmpty: Bool { byRelation.isEmpty }

    /// 从一个段的参数部分里取 `rel`。
    ///
    /// 三种写法都要认：`rel="next"`（标准）、`rel=next`（无引号，宽松解析）、`REL="NEXT"`（大小写）。
    private static func relation(in parameters: Substring) -> Relation? {
        guard let found = parameters.range(of: "rel=", options: .caseInsensitive) else { return nil }

        var value = parameters[found.upperBound...]

        if value.first == "\"" {
            value = value.dropFirst()
            guard let closing = value.firstIndex(of: "\"") else { return nil }
            value = value[..<closing]
        } else {
            // 无引号形式：取到参数分隔符为止
            let end = value.firstIndex { $0 == ";" || $0 == " " || $0 == "\t" } ?? value.endIndex
            value = value[..<end]
        }

        let name = value.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : Relation(rawValue: name)
    }
}
