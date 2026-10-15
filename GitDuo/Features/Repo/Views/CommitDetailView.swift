import GitHubAPI
import GitDuoDesign
import GitDuoKit
import SwiftUI

/// 提交详情页（PRD §4.7、原型 `SCR.commitDetail`、TECH_SPEC §9.7 / §11.2）。
///
/// 结构：头部卡（标题 + 正文 + `{作者} 提交于 {时间} · {短SHA} · {N} 个文件 · +a −d`）
/// → 每个改动文件一张 `DiffCard` → 底部（自己的仓库是 Revert，他人仓库是一句页脚）。
///
/// ## ⚠️ 展开 / 折叠不在这张视图里，也不在它的 ViewModel 里
///
/// §11.2 的「按需解析」整个落在 `DiffCard` 自己的 `@State`（6.3 已交付）。
/// 本页只把 `model.files` 交给卡片，**不持有**任何解析结果 ——
/// 同一件事有两份实现时，领域层加一档只有一份会被告知（`DiffCard` 的类型说明）。
///
/// ## ⚠️ Revert 只给出口，不假装能做
///
/// GitHub 的公开 API **没有回滚端点**（网页端的 Revert 是服务端内部能力），
/// 客户端自行实现要逐层构造反向提交、且合并提交存在主线歧义 ⇒ 本期不做（§9.7.3）。
/// 所以它做的是两件事：给一句说明，并**打开网页端的这个提交**。
/// 点了只弹一句"请去网页端"属于 PRD §8.1 明令禁止的"停留在入口或提示"——
/// 与「置顶管理」跳网页端同一处置模式（§9.1）。
///
/// ## ⚠️ 两处「规格未给，待评审」（本片新增，已登记）
///
/// 1. **提交信息正文的样式**：原型这一屏只渲染标题（`p.m`），没有正文那一段
///    （它的演示数据里提交信息都是单行）。而 `CommitDetail.message` 的说明写着
///    "详情页显示整段" ⇒ 正文要画，但画成什么样没有依据。取"次级文字色 + footnote"
///    （与仓库描述同一档），不新造字号与颜色。
/// 2. **`files` 为空时的样子**：原型永远有 diff ⇒ 这一档不存在。
///    取 `EmptyBox`（与 §4.4 分区四"还没有提交"同一形态）。
struct CommitDetailView: View {

    let fullName: String
    let sha: String
    let readOnly: Bool

    @Environment(\.openURL) private var openURL

    @State private var model: CommitDetailViewModel

    /// 「现在」只在**进页与刷新时**取一次（同 `RepoDetailView` / `ExploreRepoDetailView`）——
    /// 在 `body` 里取 `Date()` 会让"相对时间"变成渲染时机的一部分。
    @State private var now = Date()

    /// Revert 那句提示要它。⚠️ 与 ViewModel 持有的是**同一个** `ToastCenter`
    /// （组合根只造一个），所以两处引用不会变成两个通道。
    private let toast: ToastCenter

