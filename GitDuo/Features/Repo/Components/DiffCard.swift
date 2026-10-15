import GitDuoDesign
import GitDuoKit
import SwiftUI

/// **diff 卡片** —— 提交详情 / PR 详情里每个改动文件一张（TECH_SPEC §11.2）。
///
/// 原型 `scripts/08-pr.js` 的 `diffCard(file, add, del, body)` 与
/// `styles/04-screens.css` 的 `.diffcard` 一族：
///
/// ```css
/// /* 2026-10-15 方案 D 起（走查第 73 条）：容器去形 —— add/del 行底色本身构成形状 */
/// .diffcard{background:none;border:none;border-radius:0;overflow:hidden;margin-bottom:12px}
/// .diffcard .dhead{display:flex;align-items:center;gap:8px;padding:10px 12px;
///                  border-bottom:1px solid var(--border-soft);cursor:pointer}
/// .diffcard .dhead .fn{font-family:Menlo,monospace;font-size:12.5px;font-weight:600;color:var(--text)}
/// .dstat{font-size:11px;font-weight:700}
/// .dstat.add{color:var(--add-tx)}  .dstat.del{color:var(--del-tx)}
/// .diffcard .dbody{display:none}   .diffcard.open .dbody{display:block}
/// ```
///
/// 原型里卡片是 `class="diffcard open"` ⇒ **默认展开**。
///
/// ## ⚠️ 它收领域模型 ⇒ 留 Feature（判据 #43）
///
/// 入参是 `FileChange`（领域模型）⇒ 不进 `GitDuoDesign`。
/// 设计包里只有 `DiffRow`（"一行长什么样"，只收 `number` / `text` / `tone` 三个基础类型）。
///
/// ## ⚠️ 展开才解析（§11.2 的"按需解析"，不是顺手优化）
///
/// `UnifiedDiffParser` 是纯函数、无缓存，所以"按需"只能由调用方保证。
/// 一个数百文件的 PR 若一上来把每段 `patch` 都解析一遍，
/// 那几百段文本都要走一趟字符扫描 —— 而用户可能一个都没展开。
/// 所以这里把解析结果**存在 `@State` 里**，只在**展开的那一刻**填一次：
/// 既兑现了"折叠不解析"，也避免展开状态下每次重绘都重扫一遍（`body` 会被反复求值）。
struct DiffCard: View {

    let file: FileChange

    @State private var isExpanded: Bool

    /// 展开后解析出来的 hunk。**折叠状态下恒为空**（没解析过）。
    @State private var hunks: [DiffHunk] = []

