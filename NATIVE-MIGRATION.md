# 全面改用 SwiftUI 原生控件 —— 替换清单与分期计划

> 2026-10-16 用户拍板：**全面使用原生件**。
> 同时澄清了一条关键口径：**「按原型」= 功能按原型，不是视觉与原型一模一样**。
> ⇒ `redesign/prototype/` 从「视觉规格正本」降级为「**功能清单**」；视觉正本改成 **Apple HIG / SwiftUI 标准控件**。
>
> ⚠️ 这份文档是**进行中的计划**，不是历史记录。执行按 P0 → P6 推进，**一期内可以中断、每期结束必须 `make verify` 全绿 + 真机目视**。

---

## 1. 现状一句话

结构层（导航 / 弹层 / 刷新 / 转圈）已经是原生的；**"长什么样"这一层几乎全是自绘的** ——
`GitDuoDesign` 44 个组件 + 各域 App 组件，配一套自定的 `Theme` 令牌（48 色 / 8 间距 / 12 圆角 / 21 字体档）。

几个能说明问题数字：

| 指标 | 值 |
|---|---|
| `List` / `Form` / `.searchable` / `ContentUnavailableView` / `Toggle` / `swipeActions` / `contextMenu` | **0 处** |
| `.redacted`（官方骨架方案） | **0 处** —— 骨架全靠自绘 `SkeletonBar`（102 处） |
| `@ScaledMetric`（官方动态类型方案） | **0 处** |
| `Button` 构造点 | 143 处，其中 **30 处 `.buttonStyle(.plain)`**（= 明确绕开系统样式），真正用系统样式的只有 **1 处** |
| 自绘弹层 | 16 个 sheet 视图，全靠自绘的 `SheetPrimitives` 五件套拼 |
| 已经用上官方的 | `NavigationStack` · `.sheet` · `.refreshable` · `ProgressView` · `Menu` · `Picker` · `.photosPicker` · `.confirmationDialog` · `glassEffect` |

---

## 2. 替换清单

调用点 = 组件标识符在全仓 .swift 中出现的次数（含声明与 `#Preview`）。

### A 组：有官方对应，直接换（44 项）

| 组件 | 换成 | 调用点 |
|---|---|---|
| `SkeletonBar`（+ 7 个 `*Skeleton`） | `.redacted(reason: .placeholder)` | 102 |
| `UserAvatar` | `AsyncImage` + `.clipShape(.circle)` | 86 |
| `CardBox` | `List` + `Section` / `.listRowBackground` | 69 |
| `ActionButton` | `Button` + `.buttonStyle(.borderedProminent/.bordered/.borderless)` + `.tint()` | 50 |
| `RepoAvatar`（已退役，只剩骨架常量） | `AsyncImage` / `Image(systemName:)` | 47 |
| `StatInfo` | `Label` / `LabeledContent` | 38 |
| `StatButton` | `Button` + `.buttonStyle(.bordered)` | 37 |
| `SectionHeader` | `Section("…")` 的 header | 36 |
| `StateIcon` | `Image(systemName:)`（本就是 SF Symbols） | 33 |
| `SegmentedBar` | `Picker` + `.pickerStyle(.segmented)` | 31 |
| `EmptyBox` | `ContentUnavailableView` | 24 |
| `LinkRow` | `NavigationLink` | 21 |
| `CodeTextArea` | `TextEditor` / `TextField(axis: .vertical)` | 16 |
| `MenuCard`（+ `MenuRow`） | `List` + `Section` / `Form` | 15 |
| `PanelBox` | `Section` + `.background(_:in:)` | 13 |
| `BranchRow` | `List` 行 + `.swipeActions(edge: .trailing)` | 11 |
| `LabelDot` | `Circle` / 直接删（用 `Label` 的图标位） | 8 |
| `SectionTabs` | `Picker` + `.pickerStyle(.segmented)` | 6 |
| `CodePreviewLine` | `Text` + `.monospaced()` | 6 |
| `LabelAddButton` | `Button` + `.buttonBorderShape(.capsule)` | 4 |
| `MarkdownImage` | `AsyncImage` | 17 |
| `RepoTreeSection` | `List` + `NavigationLink`（层级进栈） | 28 |
| `IssueCard` | `List` 行 + `NavigationLink` + `Label` | 22 |
| `PullCard` | 同上 | 20 |
| `PinRow` | `List` 行 | 14 |
| `StarRow` | `List` 行 + `LabeledContent` | 14 |
| `RepoCard` | `List` 行 + `NavigationLink` | 13 |
| `SearchRowView` / `SearchRowBox` | `List` + `Section`（分隔线由系统画） | 11 / 8 |
| `RecentRow` | `List` 行 | 8 |
| `RepoFileRow` / `RepoCommitRow` | `List` 行 + `NavigationLink` | 8 / 6 |
| `RepoIssuesSection` | `List` + `Section` + `Picker(.segmented)` | 7 |
| `ExploreFilterSheet` | `.sheet` + `List` / `Picker` | 6 |
| `SearchField` | `.searchable(text:)` | 5 |
| `RepoPullsSection` | `List` + `Section` + `Picker(.segmented)` | 3 |
| 6 个列表骨架（Explore/Home/Profile/Repos/Repo/Search） | `.redacted` | 3 / 8 / 5 / 4 / 7 / 4 |
| `SearchIdleSection` | `.searchSuggestions { }` | 4 |
| `PageFailure` / `SectionFailure` | `ContentUnavailableView`（带重试按钮） | 16 / 28 |

