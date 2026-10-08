import GitHubAPI
import GitDuoDesign
import SwiftUI

/// **分区内的失败块** —— 内容区里的一小块，**不掀翻整页**（PRD §4.4、§8.5）。
///
/// ## 为什么把它从 `RepoDetailView` 里提出来
///
/// 切片 6 时它只是本页 Commits 分区的一个 `private func`；切片 7 的 Issues / PR
/// 两段也要同一种失败块 ⇒ 三处共用。照抄三份的下场是那句
/// 「这一块加载失败」只会在其中一处被改（另外两处的用户看到的是旧话术），
/// 而它恰好是一句**用户能看到的承诺**（"重试"这个出口在不在）。
///
/// 顺带把读屏那句 hint 也收进来：原来它同时服务"整页失败"与"分区失败"两处，
/// 那种"一个函数两个调用方"的形态最容易在改动时只照顾一边。
///
/// ## 判据 #43
///
/// 它只收 `GitHubError`（数据层的错误类型，不是领域模型）+ 一个闭包 ⇒ 它不认识业务，
/// 按理可以进 `GitDuoDesign`。但它现在只有 `Features/Repo/` 里三处用，
/// 而"跨 Feature 才搬进设计包"是本项目的既有边界（`RepoTreeSection` 同理）
/// ⇒ **先留在 Feature**，等它真的被第二个 Feature 用到再说。
struct SectionFailure: View {

    let error: GitHubError

    /// 重试。**必须留这个出口**（PRD §1 设计原则 4：任何失败都有出口）。
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text(Self.title)
                .font(Theme.Font.footnote)
                .foregroundStyle(Theme.Palette.textSecondary)
            Button(Self.retry, action: onRetry)
                .font(Theme.Font.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Self.hint(for: error))
    }

    /// 分区失败的标题。
    ///
    /// ⚠️ 与整页失败的「加载失败」**不是同一句**：这句说的是"这一块没出来，
    /// 别的块还在"，而整页失败时屏幕上已经没有别的东西了。
    static let title = "这一块加载失败"

    /// 重试按钮。
    static let retry = "重试"

    /// **只说确定的那一件事**。
    ///
    /// ⚠️ 404 与无权限被 GitHub 混同（`TECH_SPEC §14`）⇒ 不得替用户断定
    /// 是"仓库不存在"还是"你没权限"，所以不在这张表里给"仓库不存在"这类话术。
    /// 整页失败（`RepoDetailView.failureState`）用的是同一张表 —— 这也是它被提到这里的原因。
    static func hint(for error: GitHubError) -> String {
        switch error {
        case .transport: "网络不可用"
        case .rateLimited: "请求过于频繁"
        case .unauthorized: "登录状态已失效"
        default: "服务暂时不可用"
        }
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.xl) {
        // 断网（`transport`）与配额（`rateLimited`）——两句话不同，读屏各有各的引导。
        SectionFailure(error: .transport(URLError(.notConnectedToInternet))) {}
        SectionFailure(error: .rateLimited(resetAt: .now.addingTimeInterval(600), isSecondary: false)) {}
        // 兜底那一档（404 与无权限被 GitHub 混同，只说"服务暂时不可用"）。
        SectionFailure(error: .notFound) {}
    }
    .padding(.horizontal, Theme.Spacing.page)
    .background(Theme.Palette.background)
}