    /// - Parameter initiallyExpanded: 原型是 `diffcard open` ⇒ 默认展开。
    init(file: FileChange, initiallyExpanded: Bool = true) {
        self.file = file
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded { content }
        }
        // 方案 D（2026-10-15，走查第 73 条）：容器去形 —— 不画底、边框、圆角。
        // add/del 行的底色本身就是形状；头部那条下分隔线（`header` 里）负责收边。
        // 默认展开的那一种也要走一次解析 —— 它没经过 `toggle()`。
        // ⚠️ 解析**只在这里与 `toggle()` 两处**发生，`body` 里不做任何解析
        //    （在 `body` 里算就等于"每次重绘都扫一遍"，那正是 §11.2 要避免的）。
        .onAppear(perform: { self.parseIfNeeded() })
        // ⚠️ `patch` 换了就重解析一次。提交详情里它不会变（提交 SHA 是不可变的），
        //    但**切片 7 的 PR 详情会**（同名的文件在新一版 diff 里内容不同），
        //    而卡片的位置没变 ⇒ `@State` 会留着上一版解析出来的行，
        //    表现为"刷新之后看到的还是旧改动"（看起来完全正常）。
        .onChange(of: file.patch) { _, _ in self.parseIfNeeded() }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.xs) {
                // ⚠️ **有意偏差（已登记）**：原型的 `▾` 是一个固定字符，
                //    折叠前后都不变（它只切 `.dbody` 的 `display`）。
                //    于是「收起之后箭头仍朝下」—— 那是原型没处理到的一处不一致
                //    （原型里三个卡片全是 `open`，折叠态几乎没被看过）。
                //    这里**保留同一个字形**、只让它跟着状态转 90°，
                //    不换成 `chevron.down`（字形本身是原型明写的细节）。
                Text("▾")
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                Text(file.filename)
            }
            .font(Theme.Font.monospacedCode.weight(.semibold))
            .foregroundStyle(Theme.Palette.textPrimary)
            .lineLimit(1)

            Spacer(minLength: 0)

            // 原型 `+${add}` / `−${del}`（减号是 U+2212，不是连字符）。
            HStack(spacing: Theme.Spacing.s) {
                Text("+\(file.additions)")
                    .foregroundStyle(Theme.Palette.diffAddedText)
                Text("−\(file.deletions)")
                    .foregroundStyle(Theme.Palette.diffDeletedText)
            }
            // 原型 `.dstat{font-size:11px;font-weight:700}` ⇒ `.caption2` + bold。
            .font(Theme.Font.caption.weight(.bold))
        }
        // 原型 `padding:10px 12px`（10 不在 4pt 阶里 ⇒ 写原值并注明出处）。
        .padding(.vertical, 10)
        .padding(.horizontal, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: { self.toggle() })
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Palette.borderSoft)
                .frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(file.filename)，新增 \(file.additions) 行，删除 \(file.deletions) 行")
        // 领域层的文案常量：说清"按下去会发生什么"，而不是只说"是个按钮"。
        .accessibilityHint(
            CommitCopy.diffToggleAccessibilityLabel(file: file.filename, isExpanded: isExpanded)
        )
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - 主体

    @ViewBuilder
    private var content: some View {
        if file.patch == nil {
            // ⚠️ 两种"没有 patch"**必须分开说**（`FileChange` 的类型说明）：
            //    二进制是"这里看不了"，太大是"太长了，去网页端看"。
            //    同一句话会让一个 50 行的文本改动被说成"二进制文件"。
            notice(file.isBinary ? CommitCopy.binaryDiffNotice : CommitCopy.oversizedDiffNotice)
        } else if hunks.isEmpty {
            // 有 patch、但一个 hunk 都没有（纯改模式 / 纯重命名）。
            // 不画东西的话，展开后一片空白**看起来像加载失败** —— 而它是成功且本就如此。
            notice(CommitCopy.noHunksNotice)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(hunks.enumerated()), id: \.offset) { _, hunk in
                    DiffRow(text: hunk.header, tone: .hunk)

                    ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                        // ⚠️ 行档位与行号都取自 `DiffRendering.swift` 的两条派生属性，
                        //    **不在这里再写一个 `switch`** —— 同一件事有两份实现时，
                        //    领域层加一档只有其中一份会被告知（另一份静默少画一行）。
                        DiffRow(number: line.rowNumber, text: line.text, tone: line.rowTone)
                    }
                }
            }
            // PRD §4.7：「行号列不可选中」—— 言下之意是**正文可以选中**
            // （用户要能把改动复制出去）。`DiffRow` 已经把行号标成
            // `.textSelection(.disabled)`，所以这里整体打开是安全的。
            .textSelection(.enabled)
        }
    }

    /// 卡片里的一句说明（`patch` 缺席 / 无 hunk 两种情况共用）。
    ///
    /// ⚠️ **样式是「规格未给」**：原型里这三种说明都没出现过（它的演示数据永远有 diff）。
    /// 取"次级文字色 + 正文同级字号 + 12pt 内边距"——三个值都是既有令牌，
    /// 与 `CardBox` 的内边距同档，不引入新数字。
    private func notice(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.footnote)
            .foregroundStyle(Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.m)
    }

    // MARK: - 展开 / 收起

    private func toggle() {
        let next = !isExpanded
        isExpanded = next
        if next { parseIfNeeded() }
    }

    /// 展开的那一刻解析一次。折叠状态下**不调用**（§11.2 的"按需解析"）。
    private func parseIfNeeded() {
        guard let patch = file.patch else { return }
        // 只在真的变了才写 `@State`：无条件赋值会让"值相等"也触发一次重绘。
        let parsed = UnifiedDiffParser.hunks(from: patch)
        if parsed != hunks { hunks = parsed }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: Theme.Spacing.m) {
            // 正常 diff（原型 `SCR.commitDetail` 那一段逐字）。
            DiffCard(file: FileChange(
                filename: "GitDuo/Features/Repos/RepoListView.swift",
                additions: 12,
                deletions: 4,
                status: .modified,
                patch: """
                        @@ -40,7 +40,9 @@
                                  PaginatedList(items: store.repos) {
                        -             Button { selection = repo } label: {
                        +             NavigationLink(value: repo) {
                        +                 RepoRow(repo: repo)
                                  }
                        \\ No newline at end of file
                        """
            ))

            // 二进制（服务端不给 patch，且文件名不是文本类）。
            DiffCard(file: FileChange(
                filename: "Assets/launch.png", additions: 0, deletions: 0, status: .modified
            ))

            // 太大（扩展名是文本，但没有 patch）。
            DiffCard(file: FileChange(
                filename: "Package.resolved", additions: 1200, deletions: 800, status: .modified
            ))

            // 有 patch 但没有 hunk（纯改模式）。
            DiffCard(file: FileChange(
                filename: "scripts/build.sh", additions: 0, deletions: 0, status: .modified,
                patch: "diff --git a/scripts/build.sh b/scripts/build.sh\nold mode 100644\nnew mode 100755"
            ))

            // 折叠态（默认收起时的样子 —— 箭头会转过去）。
            DiffCard(file: FileChange(
                filename: "README.md", additions: 3, deletions: 1, status: .modified,
                patch: "@@ -1,3 +1,3 @@\n-a\n+b\n"
            ), initiallyExpanded: false)
        }
        .padding(.horizontal, Theme.Spacing.page)
    }
    .background(Theme.Palette.background)
}