### B 组：官方有积木但拼不出原形状，用官方件"重写"（32 项）

| 组件 | 用什么拼 | 调用点 |
|---|---|---|
| `ToastCenter` / `Toast` | 无官方 Toast；改成 `.overlay(alignment:) + .transition(.move(edge:)) + .animation` 自己管（或用 `.safeAreaInset`） | 60 / 28 |
| `FlowLayout`（另有一份 `MarkdownFlowLayout`，**先合并**） | `LazyVGrid(.adaptive)` / `ViewThatFits` | 38 / 2 |
| `MarkdownBody`（块级：标题 / 列表 / 表格 / 代码块 / 图片） | `Text(AttributedString(markdown:))` 只吃行内；块级仍需自绘 —— **保留结构、换掉行内渲染** | 33 |
| `NoticeBar` | `Label` + `.background(_:in:)` | 34 |
| `StatusPill` | `Text` + `.background(_:in: .capsule)`（iOS 26 起有 `.badge()`） | 54 |
| `AvatarStack` | `HStack` + `AsyncImage` | 18 |
| `ProfileHeader` | `VStack` + `AsyncImage` + `Text`（组合件） | 18 |
| `ProfileStatBar` | `LabeledContent` / `Label` + `Button` | 16 |
| `CodeSurface` | `Text(AttributedString)` + `.fontDesign(.monospaced)` + `ScrollView(.horizontal)`；着色自算 | 26 |
| `CommentBubble` | `LabeledContent` + `.background(_:in: .rect)` | 23 |
| `ForkIcon` | 无同形 SF Symbol ⇒ **保留自绘 `Path`** | 23 |
| `LabelPill` | `Text` + `.background(_:in: .capsule)` | 22 |
| `RepoReadmeSection` | `Section` + `Text(AttributedString(markdown:))` + `Link` | 14 |
| `RepoHeroCard` / `RepoDetailHero` | `Section` + `LabeledContent` + `Label` + `AsyncImage` | 12 / 10 |
| `TrendCard` | `List` 行 + `NavigationLink` | 10 |
| `CommentComposer` | `TextField(axis: .vertical)` + `Button` + `.safeAreaBar` | 8 |
| `SelectedLabelRow` | `LazyVGrid` + `Button` | 12 |
| `FilterChip` | `Menu`（自带 label + indicator）或 `Picker` + `.menu` | 9 |
| `UserProfileSheet` | `.sheet` + `Form` + `AsyncImage` + `LabeledContent` | 7 |
| `DiffCard` | `DisclosureGroup` 收口折叠，展开内容仍自绘 | 20 |
| `ClearRecentSheet` | `.alert` / `.confirmationDialog` | 5 |
| `ReleaseNotesSheet` | `.sheet` + `Text(AttributedString(markdown:))` | 5 |
| `ColorSwatch` | `Button` + `.bordered` + `.overlay` | 12 |
| `BreadcrumbBar` | `NavigationStack` path + `Menu`（分支）+ `Text` | 13 |
| `SheetPrimitives`（5 件） | `Form` + `Section` header / `TextField` / `Button(.bordered)` / `Text(.caption)` | 高频 |
| `StatStar`（分派件） | `Button` / `Label` | 13 |
| `ConversationHeader` | `LabeledContent` + `Text` | 12 |
| `HeatmapHeader` | `LabeledContent` + `Menu` | 15 |
| `LanguageBar` | Swift Charts `BarMark` 或 `Gauge` | 11 |