    init(
        fullName: String,
        sha: String,
        readOnly: Bool,
        loader: LoadRepoCommits,
        toast: ToastCenter
    ) {
        self.fullName = fullName
        self.sha = sha
        self.readOnly = readOnly
        self.toast = toast
        _model = State(initialValue: CommitDetailViewModel(
            fullName: fullName,
            sha: sha,
            readOnly: readOnly,
            loader: loader,
            toast: toast
        ))
    }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Theme.Palette.background)
        // 原型 `SCR.commitDetail` 的 `inline:p=>p.s` —— 导航栏上就是短哈希。
        .navigationTitle(shortSHA)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            now = Date()
            await model.refresh()
            now = Date()
        }
        .task {
            now = Date()
            await model.start()
            // 取完之后再对一次表：网速慢时"2 天前"可能已经跨过了一个整点。
            now = Date()
        }
    }

    /// 短哈希。⚠️ 与徽章共用 `CommitSummary.shortSHALength` 一个常量
    /// —— 两处各写一个 `7` 时，改了其中一处就会出现"导航栏 7 位、徽章 8 位"。
    private var shortSHA: String {
        String(sha.prefix(CommitSummary.shortSHALength))
    }

    // MARK: - 主区域

    @ViewBuilder
    private var content: some View {
        switch model.detail.presentation {
        case .skeleton:
            skeleton

        case .content:
            if let detail = model.detail.value {
                // 原型 `.conv-head{margin-bottom:12px}` 与 `.diffcard{margin-bottom:12px}`
                // ⇒ 三块之间同一个间距。
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    header(detail)
                    files(detail)
                    footer
                }
            }

        case let .failure(error):
            failureState(error)
        }
    }

    // MARK: - 头部卡

    private func header(_ detail: CommitDetail) -> some View {
        // 原型 `.conv-head{background:var(--card);border:1px solid var(--border-soft);
        //                  border-radius:14px;padding:15px}`。
        CardBox() {
            VStack(alignment: .leading, spacing: 0) {
                Text(detail.headline)
                    // 原型 `.conv-head h2{font-size:17.5px;font-weight:720}` ⇒
                    // 最近的一档是 `headline`（17 + semibold）。
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // 正文：没有就整块不渲染（渲染一个空盒子更糟）。
                // ⚠️ 样式是「规格未给」——见类型说明第 1 条。
                if let body = detail.body, !body.isEmpty {
                    Text(body)
                        .font(Theme.Font.footnote)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Theme.Spacing.s)
                }

                // 原型 `h2{margin:8px 0}` ⇒ 标题与这一行之间 8pt。
                metaLine(detail)
                    .padding(.top, Theme.Spacing.s)
            }
        }
    }

    /// `{作者} 提交于 {时间} · [短SHA] · {N} 个文件 · +a −d`（原型逐字，SHA 是徽章）。
    ///
    /// ⚠️ 走 `FlowLayout` 而不是 `HStack`：`HStack` 放不下会**压缩**
    /// （作者名长一点就会把"1 个文件 · +12 −4"截成 `1 个…`），
    /// 而原型是行内流式内容、放不下就换行（与 `BreadcrumbBar` 的路径段同一处置）。
    ///
    /// ⚠️ 三段文字**都由领域层给**：`authorLine(now:)` / `statsLabel` / `shortSHA`
    /// —— 本件不拼任何一个字，也不自己算"N 个文件"。
    private func metaLine(_ detail: CommitDetail) -> some View {
        FlowLayout(spacing: 0, lineSpacing: Theme.Spacing.xxs) {
            Text(detail.authorLine(now: now))
            Text(" · ")
            SHABadge(sha: detail.shortSHA)
                .accessibilityLabel(CommitCopy.shaAccessibilityLabel(shortSHA: detail.shortSHA))
            Text(" · ")
            Text(detail.statsLabel)
        }
        // 原型 `.t3{font-size:11.5px;color:var(--text3)}`（徽章自带字号与颜色，不受这一层影响）。
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.Palette.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 改动文件

    @ViewBuilder
    private func files(_ detail: CommitDetail) -> some View {
        if detail.files.isEmpty {
            // ⚠️ 它**不是**"加载中"：空的 `files[]` 是服务端给的一个确定结果
            //    （初始提交之外的少数提交，或某个中间层吞掉了这个字段）。
            //    什么都不画会让整页看起来像少了一块。
            EmptyBox(title: CommitCopy.noFilesNotice)
        } else {
            // ⚠️ 顺序即 `model.files` 的顺序（= 服务端的 `files[]`），本页不重排。
            ForEach(detail.files) { file in
                // 原型是 `diffcard open` ⇒ 默认展开（`DiffCard` 的默认值就是它）。
                DiffCard(file: file)
            }
        }
    }

    // MARK: - 底部

    /// 自己的仓库 ⇒ Revert 按钮；他人仓库 ⇒ 一句页脚（§4.7 的权限差异）。
    @ViewBuilder
    private var footer: some View {
        if readOnly {
            Text(CommitCopy.readOnlyFooter)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(maxWidth: .infinity)
        } else {
            // 原型 `style="width:100%;padding:12px"`。
            ActionButton(
                title: CommitCopy.revertAction,
                style: .ghost,
                verticalPadding: 12
            ) {
                revert()
            }
        }
    }

    /// Revert —— 给一句说明 + 打开网页端（见类型说明）。
    ///
    /// ⚠️ 顺序是**先出提示、再开浏览器**：`openURL` 会把 App 切到后台，
    /// 而提示是挂在本 App 上的 —— 先开浏览器的话，那句话会在用户切回来时才看到，
    /// 或者根本看不到（长时间后再回来，提示已经过期）。
    private func revert() {
        toast.show(CommitCopy.revertToast)
        guard let url = model.webURL else { return }
        openURL(url)
    }

    // MARK: - 骨架 / 失败

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            CardBox() {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SkeletonBar(height: 17, width: 240)
                    SkeletonBar(height: 11, width: 180)
                }
            }

            ForEach(0..<2, id: \.self) { _ in
                // 与 `DiffCard` 同形状：一行文件名 + 若干 diff 行。
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SkeletonBar(height: 13, width: 220)
                    SkeletonBar(height: 11, width: 260)
                    SkeletonBar(height: 11, width: 200)
                }
                .padding(Theme.Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                // 方案 A：diff 卡是**白卡**（与 `DiffCard` 一致：圆角 18、无边框）。
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous)
                        .fill(Theme.Palette.surface)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.cardLarge, style: .continuous))
            }
        }
        .accessibilityHidden(true)
    }

    /// 首屏失败 —— 必须留一个出口（PRD §1 设计原则 4）。
    ///
    /// ⚠️ 走共用件 `PageFailure`（切片 7.4 收口）：本页原来那份与
    /// `RepoDetailView` / `BranchesView` 的**逐字相同**。
    private func failureState(_ error: GitHubError) -> some View {
        PageFailure(error: error) { Task { await model.refresh() } }
    }
}

#Preview {
    @Previewable @State var environment = AppEnvironment()
    NavigationStack {
        CommitDetailView(
            fullName: "my-git/gitduo",
            sha: "a1b2c3d4e5f6a7b8c9d0",
            readOnly: false,
            loader: environment.repoCommits,
            toast: environment.toast
        )
    }
    .environment(environment)
}
