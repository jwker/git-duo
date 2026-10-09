import Foundation
import Testing

@testable import GitHubAPI

/// 切片 9.1 新增的三个 DTO（`ViewerProfileDTO` / `ViewerActivityDTO` /
/// `ContributionCalendarDTO`）的解码。
///
/// ## 为什么它们现在就测（端点落在 9.2）
///
/// 与切片 8 的 `FileWriteResultDTO` 同一处置：领域层的**映射规则**要拿它们当输入，
/// 而映射规则必须进单测（App target 没有测试 target，决策 #34）
/// ⇒ DTO 随领域层一起立。这一套守的是"字段名与形状对不对"——
/// 那类错的表现是**整块解码失败**（热力图与两个计数一起没），
/// 而报错会指向一个具体字段名，排查起来不算难；真正难的是**形状对但语义错**，
/// 所以下面几条都特意用真实响应里的形状（含 `null`）来断言。
@Suite("我的页 DTO · `GET /user`（REST）")
struct ViewerProfileDTOTests {

    private func decode(_ json: String) throws -> ViewerProfileDTO {
        try GitHubJSON.decoder().decode(ViewerProfileDTO.self, from: Data(json.utf8))
    }

    @Test("完整响应：登录名 / 昵称 / 简介 / 关注者数 / 头像地址")
    func decodesFullResponse() throws {
        let dto = try decode(
            #"""
            {"login":"octocat","name":"小明","bio":"写 Swift 的","followers":126,
             "avatar_url":"https://avatars.githubusercontent.com/u/1?v=4"}
            """#
        )

        #expect(dto.login == "octocat")
        #expect(dto.name == "小明")
        #expect(dto.bio == "写 Swift 的")
        #expect(dto.followers == 126)
        #expect(dto.avatarURL == "https://avatars.githubusercontent.com/u/1?v=4")
    }

    @Test("⚠️ `name` / `bio` 是 `null` ⇒ 解成 `nil`，**不是空串**（PRD §4.17：取不到时整行不渲染）")
    func nullNameAndBioBecomeNil() throws {
        // 官方 OpenAPI 两个形状都把它们列为"必需但可为 null"——
        // 所以这不是异常响应，是很多人真实的账号样子。
        let dto = try decode(
            #"{"login":"octocat","name":null,"bio":null,"followers":3}"#
        )

        #expect(dto.name == nil)
        #expect(dto.bio == nil)
        #expect(dto.followers == 3, "`followers` 与它们无关，照常解出来")
        #expect(dto.avatarURL == nil, "`avatar_url` 缺席同样是 `nil`（不是空串）")
    }

    @Test("⚠️ `avatar_url` 收的是**原样字符串**：缺席 / `null` ⇒ `nil`，空串**原样保留**")
    func avatarURLStaysRawString() throws {
        // 这一条钉的是 DTO 那一侧的**类型选择**：它收 `String?` 而不是 `URL?`
        // （理由见 `ViewerProfileDTO` 的说明 —— 同一份响应里 `gravatar_id` 真的会发空串，
        //  而空串对 `URL` 解码会抛错、连带整条 `/user` 失败）。
        // ⚠️ 空串**在这里不是 `nil`**（DTO 只做原样收），收窄发生在下一个注释点名的那一步。
        #expect(try decode(#"{"login":"a","name":null,"bio":null,"followers":0}"#).avatarURL == nil)
        #expect(
            try decode(#"{"login":"a","name":null,"bio":null,"followers":0,"avatar_url":null}"#).avatarURL
                == nil
        )
        #expect(
            try decode(#"{"login":"a","name":null,"bio":null,"followers":0,"avatar_url":""}"#).avatarURL
                == "",
            "空串原样收下来，「空串 → 没有头像」是 `ProfileMapper.avatarURL(from:)` 的事"
        )
    }

    @Test("⚠️ 少了 `followers` ⇒ 解码失败（不许静默当成 0）")
    func missingFollowersFailsDecoding() {
        // "0 个关注者"与"这一项没拿到"在界面上必须不同 —— 填 0 会让用户
        // 以为自己一个关注者都没有。所以它是必需的：真缺了就整块降级。
        #expect(throws: (any Error).self) {
            try self.decode(#"{"login":"octocat","name":"小明","bio":null}"#)
        }
    }

    @Test("多余的字段（`public_repos` / `total_private_repos` / …）被忽略，不影响解码")
    func unknownFieldsAreIgnored() throws {
        // ⚠️ 本条**原来拿 `avatar_url` 当"多余字段"的例子**，理由写的是"本类型有意不声明它"。
        // 那个理由已于 2026-10-09 作废（用户走查报回 #1 ⇒ 偏差第 43 条），
        // 于是例子换成一个**真的不声明**的字段。⚠️ 这一步值得记：一条测试用例
        // 可以**因为被测的规格变了而变成在守一句错话** —— 它照样会绿。
        let dto = try decode(
            #"""
            {"login":"octocat","name":"小明","bio":null,"followers":1,
             "public_repos":42,"total_private_repos":7,"created_at":"2011-01-25T18:44:36Z"}
            """#
        )

        #expect(dto.login == "octocat")
        #expect(dto.followers == 1)
    }
}

/// 一次 GraphQL 查询的三个字段（`viewer.contributionsCollection` + 两个 `totalCount`）。
@Suite("我的页 DTO · GraphQL `viewer`（活动 + 两个计数）")
struct ViewerActivityDTOTests {

    /// 取自真实响应形状：`weeks` 是数组、`contributionDays` 是数组，
    /// 头尾两周可能不足 7 天。
    private let json = #"""
    {
      "contributionsCollection": {
        "contributionCalendar": {
          "totalContributions": 1024,
          "weeks": [
            {
              "firstDay": "2026-01-01",
              "contributionDays": [
                {"date":"2026-01-01","contributionCount":0,"contributionLevel":"NONE","weekday":4},
                {"date":"2026-01-02","contributionCount":3,"contributionLevel":"SECOND_QUARTILE","weekday":5}
              ]
            },
            {
              "firstDay": "2026-01-04",
              "contributionDays": [
                {"date":"2026-01-04","contributionCount":7,"contributionLevel":"FOURTH_QUARTILE","weekday":0},
                {"date":"2026-01-05","contributionCount":1,"contributionLevel":"FIRST_QUARTILE","weekday":1},
                {"date":"2026-01-06","contributionCount":2,"contributionLevel":"SECOND_QUARTILE","weekday":2},
                {"date":"2026-01-07","contributionCount":5,"contributionLevel":"THIRD_QUARTILE","weekday":3},
                {"date":"2026-01-08","contributionCount":0,"contributionLevel":"NONE","weekday":4},
                {"date":"2026-01-09","contributionCount":1,"contributionLevel":"FIRST_QUARTILE","weekday":5},
                {"date":"2026-01-10","contributionCount":9,"contributionLevel":"FOURTH_QUARTILE","weekday":6}
              ]
            }
          ]
        }
      },
      "starredRepositories": {"totalCount": 318},
      "repositories": {"totalCount": 42}
    }
    """#

    private func decode() throws -> ViewerActivityDTO {
        try GitHubJSON.decoder().decode(ViewerActivityDTO.self, from: Data(json.utf8))
    }

    @Test("三个字段一次解出来：日历 + Star 计数 + 仓库计数")
    func decodesAllThreeFields() throws {
        let dto = try decode()

        #expect(dto.contributionsCollection.contributionCalendar.totalContributions == 1_024)
        #expect(dto.starredRepositories.totalCount == 318)
        #expect(dto.repositories.totalCount == 42)
    }

    @Test("`weeks` / `contributionDays` 都是**数组**（不是连接）⇒ 解出来是有序的嵌套数组")
    func weeksAreNestedArrays() throws {
        let weeks = try decode().contributionsCollection.contributionCalendar.weeks

        #expect(weeks.count == 2)
        // 头尾两周不足 7 天是**正常形状**（日历周是周日对齐的，一年这个窗口不会正好对齐）。
        #expect(weeks[0].contributionDays.count == 2)
        #expect(weeks[1].contributionDays.count == 7)
        #expect(weeks[0].firstDay == "2026-01-01")
    }

    @Test("⚠️ `date` 是 `Date` 标量（形如 `2026-01-04`）但**原样留成字符串**")
    func dateIsKeptAsAString() throws {
        // 转成 `Date` 就必须替服务端选一个时区，选错会让某些时区下整体偏移一天，
        // 而图上看起来完全正常。所以这里断言的是"它就是那串字"。
        let days = try decode().contributionsCollection.contributionCalendar.weeks[1].contributionDays

        #expect(days[0].date == "2026-01-04")
        #expect(days[6].date == "2026-01-10")
    }

    @Test("每一格四个字段都在：`contributionCount` / `contributionLevel` / `weekday`")
    func everyDayCarriesItsFourFields() throws {
        let day = try decode().contributionsCollection.contributionCalendar.weeks[1].contributionDays[0]

        #expect(day.contributionCount == 7)
        #expect(day.contributionLevel == "FOURTH_QUARTILE")
        #expect(day.weekday == 0)
    }

    @Test("⚠️ 认不出的 `contributionLevel` **照样能解**（声明成 `String` 而不是枚举）")
    func unknownLevelStillDecodes() throws {
        // 枚举化之后 GitHub 哪天多一档，表现就是**整张卡片解码失败** ——
        // 而这一格里"档位不准"远好过"整块没有"。翻译与兜底在领域层（`ContributionLevel`）。
        let json = #"""
        {"contributionsCollection":{"contributionCalendar":{"totalContributions":1,"weeks":[
          {"firstDay":"2026-01-01","contributionDays":[
            {"date":"2026-01-01","contributionCount":1,"contributionLevel":"FIFTH_QUARTILE","weekday":4}
          ]}
        ]}},"starredRepositories":{"totalCount":0},"repositories":{"totalCount":0}}
        """#

        let dto = try GitHubJSON.decoder().decode(ViewerActivityDTO.self, from: Data(json.utf8))
        #expect(dto.contributionsCollection.contributionCalendar.weeks[0].contributionDays[0]
            .contributionLevel == "FIFTH_QUARTILE")
    }

    @Test("空日历（新账号 / 服务端给了个空数组）⇒ 解出来是空数组，不是失败")
    func emptyCalendarDecodesToEmptyArrays() throws {
        let json = #"""
        {"contributionsCollection":{"contributionCalendar":{"totalContributions":0,"weeks":[]}},
         "starredRepositories":{"totalCount":0},"repositories":{"totalCount":0}}
        """#

        let dto = try GitHubJSON.decoder().decode(ViewerActivityDTO.self, from: Data(json.utf8))

        #expect(dto.contributionsCollection.contributionCalendar.weeks.isEmpty)
        #expect(dto.contributionsCollection.contributionCalendar.totalContributions == 0)
    }

    @Test("⚠️ 少了 `repositories` 那个计数 ⇒ 整块解码失败（**不静默给 0**）")
    func missingCounterFailsDecoding() {
        // 两个计数同属一次往返：少一个说明查询文本或服务端形状变了。
        // 静默给 0 的表现是"我的页说我有 0 个仓库"，而仓库列表里明明有几十个。
        let json = #"""
        {"contributionsCollection":{"contributionCalendar":{"totalContributions":0,"weeks":[]}},
         "starredRepositories":{"totalCount":0}}
        """#

        #expect(throws: (any Error).self) {
            try GitHubJSON.decoder().decode(ViewerActivityDTO.self, from: Data(json.utf8))
        }
    }

    @Test("`totalCount` 大数照常（`StarredRepositoryConnection.isOverLimit` 的截断发生在服务端）")
    func largeCountsDecode() throws {
        let json = #"""
        {"contributionsCollection":{"contributionCalendar":{"totalContributions":0,"weeks":[]}},
         "starredRepositories":{"totalCount":123456},"repositories":{"totalCount":9999}}
        """#

        let dto = try GitHubJSON.decoder().decode(ViewerActivityDTO.self, from: Data(json.utf8))

        #expect(dto.starredRepositories.totalCount == 123_456)
        #expect(dto.repositories.totalCount == 9_999)
    }
}
