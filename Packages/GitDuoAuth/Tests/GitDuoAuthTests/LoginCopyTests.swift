import Foundation
import Testing

@testable import GitDuoAuth

/// 登录页文案的规格 —— 把原型 jsdom 回归里"登录段"的断言在 Swift 侧重述一遍。
///
/// 依据：REVIEW-CHECKLIST §4（断言 → 切片映射：登录段 → 切片 1）、
///      TECH_SPEC §3.4（权限清单）、§3.5.4（安装范围）、PRD §4.0.1。
///
/// 为什么值得单独测：这几句是**产品对用户的承诺**，而承诺最容易在"改实现"时悄悄失效
/// ——原型阶段就出过一次（文案承诺撤销授权，实现却做不到）。现在实现做得到了，
/// 于是要有一处地方能守住"文案与实现同时成立"。
@Suite("登录页文案 · 权限预告与安全说明")
struct LoginCopyTests {

    private static let expectedTitles = [
        "仓库内容", "Issues", "Pull Requests", "Star 收藏", "关注关系", "账号基本信息"
    ]

    @Test("权限预告恰好 6 项，且就是 TECH_SPEC §3.4 那六项")
    func permissionListIsComplete() {
        let titles = AuthPermission.all.map(\.title)
        #expect(titles == Self.expectedTitles)
        #expect(Set(titles).count == titles.count, "标题是条目的 id，重复会让 ForEach 渲染错乱")
    }

    @Test("每项权限都有标题与说明 —— 空条目在界面上就是一行空白")
    func permissionCopyIsNotEmpty() {
        for permission in AuthPermission.all {
            #expect(!permission.title.isEmpty)
            #expect(!permission.detail.isEmpty)
            #expect(!permission.symbol.isEmpty, "\(permission.title) 缺图标名")
        }
    }

    @Test("账号级权限（Star / 关注）必须写明是读写 —— 缺了会 403，不是可有可无")
    func accountLevelPermissionsAreMarkedWritable() throws {
        let star = try #require(AuthPermission.all.first { $0.title == "Star 收藏" })
        let follow = try #require(AuthPermission.all.first { $0.title == "关注关系" })
        #expect(star.detail.contains("读写"))
        #expect(follow.detail.contains("读写"))
    }

    @Test("三项安全说明齐全，各自点到位：系统浏览器 / Keychain / All repositories")
    func disclosureIsComplete() {
        #expect(AuthDisclosure.allCases.count == 3)
        #expect(AuthDisclosure.passwordNeverSeen.text.contains("系统浏览器"))
        #expect(AuthDisclosure.tokenStorageAndRevocation.text.contains("Keychain"))
        #expect(AuthDisclosure.installScope.text.contains("All repositories"))
    }

    @Test("登出承诺必须是「同时撤销 GitHub 侧授权」—— 这是实现真做得到的事（§3.6）")
    func disclosurePromisesRevocation() {
        // 该承诺在决策 #30 之前是**做不到**的（客户端不持 secret ⇒ 无法调撤销端点），
        // 文案却已经写下，属"承诺大于实现"。现在两者都成立，别让任何一边退回去。
        #expect(AuthDisclosure.tokenStorageAndRevocation.text.contains("撤销"))
    }

    @Test("登录页不得复述「客户端不持有 client secret」—— D4 决策后该表述已被推翻")
    func disclosureDoesNotRepeatTheOverturnedClaim() {
        for disclosure in AuthDisclosure.allCases {
            #expect(!disclosure.text.contains("不持有"))
            #expect(!disclosure.text.contains("client secret"))
        }
    }
}
