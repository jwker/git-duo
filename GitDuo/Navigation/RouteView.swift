import SwiftUI

/// `Route` → 具体页面。
///
/// 骨架期：**每个 case 都必须出现在 switch 中**（穷尽枚举），未落地的分支显示占位屏。
/// 这样做的好处：切片推进时**编译器的穷尽性检查会盯住每一处**——
/// 新增一个 `Route` case 而忘记接线，构建即失败，不会静默漏页。
struct RouteView: View {

    let route: Route

    var body: some View {
        switch route {
        case .search:
            SkeletonScreen(title: "搜索", slice: "切片 5 落地", reference: "PRD §4.2 / TECH_SPEC §9.11")
        case let .repoDetail(fullName, section, _):
            SkeletonScreen(title: "仓库详情 · \(fullName)", slice: "切片 4 落地", reference: "PRD §4.16 · 分区 \(section.rawValue)")
        case let .exploreRepoDetail(fullName, _):
            SkeletonScreen(title: "探索仓库详情 · \(fullName)", slice: "切片 4 落地", reference: "PRD §4.17（他人仓库 · 只读）")
        case let .fileView(fullName, path, readOnly):
            SkeletonScreen(title: "文件查看 · \(path)", slice: "切片 6 落地", reference: "PRD §4.18 · \(fullName) · 只读=\(readOnly)")
        case let .editor(fullName, path, mode):
            SkeletonScreen(title: "编辑器 · \(path ?? "新文件")", slice: "切片 8 落地", reference: "PRD §4.20 · \(fullName) · 模式=\(mode)")
        case let .commitDetail(fullName, sha, readOnly):
            SkeletonScreen(title: "提交详情 · \(sha.prefix(7))", slice: "切片 6 落地", reference: "PRD §4.7 · \(fullName) · 只读=\(readOnly)")
        case let .branches(fullName):
            SkeletonScreen(title: "分支管理", slice: "切片 6 落地", reference: "PRD §4.6 / TECH_SPEC §9.4.1 · \(fullName)")
        case let .issueDetail(fullName, number):
            SkeletonScreen(title: "Issue #\(number)", slice: "切片 7 落地", reference: "PRD §4.8 · \(fullName)")
        case let .newIssue(fullName):
            SkeletonScreen(title: "新建 Issue", slice: "切片 7 落地", reference: "PRD §4.9 · \(fullName)")
        case let .prDetail(fullName, number, readOnly):
            SkeletonScreen(title: "PR #\(number)", slice: "切片 7 落地", reference: "PRD §4.11 · \(fullName) · 只读=\(readOnly)")
        case let .exploreIssueList(fullName):
            SkeletonScreen(title: "探索 Issues", slice: "切片 4 落地", reference: "PRD §4.17 · \(fullName)")
        case let .explorePRList(fullName):
            SkeletonScreen(title: "探索 Pull Requests", slice: "切片 4 落地", reference: "PRD §4.17 · \(fullName)")
        case .stars:
            SkeletonScreen(title: "我的 Star", slice: "切片 9 落地", reference: "PRD §4.13")
        case .folders:
            SkeletonScreen(title: "我的收藏", slice: "切片 9 落地", reference: "PRD §4.19 · 纯本地，零请求")
        case .settings:
            SkeletonScreen(title: "设置", slice: "切片 9 落地", reference: "PRD §4.20")
        }
    }
}

#Preview {
    NavigationStack {
        RouteView(route: .settings)
    }
}
