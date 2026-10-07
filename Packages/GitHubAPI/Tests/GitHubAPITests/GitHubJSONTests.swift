import Foundation
import Testing

@testable import GitHubAPI

/// 统一解码器与日期解析 —— TECH_SPEC §4.6（本包所有带时间戳的端点的公共前提）。
///
/// 这一套测试保护的是一个**很容易被"优化"掉、且症状极难定位**的东西：
/// `JSONDecoder` 的默认日期策略要的是"距 2001 年的秒数"，而 GitHub 给的是 ISO 8601 字符串。
/// 一旦有人把某个端点的解码器换回裸 `JSONDecoder()`，症状不是"日期错了"，
/// 而是**那一页整页拿不到内容**，报错还指向一个具体字段名。
@Suite("GitHubJSON · 统一解码器与 GitHub 时间戳")
struct GitHubJSONTests {

    private struct Stamped: Decodable, Sendable, Equatable {
        let createdAt: Date

        private enum CodingKeys: String, CodingKey {
            case createdAt = "created_at"
        }
    }

    private func decodeDate(_ text: String) throws -> Date {
        let json = #"{"created_at":"\#(text)"}"#
        return try GitHubJSON.decoder().decode(Stamped.self, from: Data(json.utf8)).createdAt
    }

    // MARK: - 两种形状都要认

    @Test("常规形状：2026-08-05T09:00:00Z")
    func parsesPlainTimestamp() throws {
        // 硬编码秒数（而不是拿另一个解析器算），这样"两个实现一起错"不会被漏掉。
        // 2026-08-05T09:00:00Z = 1785920400
        #expect(try decodeDate("2026-08-05T09:00:00Z").timeIntervalSince1970 == 1_785_920_400)
    }

    @Test("带小数秒：2026-08-05T12:34:56.789Z（`.iso8601` 会在这里失败）")
    func parsesFractionalSeconds() throws {
        // 2026-08-05T12:34:56Z = 1785933296
        let parsed = try decodeDate("2026-08-05T12:34:56.789Z")
        #expect(parsed.timeIntervalSince1970 == 1_785_933_296.789)
    }

    @Test("带时区偏移：+08:00 表示的是同一时刻，而不是「少八小时」")
    func parsesTimezoneOffset() throws {
        // 2026-08-05T12:34:56+08:00 == 2026-08-05T04:34:56Z = 1785904496
        #expect(try decodeDate("2026-08-05T12:34:56+08:00").timeIntervalSince1970 == 1_785_904_496)
    }

    @Test("两种形状解出来的是**同一时刻**（小数秒只影响精度）")
    func fractionalAndPlainAgree() throws {
        let plain = try decodeDate("2026-08-05T12:34:56Z")
        let fractional = try decodeDate("2026-08-05T12:34:56.000Z")
        #expect(plain == fractional)
    }

    // MARK: - 坏输入：失败而不是崩，也不是默默给个错值

    @Test("不是时间戳 ⇒ decoding 失败（绝不静默当成 1970 或当前时间）")
    func rejectsNonTimestamp() throws {
        #expect(throws: (any Error).self) {
            try decodeDate("昨天")
        }
    }

    @Test("空字符串 ⇒ decoding 失败")
    func rejectsEmptyString() throws {
        #expect(throws: (any Error).self) {
            try decodeDate("")
        }
    }

    @Test("字段是数字而不是字符串 ⇒ decoding 失败（形状不符要说出来）")
    func rejectsNumericTimestamp() throws {
        let json = #"{"created_at":1785920400}"#
        #expect(throws: (any Error).self) {
            try GitHubJSON.decoder().decode(Stamped.self, from: Data(json.utf8))
        }
    }

    // MARK: - 键名不做隐式转换

    @Test("不做 snake_case 自动转换：`created_at` 必须由 DTO 自己的 CodingKeys 声明")
    func doesNotConvertKeyCase() throws {
        // 上面 `Stamped` 写了 CodingKeys，所以能解。这里故意用一个**没写** CodingKeys
        // 的形状：它必须失败 —— 否则"某个键没转过来"会变成"字段静默为 nil"，
        // 而不是一个能看见的错误。
        struct Uncased: Decodable, Sendable {
            let createdAt: Date
        }
        let json = #"{"created_at":"2026-08-05T09:00:00Z"}"#

        #expect(throws: (any Error).self) {
            try GitHubJSON.decoder().decode(Uncased.self, from: Data(json.utf8))
        }
    }

    // MARK: - `HTTPResponse.decode` 确实用的是它（接线回归）

    @Test("HTTPResponse.decode 走的是统一解码器（换回裸 JSONDecoder 会在这里红）")
    func responseDecodeUsesSharedDecoder() throws {
        let response = HTTPResponse(
            statusCode: 200,
            headers: HTTPHeaders([:]),
            body: Data(#"{"created_at":"2026-08-05T09:00:00Z"}"#.utf8),
            isFromCache: false
        )

        let stamped = try response.decode(Stamped.self)

        #expect(stamped.createdAt.timeIntervalSince1970 == 1_785_920_400)
    }

    // MARK: - 空结构体（两个 DTO 依赖它）

    @Test("空结构体能从 JSON **对象**解出（`RepoReleaseDTO.Asset` 与 `PullRequestMarker` 依赖这条）")
    func emptyStructDecodesFromObject() throws {
        struct Marker: Decodable, Sendable {}

        // 这两个类型只关心"字段在不在"或"有几个"，所以不声明任何属性。
        // 这条性质来自编译器合成的 `init(from:)`（零属性 = 不读任何键），
        // **没有任何文档承诺它**，所以用测试把它钉住 ——
        // 一旦哪天它变了，症状会是"版本卡片整块没了 / Issue 列表把 PR 也当成 Issue"，
        // 都属于很难一眼看出根因的那种。
        let markers = try GitHubJSON.decoder().decode([Marker].self, from: Data(#"[{},{"a":1}]"#.utf8))
        #expect(markers.count == 2)

        let assets = try GitHubJSON.decoder().decode(
            [RepoReleaseDTO.Asset].self,
            from: Data(#"[{"name":"a.zip","size":12},{"name":"b.zip","size":34}]"#.utf8)
        )
        #expect(assets.count == 2)
    }

    @Test("空数组 ⇒ 零个元素（不是解码失败）")
    func emptyArrayDecodes() throws {
        let assets = try GitHubJSON.decoder().decode(
            [RepoReleaseDTO.Asset].self,
            from: Data("[]".utf8)
        )
        #expect(assets.isEmpty)
    }
}