### C 组：无官方对应，**不换**（7 项，保留自绘）

| 组件 | 为什么留 | 调用点 |
|---|---|---|
| `ContributionHeatmap` | 53×7 日历方格矩阵，Charts 表达不了 | 39 |
| `DiffRow` | diff 行（行号槽 + 六档底色）无官方件 | 54 |
| `MarkdownBadgeView` | shields.io 徽章重绘 | 4 |
| `CodeHighlighting` / `DiffRendering` / `StateTone` | 纯逻辑翻译层，非 UI | 6 / 1 / 4 |
| `MarkdownImageStore` | 取图上下文（仓库 / 分支 / 基准目录） | 9 |

### D 组：令牌（`Theme`，89 个）

| 类别 | 数量 | 处置 |
|---|---|---|
| `Theme.Font` | 21 | 全是系统 Dynamic Type 语义档 ⇒ **可直接删**，各处直写 `.body` / `.caption` 等（或保留做别名） |
| `Theme.Spacing` | 8 | 列表内交给系统；页面级留 3–4 档，其余删 |
| `Theme.Radius` | 12 | 交给 `.background(_:in:)` 与系统形状，删 |
| `Theme.Palette` | 48 | 迁到 **Asset Catalog** + 语义色（`.primary` / `.secondary` / `.tint()`）。⚠️ 三组**没有系统等价物，必须保留自定色**：**diff**（4）、**语法高亮**（4）、**热力图 5 档**；另外头像兜底 8 色、状态色族也是 GitHub 语义 |

---

## 3. 分期计划

每期独立可停；每期结束 `make verify` 全绿 + 真机目视。**顺序按"收益高 / 风险低"排，不是按页面排。**

### P0 · 口径落地（半天，无 UI 改动）
- 改 `AGENTS.md` §0：原型 = **功能**清单，视觉正本 = HIG；加一行指向本文档。
- `PRD` / `TECH_SPEC` / `REVIEW-CHECKLIST` 三处记一笔「原型降级」与「自绘件退休计划」。
- 顺带：`archive/` 里前几轮为"对齐原型视觉"写的那些口径（hairline 缩进 66/56/57、卡片圆角 18、内嵌分隔线）标记为**作废**。

### P1 · 白拿系统行为（观感基本不变，收益最大）
1. 骨架：8 个 `*Skeleton` + `SkeletonBar` → `.redacted(reason: .placeholder)`（**102 处**）
2. 空态 / 失败：`EmptyBox`（24）· `PageFailure`（16）· `SectionFailure`（28）→ `ContentUnavailableView`
3. 确认弹层：`ClearRecentSheet`（5）· `SignOutConfirmSheet` → `.alert` / `.confirmationDialog`
4. 行的系统交互：`BranchRow` 删除 → `.swipeActions`；该有长按菜单的地方加 `contextMenu`
5. 设置页：`Toggle` / `Picker` 用原生形态（现在只有主题三档用了 `Picker`）
6. `.searchable(text:)` 替换 `SearchField`（5）+ `.searchSuggestions` 替换 `SearchIdleSection`（4）
   ⚠️ 这一条**会改观感**（变系统搜索框），但属于"要原生"的应有之义

### P2 · 按钮与控件样式
- `ActionButton`（50）→ `Button` + 系统 `.buttonStyle` + `.tint()`
- 30 处 `.buttonStyle(.plain)` **逐处判读**：自绘行（会消失的那批）保留 plain，真按钮换系统样式
- `StatButton`（37）· `LabelAddButton`（4）· `ColorSwatch`（12）→ `.bordered` / `.borderless` + `.buttonBorderShape(.capsule)`
- `SegmentedBar`（31）· `SectionTabs`（6）→ `Picker` + `.pickerStyle(.segmented)`
- `FilterChip`（9）→ `Menu`

### P3 · 列表主干（**最大的一期**）
- 各页 `ScrollView + LazyVStack` → `List`（含 `.listStyle` 选型，iOS 26 下建议先用默认 / `.insetGrouped`）
- 行件全部改成系统行：`RepoCard` `TrendCard` `IssueCard` `PullCard` `PinRow` `RecentRow` `StarRow` `MenuRow` `LinkRow` `BranchRow` `SearchRow*`
- `SectionHeader`（36）→ `Section` 的 header；**自绘 hairline 全部删掉**（"顶线 vs 底线"、"缩进 66/56/57"这一整族问题随之消失）
- `CardBox`（69）· `PanelBox`（13）· `MenuCard`（15）→ `Section` / `.listRowBackground`

### P4 · 弹层
- `SheetPrimitives` 五件套 → `Form` + `Section` + `TextField` + `Button(.bordered)` + `Text(.caption)`
- 16 个自绘 sheet 逐个改写 + 标准 `.presentationDetents`

### P5 · 令牌收尾
- `Theme.Palette` 48 色 → Asset Catalog + 语义色；保留 diff / 语法 / 热力图三组自定色
- `Spacing` / `Radius` / `Font` 三档瘦身或删除
- 补 `@ScaledMetric` 与动态类型（现在 0 处）

### P6 · 保留自绘件的"官方化"
`ContributionHeatmap` / `DiffRow` / Markdown 块级 / 代码高亮 / Toast / 面包屑 / 气泡 —— 不换掉，但内部改成用官方积木拼（`Grid` / `AttributedString` / `TextEditor` / `AsyncImage` / `DisclosureGroup` / `Charts`）。

---

## 4. 代价与风险（先说清楚）

1. **观感会变成"iOS 原生 App"，不再是"GitHub 客户端"。** 方案 A/D 那一批视觉工作（圆角 18、卡间 10、内嵌分隔线那一整族）在 P3 之后基本作废 —— 这是方向变更的必然结果，不是返工。
2. **验收依据要换**：原型不再逐像素比对 ⇒ 每期结束需要你在真机上看一眼（`make device`），我不再能从原型推导出"对不对"。
3. **P3 一改就是几十个文件**，建议按页分批提交（首页 → 仓库列表 → 探索 → 搜索 → 我的 → 仓库详情），每批一次 `make verify`。
4. **无障碍与动态类型会白拿回来**（P1/P5 之后），这是这次改动最大的实利。
5. 有 7 个组件**永远自绘**（C 组），别把它们当成"还没改完"。

---

## 5. 建议的第一步

从 **P1** 开始：骨架换 `.redacted`、空态与失败换 `ContentUnavailableView`、确认弹层换系统弹层 ——
这三块**不碰观感**、改动局部、收益立竿见影（少掉 150+ 处自绘代码），可以拿来验证"原生化"这条路的手感，再决定要不要进入 P3 那个大改。
