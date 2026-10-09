# AGENTS.md —— GitDuo 2.0 的 AI 开发入口

> 这个文件是**每次动手前必读**的唯一入口：规则、命令、文档索引都在这里。
> 它与 `PRD.md` / `TECH_SPEC.md` 的关系：**规格看文档，纪律看这里**。

## 0. 当前阶段

**切片 1（Auth）已验收；切片 2（GitHubAPI 客户端骨架）2.1–2.6 已落地；切片 3（仓库列表）3.1–3.7 已落地；切片 4（首页 + 探索 + 详情）4.0–4.6 已落地；切片 5（搜索）5.0–5.6 全部落地；切片 6（文件查看 + 提交详情 + 分支管理 + 仓库详情外壳）6.0–6.6 全部落地，并已**陪跑目视修复（6.7 起，现已到 6.9 —— 完成定义第 3 条「与原型逐屏对照」12 项于 2026-10-07 全部走完）**；**切片 7（Issues / PR）2026-10-08 开工、当天走完：7.0 文档先行（决策 #56–#63）· 7.1 领域层 · 7.2 数据层 · 7.3 设计系统 · 7.4 表现层 · 7.5 装配与路由**全部落地并提交（`0b963df`）；**7.6 收尾三件事也已齐** —— `make verify` 已过 · 文档同步已做 · **逐屏对照 13–17 五项同日走完**（用户回"看过了没啥问题"）⇒ **切片 7 的 4 条完成定义全部满足**。**
**切片 8（编辑器与提交）已于 2026-10-08 开工：8.0 文档先行（决策 #64–#70）已落地** —— 本片把决策 #51 里"画出但不可点"的那批按钮（`编辑` / `更多` / 「＋ 添加」）**全部接通**，
并**新扩出三件事**（用户 2026-10-08 拍板）：**「更多」= 重命名 + 删除文件**（原先连规格都没有，本次补出 `PRD §5.15–§5.17`）·
**上传文件 / 上传图片两个出口**（`.fileImporter` / `PhotosPicker`，都不需要权限声明）· **提交弹层「新分支 + PR」的两行输入与 409 两出口**。
**8.1 领域层已落地**（2026-10-08）：`GitDuoKit/Files/` 的写通道编排与判定 —— `FileWriteTarget`（两档 + 预填分支名）· `CommitDraft`（+ `CommitSource` 四档）·
`FileWriteFailure`（409 与 422 的分类）· `SaveFile`（**三步**：建分支 → 提交 → 建 PR，**四种结局**）· `RenameFile`（**两步串行** + 四种结局）· `DeleteFile` ·
`RepoPath` 的**重命名目标路径判据** · 三个文案命名空间（`EditorCopy` / `CommitSheetCopy` + `FileCopy` 新增三节）· `EditorMode` **从 App 层搬进领域层**。
**8.2 数据层已落地**（2026-10-08）：`GitHubRepoContentEndpoint` 加**写** —— `putFile(owner:repo:path:message:content:sha:branch:)`
与 `deleteFile(owner:repo:path:message:sha:branch:)`，**`branch` 是必传参数（无默认值 ⇒ 少传编译不过**，决策 #65：官方默认值 = 仓库默认分支，
不显式传 ⇒ 在 `feature/x` 上编辑却提交到 `main`，**全程无错误信号**）；`sha` 用 `String?`，**为 `nil` 时整条键不写**（不是写 `null`）；
内容 `base64EncodedString()`（**不带换行**）。`GitHubRepoPullsEndpoint` 加 `createPull(owner:repo:title:head:base:)`（三必填，决策 #67；
`head` 同仓库时**只写分支名**）。**写后缓存失效**：`HTTPRequest.invalidatesPathPrefixes` ⇒ 三条路径前缀
（`contents` / `commits` / `branches`）走 `cache.invalidate(pathPrefix:)`（按 URL **path** 匹配 ⇒ 只清本仓库、清掉所有分支）。
✅ **两条接缝已接上**（8.1 立协议、8.2 接端点）：`extension GitHubRepoContentEndpoint: RepoFileWriteDataSource {}` 与
`extension GitHubRepoPullsEndpoint: RepoPullCreationDataSource {}` —— 扩展体**仍是空的**，但**不再是"有意不存在"**。
⚠️ 空扩展体被整条删掉时**编译与其余测试都不会有反应** ⇒ 新套件 `RepoEndpointsContractTests`（**16 条接缝全清点**，每条当协议用一次）
把"某天有人顺手删掉一个"从**静默**变成**当场红**；**新增接缝时要在那边也加一行**（已写进 `RepoEndpoints.swift` 抬头当维护规矩）。
✅ **切片 8 已全部收口（2026-10-09）**：8.0–8.8 全部落地，**8.6 的「逐屏对照 18–21 + 走查单 #83–#120」也于 2026-10-09 由用户走完（零条目）**
⇒ **切片 8 的 4 条完成定义全部满足**（收口记录见 `REVIEW-CHECKLIST` **6.11**）。
⚠️ 这一批**没有 AI 侧的证据**（用户自行目视、只回传结论）⇒ 状态记 `✅ ⚠️`，与切片 6 / 7 那两批（逐批回传）在证据强度上不同，如实留痕。
**8.3 设计系统已落地**（2026-10-08）：施工图原写「预计零新增」⇒ 逐条核实后**结论成立** —— **零新增组件**，
但**三件既有组件各缺一个参数**（`NoticeBar.tone` 两档色对 · `SheetRow.titleTone` 危险色标题 · `SheetField.minLines` 多行），
另补 `GitHubIcon.pencil` / `trash` 两个图标常量。⚠️ **三个新参数默认值一律保持原行为**，既有 **12 处生产调用点**（`SheetField` 4 · `SheetRow` 6 · `NoticeBar` 2）一个字都没改。
`make verify` = **五包单测 1616 项 + 模拟器构建**，一条命令，**零编译警告**。
（**GitHubAPI 406** · GitDuoAuth 57 · **GitDuoCore 63** · **GitDuoDesign 103 / 11 套件** · **GitDuoKit 987 / 83 套件**）

**切片 9（收藏 / 设置 / 我的 Star）已于 2026-10-09 开工**，承接用户「目视工作我完成了，继续下一步吧」——
**9.0 文档先行已落地**：决策 **#73–#76** + `PRD` 新增 **§4.21** + `TECH_SPEC §9.14` 重写与 **§13.2 一处真错误的修正**（把数组当成了连接）。
**9.1 领域层已落地**：新建 15 个文件（`Favorites/` 3 · `Profile/` 8 · `Mapping/ProfileMapper` + `GitHubAPI` 3 个 DTO），
其中**三处设计是编码期自查改掉的**（`Folder.isDefault` 改计算属性 · `ProfileStats` 三字段全可选 · `LoadMyConversations.Result` 只存游标）。
**9.2 数据层已落地**：两个新端点（REST 资料 / GraphQL 活动）+ 搜索端点加 `sort`/`order` + 两条接缝的生产实现（见 9.2a）。
**9.3 设计系统已落地**：**四个新件 + 一条新令牌 + 一处既有件补口**（见 9.3a）——
`ContributionHeatmap` · `ProfileHeader` · `ProfileStatBar` · `MenuCard`/`MenuRow` · `Theme.Palette.heatmapLevels` · `UserAvatar.initialFont`。
⚠️ 本片是**「占位清零」的那一片**（做完之后 `SkeletonPlaceholders.registry` 应为空数组）；
⚠️ 也是**唯一一片含"纯本地"业务逻辑**的（收藏夹，§9.12）—— 它的计数**永远从映射派生、绝不落盘成计数器**。

✅ **6.5 起「我的仓库列表 → 看代码」这条主线**真的通了 —— `RouteView` 里 `.repoDetail` /
`.fileView` / `.commitDetail` / `.branches` 四条已从占位屏换成真页面，四个入口
（仓库列表 / 首页置顶 / 最近访问 / 搜索）都点得进去。

✅ **7.5 起「仓库 → Issues / PR → 详情」这条支线**也通了 —— `RouteView` 里 `.issueDetail` /
`.newIssue` / `.prDetail` 三条换成真页面，五个入口（仓库详情两段 / 探索 Issues 列表 /
探索 PR 列表 / 搜索的 Issue 与 PR 结果 / 仓库详情 PR 段）都点得进去，
且 `.prDetail` 的 `readOnly` **一路透传**到操作区与提交详情（铁律 #7）。
✅ **这三页 2026-10-08 已目视**（连同仓库详情两段与两个弹层，共 13–17 五项，用户回"看过了没啥问题"）——
记账口径仍是"**看过且未报问题 = 过**"，**若哪一项其实有问题，说一声就改回 ⬜**（正本 = `REVIEW-CHECKLIST §6` 那张表）。

✅ **完成定义第 3 条「与原型逐屏对照」—— 切片 6 的 12 项 2026-10-07 走完、切片 7 的 13–17 五项 2026-10-08 走完**（此前"这些页面都要登录才可达"的理由，6.5 之后不再成立）。
四批都在同日走完：① 首页 · 搜索页 · 仓库详情 · 文件查看 · 探索仓库详情的 README ⇒ 报回 5 条（4 条已修 + 1 条是决策 #51）；
② 探索双榜 · 探索 Issues 列表 · 探索 PR 列表 · 用户资料弹层 ⇒ 未报问题；③ 提交详情（§4.7）· 分支管理（§4.8）⇒ 均无问题；
④ **五个弹层**（§5.7 切换分支 / 新建 / 删除 / 合并 · §5.8 添加文件）⇒ 未报问题（用户回"都看好了"）。
⇒ **切片 6 的 4 条完成定义首次全部满足**（此前只有切片 1 走到过"4 条齐全"）。
✅ **切片 7 那批（13–17：Issue 详情 / 新建 Issue / PR 详情 / 仓库详情两段 / 两个弹层）2026-10-08 走完**
（落地当天就走，没有往后拖）⇒ **切片 7 的 4 条完成定义也全部满足** —— 目前达到这个状态的只有切片 1、6、7。
**清单正本 = `REVIEW-CHECKLIST §6` 末尾**（页级 **26 项** —— 逐项细则共 **149** 条（#1–#149）；已知有意偏差 **39 条**（现行 **38**，第 3 条已作废）；已完成 6.7 / 6.8 / 6.9 / **6.10 / 6.11**）；
**该表的状态列是唯一记录处**。⚠️ ②④ 两批是**口述未报问题**（没有逐条点名）⇒ 按"看过且未报问题 = 过"记的，
**若哪一页其实有问题，说一声就改回 ⬜**。⚠️ 第 ④ 批里 **§5.8 添加文件弹层在 App 里打不开**
（唯一入口「＋ 添加」按决策 #51 不可点）⇒ 那一项只有**代码核对**这一层证据、没有真机目视。

**第 1 批报回来那 5 条** —— 前 4 条是真缺陷（已修，见 6.7 与 `REVIEW-CHECKLIST §6`）、第 5 条是拍过板的设计：
① 首页「清除」确认是系统动作表（贴屏幕底）而 PRD §5.1 与原型要的是弹层；
② README 里的 HTML 标签**原样打出来**（真实 README 大量用 `<p align>/<img>/<br>/<details>`）；
③ README 里的**仓库内相对链接点了没反应**（`[中文](README_zh.md)`）；④ 搜索回车后**键盘一直挂着**，不收起；
⑤ 「＋ 添加 / 编辑 / 历史 / 更多」**点不动** —— 这一条**是决策 #51（有意为之）**，不是接线漏了。
   ✅ **已裁定（2026-10-07）：保持现状** —— 四个候选（保持现状 / 改灰 / 先藏着 / 提前做编辑器）里用户选第一个：
   **本轮不改代码，等切片 8（编辑器）一起接上**。
   ⚠️ 已知代价：这几个按钮"看起来能点"，本轮目视已经被命中过一次 ⇒ **别再当缺陷报/改**；
   真要动它，等于同时改 `AGENTS.md §0`、`PRD §4.4` 与已验收口径。
   ✅ **2026-10-08 更新：切片 8 已经把它们接通** —— `编辑` → 编辑器（§4.6）· `更多` → 文件操作菜单（§5.15）·
   「＋ 添加」→ 添加文件弹层（§5.8，三个出口全通）。**只有 `历史` 仍是"画出但不可点"**（PRD 标 ⏳，本期不做），
   他人仓库的 `⑂ Fork 后可编辑` 也维持原状（纯展示，同 §5.10 关注按钮的处置）。

✅ **目视陪跑里用户自己试出的一条（6.8）**：在「新建分支」连试 `～` 与 `？`（**全角** —— 中文输入法下打 `~` `?` 的默认手感）
**都建成功了**。判定**不是缺陷**：git 的 `check_refname_format` 只禁**半角**那八个，全角同形字是**独立码位**，
`git` 与 GitHub 都收（实测：半角八个全拒 / 全角同形字全收，客户端逐条一致；非 ASCII 名字的 URL 编码实测也读得回来）。
⚠️ 但顺着这条探到一个**真缺口**：禁用字符的判据**按 `Character`（字素簇）比** ⇒「禁用字符 + 组合记号」（`~\u{0301}`）
在客户端**放行**、到服务端吃 422 —— **正是 `BranchName` 开头写明它存在的那条理由**。已改为**按 Unicode 标量判**，
并修掉提示语把命中字符**印两遍**。⚠️ **只堵漏、不加规则**：全角照旧放行；`@{` 维持原判不动。

⇒ **目视这笔账没有往后拖**：切片 6 的清单当天跑完，**切片 7 那批（13–17）也在落地当天走完**（2026-10-08，用户回"看过了没啥问题"）。
⚠️ 走"会改真实仓库"的页面时（删除 / 合并分支 / **合并 PR** / **创建标签**这类）**只看形态、别真删真合真建**；
看到"不一样"**先翻 `REVIEW-CHECKLIST §6` 末尾那张有意偏差表**（**39** 个编号，其中第 3 条已于 2026-10-08 作废 ⇒ 现行有效 **38** 条）—— 拍过板的不算缺陷。
⚠️ 走这一批之前给过的提醒（**别真删真合真建** · "看到不一样先翻偏差表"）与走完的结果，**一并留档在 `REVIEW-CHECKLIST` 6.10**。

> **切片 7 施工图（2026-10-08 起）**：Issues / PR —— Issue 详情 + 新建 Issue + PR 详情，
> **并补上仓库详情（§4.4）的 Issues / Pull Requests 两个分区**（决策 #50 把这两段从切片 6 挪到了这里）。
> 对应 PRD **§4.9 / §4.10 / §4.11 / §4.4（分区二 · 分区三）**（+ §5.2 标签选择/新建弹层 / §5.3 合并 PR 弹层）。
> ⚠️ 它有一半零件在切片 4 就备好了（`IssueRow` / `PullRow` / `LoadRepoIssues` / `LoadRepoPulls` / `IssueCard` / `PullCard`），
> 数据层的 `openIssues` 也早留了口子（注释逐字写着"切片 7 的「我的仓库」四分区确实需要『已关闭』，**那时再加参数**"）。

| # | 内容 | 状态 |
|---|---|---|
| 7.0 | 文档先行：决策 **#56–#63**（表格筛选只按标签走服务端 / Issue 详情 REST 两次 / PR 卡片不显示增删 / 评论草稿落本地 / **评审状态取 `/reviews` 而非 `/comments`** / 两段范围与组件落点 / Issue 关闭重开本期不做 / **标签白字对比度 ⇒ 换同族深色色板**）+ `TECH_SPEC §9.8` / **`§9.8.1`（新增：仓库详情两段）** / `§9.9` / `§4.6.2` 改写 + `PRD §4.4` 两段 / `§4.9` / `§4.11` 补口径 | ✅ |
| 7.1 | 领域层（`GitDuoKit`）：✅ **已落地**（2026-10-08）—— `RepoListState`（`open`/`closed`/`all`）· `LoadRepoIssues` / `LoadRepoPulls` 加 `state` 参数与**标签筛选**（决策 #56）· 两文件**移出 `Explore/` 到 `Repo/`**（决策 #61，它们现在服务两个页面）· `IssueDetail` + `LoadIssueDetail`（**REST 两次、评论可单独重试**，决策 #57）· `IssueComment` + `PostIssueComment`（空内容判据 `canSend`）· `Label` / `LabelPalette`（10 色，**不带 `#`**）/ `LabelCatalog`（自动续页 + **空名与重名都不发那次必败的请求**）· `NewIssueDraft` + `CreateIssue`（占位标题 `新 Issue`、正文不 trim）· `PullDetail` / `PullReview` / `PullTimelineItem`（**评论与评审按时间合成一条流**，决策 #60）· `LoadPullDetail`（详情 + 对话；Commits / 文件**进分区才取**）· `PullAction`（合并三方式 / 关闭 / 重开；`PullMergeResult.merged(at:sha:)`）· `CommentDraftStore`（决策 #59）· 文案 `IssueCopy` / `PullCopy` / `ConversationCopy` / `AuthorName` · **PR 侧多文件 diff 边界**（`PullDetailTests` 里 3 条，含"接成一份会算错哪"的正面证据）| ✅ |
| 7.2 | 数据层（`GitHubAPI`）：✅ **已落地**（2026-10-08）—— `GitHubRepoIssuesEndpoint` 加 `state`/`labels` 参数 + 详情 / 评论读 / 评论写 / 新建 · 新增 `GitHubRepoLabelsEndpoint`（列表 + 新建）· `GitHubRepoPullsEndpoint` 加 `state` 参数 + 详情 / 文件 / Commits / **评审** / 合并 / 改状态（评论写复用 issues 端点 —— PR 的时间线就是 issue 评论）· 新 DTO：`AuthorDTO`（从 `IssueDTO.Author` 提为顶层）· `LabelDTO` · `IssueDetailDTO` · `IssueCommentDTO` · `PullRefDTO` · `PullDetailDTO`（⚠️ **`createdAt` 是 7.1 追加的** —— PR 正文气泡那个时间，用 `updated_at` 会随每次改动而变）· `PullReviewDTO` · `PullMergeResultDTO`（+ `PullMergeMethod` / `PullMergeOutcome`；`PullFileDTO` 是 `CommitFileDTO` 的别名）。⚠️ 13 条路由**配额桶逐个显式声明**并由 `RepoEndpointQuotaTests` 正面断言。⚠️ **Issue 的「改状态」按决策 #62 不做** —— 施工图原先那一行与 #62 冲突，以 #62（后定）为准 | ✅ |
| 7.3 | 设计系统（`GitDuoDesign`）：✅ **已落地**（2026-10-08）—— `CommentBubble`（头像 + 作者 + 时间 + **注入的正文** + 可选状态胶囊）· `LabelPill`（自定义颜色，**白字**）· `ColorSwatch`（10 色板，选中态两层：深边 + 内白环）· `ConversationHeader`（状态胶囊 + 说明 + 标题 + 元信息，形状直接用 `CardBox(vertical: 15, horizontal: 15)`）· **`LabelDot`**（12×12 标签小色块）· **`LabelAddButton`**（虚线「＋ 标签 / 新建」，⚠️ 后两件超出施工图原名、经用户 2026-10-08 裁定一并做掉）· **`LabelColor`**（服务端色值 → `Color` 的唯一转换处，三处共用以免分叉）。新令牌 6 个：`bubbleHeaderSurface` / `labelFallbackSurface` / `Radius.bubble`(12) / `Radius.labelDot`(4) / `Font.conversationTitle` / `Font.commentMeta`。判据 **#43**：只收基础类型、不认识领域模型。⚠️ 顺带一条**口径变更（决策 #63）**：标签是白字压色块，原 10 色色板有四档太浅（黄 1.55 · 灰 2.75）⇒ 按用户裁定换同族深色，十档全部 ≥ 4.5:1；`LabelPalette.hexes` / 原型 `LBL_COLORS` / `RepoLabelsTests` 三处同步，并新增对比度护栏 | ✅ |
| 7.4 | 表现层（`GitDuo/Features/Repo/`）：✅ **已落地**（2026-10-08）—— **仓库详情两段换真件**（`RepoIssuesSection` / `RepoPullsSection`，含标签筛选档与新建入口）· `IssueDetailView`（§4.9）· `NewIssueView`（§4.10）· `PullDetailView`（§4.11 三分区，**Commits / 文件进分区才取**）· 两个弹层（`LabelPickerSheet` §5.2 / **`MergePRSheet`** §5.3）。⚠️ `IssueCard` / `PullCard` **移出 `Features/Explore/`** 改两处共用（决策 #61）。⚠️ 本片**顺手还掉的三笔重复**：`ActionCopy.failed`（正本，**3** 处副本）· `RefreshCopy.failed`（正本，**4** 处副本）· `PageFailure`（收口了 `Features/Repo/Views/` 下 3 处逐字相同的私有实现 —— ⚠️ `Features/Explore/` 下另有 3 处**仍是各自私有实现**，已登记为欠账：收口它要给本件加 `title` 参数并动三个别的 Feature，属独立整理）。⚠️ **新登记 5 条有意偏差**（`REVIEW-CHECKLIST §6` 第 23–27 条），其中 23（PR 文件分区的 diff 默认收起）是唯一一条主动偏离原型视觉的。**⚠️ 已于 2026-10-08 目视**（13–17 五项，用户回"看过了没啥问题"；收口记录见 `REVIEW-CHECKLIST` **6.10**） | ✅ |
| 7.5 | 装配与路由：✅ **已落地**（2026-10-08）—— `AppEnvironment` 接入五条新用例（`issueDetail` / `postIssueComment` / `createIssue` / `pullDetail` / `pullAction`）与**评论草稿存储**（`UserDefaultsCommentDraftStore`，含 `signOut()` 第 ③ 步清理 —— 草稿里可能有还没发布的正文）· `RouteView` 把 `.issueDetail` / `.newIssue` / `.prDetail` 三条从骨架屏换成真件（`.prDetail` 的 `readOnly` **一路透传**）· `SkeletonPlaceholders.registry` 同步消解（只剩编辑器与「我的」旗下的三页）。⚠️ `LoadPullDetail` 同时用到**两个端点实例**（详情 / 评审 / 文件 / Commits 在 pulls 端点、评论在 issues 端点 —— 决策 #60），这是有意的 | ✅ |
| 7.6 | 收尾：✅ **已完成**（2026-10-08）—— `make verify`（**1328 项，零警告**）· 文档同步（本文件 §0 + `REVIEW-CHECKLIST` 页级表 13–17、偏差表 23–27、**6.10 收口记录**）· **逐屏对照 13–17 五项**（Issue 详情 / 新建 Issue / PR 详情 / 仓库详情两段 / 两个弹层）**落地当天走完**（用户回"看过了没啥问题"）⇒ **切片 7 的 4 条完成定义全部满足**。⚠️ 记账口径同切片 6：**口述未报问题 = 过**，正本那张表的状态列是唯一记录处，**若哪一项其实有问题，说一声就改回 ⬜** | ✅ |

> **切片 8 施工图（2026-10-08 起）**：编辑器与提交 —— **把决策 #51 里"画出但不可点"的那批按钮全部接通**。
> 对应 PRD **§4.6 编辑器**（+ **§4.5 的「编辑」与「更多」** / **§5.8 添加文件的三个出口** / §5.9 提交更改 / **§5.15–§5.17 文件操作三件**）。
> ⚠️ **它比原施工图大了三块**（用户 2026-10-08 拍板，见 8.0 那行）：「更多」的重命名 / 删除、上传文件 / 上传图片两个出口、
> 提交弹层的两行输入与 409 两出口。原施工图只写了"编辑器与提交"。
> ⚠️ **8.7 / 8.8 是第二、三笔追加**（2026-10-09，用户上手看效果后**连着**提的两条）：**>1MB 的图片先自适应压缩**（#71）·
> **网页端显示不出来的图片格式一律转码、且 ≤1MB 也转**（#72）。
> ⚠️ **两条都是"用户自己推翻自己先前定的规格"**（#70③ → **#71** → **#72**，**同一条规格被连着收窄两次**）——
> 前面那几笔（8.4 / 8.5 的额外三块）是"原施工图没写"，这两笔是"写了的要改"。
> ⇒ 记一条：**"传原始字节"这类规格，每加一层治理（体积 / 格式）都要回头把上一层的绝对性收窄**，别让两句话同时成立。
> ⚠️ **它是第一个"会往真实仓库写东西"的切片** —— `make verify` 与单测都验不了"提交真的落到了那条分支上"，
> 逐屏对照时**别真写**（`REVIEW-CHECKLIST §6` 的 18–21 那段有完整提醒），拿一只测试仓库走。
> ⚠️ **两处"错了都不报错"**（**决策 #65 / #66**）：`PUT contents` 不显式传 `branch` ⇒ 改动**静默进默认分支**；
> `PUT` 与 `DELETE` 并行 ⇒ 偶发冲突。这两条是本片最该被单测钉住的东西。

| # | 内容 | 状态 |
|---|---|---|
| 8.0 | 文档先行：决策 **#64–#70**（编辑器自己取 sha / **`branch` 恒传 + 写后失效** / 重命名与删除 + **串行** / 「新分支 + PR」两行输入 / **多步操作的部分失败** / 409 两出口 / 上传两个出口的落点）+ `TECH_SPEC §9.6` **重写为五个子节**（写通道 / 两条不能省的参数 / 三步与部分失败 / 409 / 「更多」）· `§4.6.2` 端点表补全（PUT 的 `branch` 默认值 · 新增 `DELETE contents` 与「重命名 = PUT+DELETE」· 建 PR 三必填 · 上传图片的 PhotosPicker 口径）· `§8.4` 弹层表 14 → **17 类** · `§13.2` 配额表补 6 行 + `PRD §4.5 / §4.6 / §5.8 / §5.9` 补口径 + **新增 `§5.15–§5.17`** + `REVIEW-CHECKLIST §1/§6` | ✅ |
| 8.1 | 领域层（`GitDuoKit/Files/`）：✅ **已落地**（2026-10-08）—— **写通道的编排与判定**，五个新类型 + 一个判据补口 + 三个文案命名空间：`FileWriteTarget`（`.currentBranch` / `.newBranch(name:prTitle:)` + `isNewBranch` / `newBranchName` / `newBranchPRTitle` 三个派生属性 + `defaultNewBranchName(now:timeZone:)` 预填 `gitduo/yyyyMMdd-HHmmss`）· `CommitDraft`（`message` **原样存**（打字过程不吃空格）+ **两条回落**：trim 后为空 ⇒ `CommitSheetCopy.defaultMessage`、PR 标题为空 ⇒ 回落生效后的提交信息）+ `CommitSource` 四档（新建 / 编辑 / 上传文件 / 上传图片；**只有后两个的 `pathIsAutomatic` 为真**）· `FileWriteFailure`（409 / 422 / 404 / 其余，**只有前两档给话** + `offersConflictExits`）· `SaveFile`（**三步**顺序固定：建分支 → 提交 → 建 PR；`FileSaveReceipt` 里 **`blobSHA` 与 `commitSHA` 是两个 sha**；四种结局 = 落当前分支 / 建分支 + 建 PR / **建了分支但没提交成** / **提交了但没建 PR 成**；手上没有 headSHA 时补一次 `GET /branches/{branch}`）· `RenameFile`（**两步串行** + 四种结局：`.renamed` / `.destinationExists` / **`.movedButOldRemains`（两步之间断掉 ⇒ 仓库里两个文件都在）** / `.sourceUnavailable(.gone / .notWritable)`）· `DeleteFile`（**现取 sha** + 404 不抛 ⇒ `.alreadyGone`）· `RepoPath.resolveRenameDestination`（前导 `/` 宽容剥一次；空 / 与源相同 / 非法字符三档）· `CommitMessageDefaults`（两个用例共用的默认信息）· 文案 `EditorCopy`（§4.6）+ `CommitSheetCopy`（§5.9）+ `FileCopy` **新增三节**（§5.15–§5.17）· `EditorMode` **迁入本包**（正本在领域层，`TECH_SPEC §8.2` 已改为"只描述形状"）。⚠️ **成果验收**：`FileWriteTargetTests` / `FileWriteTests` / `FileOperationCopyTests` 三套共 **+77 项**（GitDuoKit 780 → 857），其中把"**两步必须串行**""**422 不发 DELETE**（不然两个都丢）""**页脚点名的两颗按钮真的存在**"都做成了正面断言 | ✅ |
| 8.2 | 数据层（`GitHubAPI`）：✅ **已落地**（2026-10-08）—— `GitHubRepoContentEndpoint` 加**写**（`putFile` / `deleteFile`，**`branch` 必传无默认值**、`sha` 为 `nil` 时**整条键不写**、base64 不带换行）· `GitHubRepoPullsEndpoint` 加 `createPull(title:head:base:)` · **写后缓存失效**（`invalidatesPathPrefixes` ⇒ 本仓库的 contents / commits / branches，按 URL **path** 匹配 ⇒ 只清本仓库、所有分支一起清）· 配额桶逐个显式声明（`RepoEndpointQuotaTests` 代码浏览 **5 → 7 条**、PR **7 → 8 条**）。⚠️ 本轮**两条空扩展体已接上**（`RepoFileWriteDataSource` / `RepoPullCreationDataSource`）—— 不再是"有意不存在"的中间状态。⚠️ 三条"静默"性质本轮被钉成断言：① **写不重试**（`HTTPMethod.isSafelyRetryable` 只认 GET ⇒ 重放 PUT 会因 sha 过期回 409 而第一次其实已成功 ⇒ "假失败"）—— 断言带**对照组**（同桩件下 GET 重试、PUT 不重试）；② **`FileWriteResultDTO` 的两个 sha 不能混**（`content.sha` = 新 blob 基准 / `commit.sha` = 这次提交；混了 ⇒ 第二次编辑必 409）；③ **缓存失效不误伤别的仓库**（缓存里放另一个仓库一条，断言写后只剩它）。⚠️ 本片**新套件两个**：`GitHubRepoFileWriteEndpointTests`（**+15 项**）· `RepoEndpointsContractTests`（接缝清点）。⚠️ **"不带 `branch` 的请求发不出去"这条按施工图要求做了**，但**一半是编译期事实、写不出运行时断言**（`branch: String` 无默认值）⇒ 测试注释里把这句**拆成两半**讲清，运行时断言只覆盖下半句（"值真的是 `feature/x` 且 `!= "main"`"）。⚠️ **顺带修掉 4 处编译警告**（3 处 `try #require` 写在 `#expect` 里的假警告 + 1 处 8.1 遗留的 `putFile` 未使用返回值）—— 共同成因是**增量构建会吞掉警告**，第一次 `make verify` 报"零警告"其实是假象，**强制全量重编**（`find ... -xargs touch`）才抓出来 | ✅ |
| 8.3 | 设计系统（`GitDuoDesign`）：✅ **已落地**（2026-10-08）—— 施工图原写「**预计零新增**」，逐条核实后**结论成立**：**零新增组件**，但**三件既有组件各缺一个参数**（都是"加参数、不抄第二份"，默认值一律保持原行为 ⇒ 既有调用点一个字都不用改）：① **`NoticeBar.tone`**（`.danger` 默认 / `.add`）—— 它原先把底 / 字色写死成 diff 的**删除**那一对，而 §5.9「新分支 + PR」那条提示在原型里是 `--add-bg` / `--add-tx`（**值已与 `diffAddedSurface` / `diffAddedText` 逐字核对**，`01-base.css` 第 8 行四色并列声明）；② **`SheetRow.titleTone`**（`.normal` 默认 / `.destructive`）—— 它原先标题色写死 `textPrimary`，而 §5.15「删除文件」明写**危险色**、§5.12 原型里就是 `style="color:var(--closed-p)"`（= `Palette.destructive`）⇒ 少了它"这是破坏性操作"在画面上**完全消失**；⚠️ **只改标题**，图标仍走 `textSecondary`（原型 `.sheet-row svg{stroke:var(--text2)}` 写死，查过）；③ **`SheetField.minLines`**（默认 `1`）—— §5.9 提交信息框在原型里是 `<textarea class="sheet-input" id="cmsg" rows="2">` ⇒ 保底 2 行；⚠️ **不能**改用 `CodeTextArea`（那是**另一个类**：等宽 + `--card` 底），且 `minLines == 1` 走的仍是**原来那一行** `TextField(placeholder:text:)` 而不是 `axis: .vertical` + `lineLimit(1...)`（后者会让单行框随长文本长高，是另一种行为）。另补 **`GitHubIcon.pencil` / `trash`** 两个常量（原型 `11-favorites.js:93/94` 就在用，§5.15 明写"形态照 §5.12"）。✅ **施工图点名的四件全部在位**（`CodeTextArea` 的 `minLines: Int = 6`、`SheetField`、`SheetTitle` / `SheetRow` / `SheetHint`、`ActionButton.Style.destructive` = `0xCF222E`）。⚠️ **一处经核实"不是缺口"**：§5.9 那行只读的「将写入 `{path}`」在 App 里**已有先例** —— `MergeSheet.targetSection` 就是手写的只读行（图标 + 值 + 下方一句 caption）⇒ 8.4 照它写即可，设计包不需要新件；若 8.4 发现两处真的逐字相同，按 6.4 的 `SHABadge` 先例收拢。⚠️ 新增 `Slice8ComponentTests`（**+9 项**，Design 79 → 88） | ✅ |
| 8.4 | 表现层（`GitDuo/Features/Repo/`）：`Views/EditorView` + `ViewModels/EditorViewModel`（§4.6 两模式）· `Views/Sheets/CommitSheet` + VM（§5.9，含两行输入与 409 两出口）· `AddFileSheet` **三行接通**（§5.8，含两个系统选择器）· `Views/Sheets/FileOperationsSheet` / `RenameFileSheet` / `DeleteFileSheet`（§5.15–§5.17，形态照 §5.12 / §5.14 两条先例）· `FileView` 的「编辑」「更多」接通 + **>1MB 时「编辑」不可点**（偏差 32）：✅ **已落地**（2026-10-08）—— 六个新文件 + 四处改造：**`EditorView` + `EditorViewModel`**（§4.6 两模式；编辑模式那一次读**同时**给编辑区初值与 `baseSHA`，决策 #64 同源）· **`CommitSheet`**（§5.9；四相 `editing / conflict / latest / partial`，两行输入 + 409 两个出口 + 两档结果屏）· **`FileOperationsSheet` / `RenameFileSheet` / `DeleteFileSheet`**（§5.15–§5.17）· **`AddFileSheet` 三行接通**（`.fileImporter` + `PhotosPicker`，两个选择器**都不需要权限声明**）· `FileView` 两条接通。⚠️ **施工图 8.4 / 8.5 的边界不可执行** —— 分界写的是"表现层" vs "装配与路由"，而 `AddFileSheet` 的「新建文件」与 `FileView` 的「编辑」都要 `push(.editor)`：**不接通就编不过、也验不了**。所以**8.5 整片并入本片**（`AppEnvironment` 三条写用例 + `RouteView.editor` 换真件 + `SkeletonPlaceholders.registry` 消解），8.5 那一行只在文档里留痕。⚠️ **本片撞到一条被外部事实推翻的规格**：§5.8 写「上传图片 → **选中图片的文件名**」，而 iOS 27.0 SDK 里 `PhotosPickerItem` 的全体成员只有 `itemIdentifier`（相册内部标识，形如 `UUID/L0/001`）/ `supportedContentTypes` / `loadTransferable` —— **没有任何文件名**。⇒ 自拟 `UploadFileName.photo(fileExtension:now:)` = `photo-{yyyyMMdd-HHmmss}.{ext}`（`jpeg`→`jpg`、落空兜底 `jpg`），**PRD §5.8 那张表已同步改正**（同决策 #47 的做法：外部事实优先，改规格不改实现）。⚠️ **另一档规格未给、本片自拟**：**图片上「编辑」也不可点**（`EditorCopy.editImageHint`）—— 编辑器是**文本**编辑器，一张 png 点进去只能得到 `EditorContentIssue.notText` 那个失败态，而用户一路点下来什么都没做错；施工图只点名了 >1MB 那一档。判据收在 **`EditorCopy.editHint(for:)` 一处**（`.text` 可点；`.largeText` / `.image` 各说各的**不同**的一句话 —— 合成一句就会让其中一档说假话）。⚠️ **两处"错了不报错"的坑本片修掉**：① `RenameFileSheet` 的 `.unchanged`（用户没改路径）**不能**让弹层自己 `dismiss()` —— 那样弹层关了而 `sheet` 字段还停在 `.rename`，用户再点一次「重命名」时"要呈现的东西"与"正在呈现的"是同一个值 ⇒ **弹层不再出现**；② 删除办妥之后的 `pop()` 放进 **`.sheet(onDismiss:)`** —— 弹层正挂在**栈顶那一页**身上，先 pop 会把它一起掀掉（无下滑动画 + 导航栏闪一下）。⚠️ 「路径跟着变」**不换路由**：改 `FileViewModel.path` + 重取内容（换路由同样会掀掉挂在这一页上的弹层）。⚠️ **死常量清掉三条**（`FileCopy.editUnavailableHint` / `moreUnavailableHint` / `RepoCopy.addFileUnavailableHint` —— 留着它们，"这三颗按钮还不能点"在代码里就仍然看起来成立）。✅ 单测 **1433 → 1439**（Kit 861 → 867：`EditorCopy.editHint` 1 项 + `UploadFileName` 5 项） | ✅ |
| 8.5 | 装配与路由：`AppEnvironment` 接新用例 + `RouteView` 的 `.editor` **从骨架屏换真件**（§8.3 那张表里它是最后一条占位）· `SkeletonPlaceholders.registry` 消解（只剩「我的」旗下三页）—— ⚠️ **已并入 8.4 执行**（理由见 8.4 那一行末尾：那两条接线不做完，8.4 连编译都过不去） | ✅（并入 8.4） |
| 8.6 | 收尾：`make verify` · 文档同步 · **逐屏对照 18–21**（编辑器 / 提交弹层 / 添加文件三出口 / 文件操作三件）—— ⚠️ **别真写**，见上面那条。⚠️ **走查单已备好**（`REVIEW-CHECKLIST §6` 第二张表 **#83–#120**）；⚠️ **18–21 还没走**，而 8.7 / 8.8 **连着**改了其中两个弹层的可见内容（各改一次同一个地方）⇒ **三片一起走**（8.6 / 8.7 / 8.8 合并目视，不跨片攒） | ✅（2026-10-09 由用户自行走完 18–21 + **#83–#120**，**零条目** ⇒ 8.6 / 8.7 / 8.8 三片一并收口；⚠️ 这一批**没有 AI 侧证据**，只有用户口述结论，已如实登记） |
| 8.7 | **追加（原施工图里没有）：>1MB 的图片先自适应压缩** —— 用户 2026-10-09 提出的**规格变更**（**决策 #71**）：决策 #70③ 的"取原始字节、不重编码"从**绝对**收窄成**默认**（≤1MB 仍然原样）。⚠️ **它推翻的是一条已登记的规格**，所以先改文档再动代码（同 #47 的处置）。落点：`GitDuoCore.Images.ImageCompressor`（ImageIO，跨平台 / 零第三方依赖；⚠️ **8.8 落地时改名为 `ImageProcessor`**，接缝协议也从 `ImageCompressing` 改成 `ImageProcessing` —— 它现在**也管转码**，名字里留着 "Compress" 会让下一个人找错地方）· `GitDuoKit.ImageCompressing` 接缝 + `UploadIntake` 编排 + `CommitSheetCopy.compressedNotice` · `AddFileSheet` 两个出口都过它 · `CommitSheet` 那行只读落点下补一句 caption。⚠️ **三条不许忘**：① **不承诺"一定压得下来"**（压不动仍走"引导网页端"那句）；② **动图不压**（压完只剩第一帧 = 改内容）；③ **压缩有损、剥掉 EXIF（含 GPS）** ⇒ 传上去的不再是相册里那一份，**必须让用户看见**（那行 caption）：✅ **已落地**（2026-10-09）—— 四个新文件 + 十三处改动：**`ImageCompressor`**（⚠️ 8.8 起叫 `ImageProcessor`；档位表 = 无损族 4 档只缩边 → 有损族 9 档先降质再缩边，共 13 次编码；`kCGImageSourceCreateThumbnailWithTransform` **把 EXIF 方向烘焙进像素**，漏了会"竖着拍的照片传上去躺倒"；JPEG 那几档先摊到**白底**，不摊则透明白截图变黑底）· **`ImageCompressing` 接缝**（协议在 Kit、被扩展的类型在 Core，扩展体空 ⇒ 有 `imageSeam` 测试把它当协议用一次）· **`UploadIntake`**（"≤1MB 就**不编码**"这条判据**写在这里、且先判** —— 交给压缩器等于把这句承诺挂在另一个类型上；压缩器回天真值时**再判一次**，否则用户在弹层里填完按下提交才收到 422）· `AddFileSheet`（`isPreparing` 转圈 + 三行暂时不可点；「文件 App」那条先看大小、只在**扩展名不像图片**时当场拒绝 ⇒ 100MB 的 zip 不进内存）· `CommitSheet`（落点行下补 caption `已压缩 3.2MB → 0.8MB`）。⚠️ **两处"静默"被钉成断言**：① `CGImagePropertyHasAlpha` 走 `NSNumber` 而不是 `as? Bool`（后者对 `NSNumber(0/1)` 会**静默**得 nil ⇒ 无损族永远不走，无任何信号）；② 有损阶梯**尺寸与画质都单调不增**、且同一档不同时放宽两个维度。⚠️ **本片不改**「编辑器那条文本通道」的大小判据（两条路）。✅ 单测 **1439 → 1456**（Core 50 → 58：`ImageCompressorTests` 8 项，含两条**真编码再回读**的 —— ⚠️ 8.8 起文件叫 `ImageProcessorTests`、涨到 13 项；Kit 867 → 876：`UploadIntakeTests` 9 项，桩件断言"≤1MB 时压缩器**一次都没被调用**" —— ⚠️ **这条断言 8.8 起被反过来钉住**，见 8.8 行）· `make verify` 全绿 · 强制全量重编零警告 | ✅ |
| 8.8 | **追加（原施工图里没有）：网页端显示不出来的图片格式一律转码（≤1MB 也转）** —— 用户 2026-10-09 提出的**第二笔规格变更**（**决策 #72**）：#71 只解决了"体积"、没解决"格式"，而 iPhone 相机默认拍的 **HEIC** 浏览器根本渲染不出来 ⇒ 传上去在 GitHub 上是一块破图。⚠️ **它把同一条规格又收窄一次**（#70③ → #71 → **#72**），所以同样**先改文档再动代码**。⚠️ **三条不许忘**：① **白名单 = PNG / JPEG / GIF / WebP / SVG**（外部事实，会变；**AVIF 有意在外** —— `UTType` 没有它的编译期常量）；② **不一律转 PNG**（照片转 PNG 体积翻几倍，按源选：带 alpha / 源无损 → PNG，其余 → JPEG）；③ **文件名扩展名必须跟着换**（不换 ⇒ GitHub 仍按老扩展名渲染 ⇒ 白转）：✅ **已落地**（2026-10-09）—— 三个新文件 + 两个删除 + **一处改名**（`ImageCompressor` → **`ImageProcessor`**、`ImageCompressing` → **`ImageProcessing`**、`ImageCompressionStep.Format` → 顶层的 **`ImageOutputFormat`**，新增 `identifier` / `fileExtension` / `displayName` 三个派生属性 —— 最后一个就是 caption 里那句"JPEG"的**唯一来源**）。⚠️ **一处判据被搬家**（本片最容易漏的一处）：`UploadIntake` 里原先有一句"`data.count <= targetBytes` 就原样放行"的**短路** —— #72 一来它就成了 bug（**≤1MB 的 HEIC 会绕过转码**）⇒ 判据下沉到 `ImageProcessing` 的实现里（**只有它看得见字节的真实类型**），并新写一条 `processorIsAlwaysConsulted` 把"≤1MB 也必须问一次"钉住。⚠️ 记一条判据：**短路条件要写在"信息最全"的那一层**，否则每加一层治理（体积 / 格式）都会漏一次。⚠️ **摘要分三种说法**（`CommitSheetCopy.compressedNotice` → **`adjustmentNotice`**，靠 `UploadAdjustment.didShrink` 挑）：`已压缩 3.2MB → 0.8MB` / `已压缩并转为 JPEG · 3.2MB → 0.8MB` / `已转为 JPEG · 1.2MB → 1.4MB` —— **不许把第三种说成"已压缩"**（转码体积可能变大，说反话比不说更糟）。⚠️ **两条外部事实**（2026-10-09 实测，已写进代码注释 + 测试 + 四份文档）：① `UTType.avif` / `UTType.jpeg2000` **不存在**（只有运行时 `UTType("public.avif")` 查得到）⇒ 白名单收成**五个编译期常量**、AVIF 有意在外；② `UTType.svg.identifier == "public.svg-image"`（反直觉，有测试钉住）。⚠️ **`UploadFileName.replacingExtension` 对"没有扩展名"走"接上去"而不是"删再拼"**（`deletingPathExtension` 对 `.gitignore` 会原样返回），有单测钉住。✅ 单测 **1456 → 1468**（Core 58 → 63：`ImageCompressorTests` → **`ImageProcessorTests`**，含 `smallTranscodableIsStillTranscoded` / `smallBMPIsTranscodedToPNG` 两条 #72 核心；Kit 876 → 883：`UploadIntakeTests` 加 `processorIsAlwaysConsulted` · `transcodeRewritesTheExtension` · `transcodeThatGrowsStillCarriesReceipt` · `sizeCheckRunsBeforeTheUntouchedShortcut`；`UploadFileNameTests` 加三条）· `make verify` 全绿 · 强制全量重编零警告 | ✅ |

> ⚠️ **8.1 对施工图措辞的三处有意偏离**（2026-10-08，逐条记下免得下一片照着旧措辞做）：
> ① 施工图原文写「`SaveFile`（**取 sha** → base64 → 发；`mode` 决定带不带 sha）」，实际落地**把"取 sha"排除在 `SaveFile` 之外** ——
> 它只收「**用户读到的那一版**」这个 sha，**不收取法**。理由是决策 **#64**：在提交时刻现取新 sha ⇒ 并发改动**永远撞不上 409** ⇒ **静默丢掉远端改动**。
> ⇒ 「取 sha」归编辑器页（8.4）、「base64」归数据层（8.2，§4.6.2），`SaveFile` 只留编排。
> ② 施工图里 `mode` 决定带不带 sha —— 落到代码上是**两条用例的两种语义**：`SaveFile` 收「读到的那一版」（乐观锁），
> `DeleteFile` **现取**。两者在类型上无法区分（同一个 `String?`）⇒ 已写进协议文档。
> ③ 施工图那一行的 `CommitCopy` 实际落成 **`CommitSheetCopy`**（§5.9 提交弹层）+ **`EditorCopy`**（§4.6 编辑器）两个命名空间，名字与 PRD 章节对齐。
> ⚠️ 三条都是**措辞没跟上实现**那一类，不是漏做；但下一片（8.2）若照原文找 `SaveFile` 里的 `Data` 参数会找不到。

> **切片 9 施工图（2026-10-09 起）**：收藏 / 设置 / 我的 Star —— **把「我的」那条线上剩下的占位全部换真件**。
> 对应 PRD **§4.17 我的（Tab 根页）· §4.18 我的 Star · §4.19 我的收藏 · §4.20 设置 · §4.21 我的 Pull Request / 我的 Issue（本片新增）**
> （+ §5.5 选择收藏列表 / §5.6 新建收藏夹 / §5.11 退出登录 / §5.12 菜单 / §5.13 重命名 / §5.14 删除确认 六类弹层）。
> ⚠️ **本片是「占位清零」的那一片** —— 一共 **5 处**：`RouteView` 的三条推入页（`.stars` / `.folders` / `.settings`）· 「我的」Tab 根页
> （`ProfileView` 至今仍是 `SkeletonScreen`，只有一条真实现的 `signOutRow`）· `SkeletonPlaceholders.registry` 自己 ·
> 他人仓库详情里的 `myFoldersSection`（"我的收藏（私人整理 · 仅自己可见）"，现挂在 `ExploreRepoViewModel` 上）。
> ⇒ **做完本片，`SkeletonPlaceholders.registry` 应当是空数组**；若不是，说明还有一处没消。
> ⚠️ **两处与原型必然不同**（都在 9.0 文档先行时定了，见决策 **#73 / #74**）：① **新增了一个原型没有的页面**（`.myConversations`）——
> 原型那两个菜单项是"直接跳详情"（演示数据里正好各有一条）；② **热力图口径与原型不同** —— 原型画死 **40 周**（硬编码），
> 真实数据是 **API 给的一年（≈53 周）**。两条都已登记为**有意偏差第 37、38 条**（`REVIEW-CHECKLIST §6`）。
> ⚠️ **9.3 顺带发现一处"既有偏差"（本片有意不动，登记在此待裁定）**：`UserAvatar` 首字母字号
> 三档原型是 **13 / 19 / 30**（对直径 34 / 52 / 86），而本仓 34 / 52 两档一直用 `Theme.Font.label`（**11pt**）。
> 9.3 只把新的 86 那一档做对（30pt/800），**没有顺手改那两档**（它们是切片 4 / 5 已验收的观感，
> 而"头像里的字母变大一点点"是评审时不说不清的那类变化）。要一次性收口 = 改 `UserAvatar.initialFont` 的默认值一处。
> ⚠️ **收藏夹是本片唯一"纯本地"的一块**（§9.12：GitHub 没有对应资源，连读接口都没有），
> 而它的**计数必须永远从映射派生**（`favMap` 单一数据源）—— 这条已经踩过一次坑（原型第一版用独立计数器 ⇒ 删夹后默认夹不动），
> 见 §9.12 与 `REVIEW-CHECKLIST` 有意偏差表。

| # | 内容 | 状态 |
|---|---|---|
| 9.0 | 文档先行：决策 **#73–#76**（我的 PR/Issue 落点 = **新增专用列表页**，不复用搜索页 / 热力图 = **画满 API 给的一年、5 档照 `contributionLevel`** / 清除缓存 = **清自建接口缓存** / 三统计项来源 + **"仓库"数与仓库列表同源**）+ `TECH_SPEC §9.14` **重写** · `§9.15` 清除缓存改口径 · `§8.2` 新增 `.myConversations(kind:)` · `§8.3` 补一行 · `§4.6.5` 补一句 · **`§13.2` 修正一处真错误**（`weeks` 是**数组不是连接**，原写的 `weeks(first:53)` 会被服务端拒）+ `§5.1` / `§5.4` 补"三层里实际**只落地了 L2**"· `PRD §4.17–§4.20` 补口径 + **新增 `§4.21`** + §7 补三条空态 + 修 `§4.19` 里**引错的弹层编号**（原写 §5.14，应为 §5.6）· 本文件切片 9 图 · `REVIEW-CHECKLIST` 走查单 **#121+** 与有意偏差 **37 / 38** | ✅ |
| 9.1 | 领域层（`GitDuoKit`）：**从零建**（`FolderStore` / 收藏夹相关类型在工程里**一个都不存在**——切片 4 的收藏入口当时只做到了"弹层画出来"）—— `Folder { name, isDefault }` + 收藏映射 `favMap: [repoFullName: folderName]`，**计数纯派生**（§9.12 那张归属表逐行落地：首次收藏 / 换夹 / 取消 / 新建并收藏 / 重命名 / 删除回落）· 收藏夹校验与全部文案（空名 / 重名 / 默认夹保护 / 删除回落提示；⚠️ **两个入口的重名处置有意不同**：仓库详情入口"提示并自动选中"、管理页入口"只提示不创建"）· **我的会话查询**（`author:@me` + **单条 part**，按 kind 选限定符 —— 与搜索页的双 part 有意不同，决策 #73）· 我的页资料模型与三统计项口径 · 热力图分档与网格模型（**53 列 × 7 行的坐标**，分档由 `contributionLevel` 翻译，**不自己按次数划**）· Star 列表分页编排（复用既有 `listStarred`） | ✅ |
| 9.1a | **实际落地（2026-10-09）**：新建 **15 个文件** —— `GitHubAPI` 3 个 DTO（`ContributionCalendarDTO` / `ViewerActivityDTO` / `ViewerProfileDTO`，随领域层立、端点在 9.2）· `GitDuoKit` 的 `Favorites/`（`Folder` / `FolderStore` / `FolderCopy`）· `Profile/`（`ContributionGrid` / `ViewerProfile` / `ProfileOverview` / `ProfileDataSource` / `LoadProfileOverview` / `ProfileCopy` / `MyConversations` / `LoadMyConversations`）· `Mapping/ProfileMapper`。<br>⚠️ **三处编码期自查改掉的设计**（都不是编译错，是"能构造出脏数据"）：① `Folder.isDefault` 由存储字段改**计算属性**（`Codable` 合成实现绕过自定义 `init` ⇒ 字段能与名字脱钩）；② `ProfileStats` **三个字段全 Optional**（GraphQL 允许部分成功 ⇒ "日历没拿到、两个计数拿到了"是真实可达形状）；③ `LoadMyConversations.Result` 只存 `nextCursor`，`hasMore` **派生**（存两份必然不同步 ⇒ 「加载更多」每次点击都回到第一页且配额白扣）。<br>⚠️ **`ProfileCopy.signOutDegradedNotice` 收口了一处文档/代码不一致**：PRD §5.11 / §7 的长版带「可在设置中手动撤销」，而 `AppEnvironment.signOut()` 现用短版 ⇒ 9.5 接线时改为引用本常量（提示不说出口在哪，那个兜底就等于不存在）。<br>⚠️ **Star 列表分页编排无需新建代码**：`LoadRepositoriesPage.load(source: .starred)`（切片 3）已够，本片只核实。<br>⚠️ **`RepoEndpointsContractTests` 本片不加行**：`ProfileDataSource` / `MyConversationsDataSource` 的生产实现在 9.2。<br>测试：`GitHubAPI` 377 → **389**（新 DTO 解码，含 `date` 原样留串 / 认不出的 `contributionLevel` / 缺 `followers` 不许静默给 0）· `GitDuoKit` 883 → **978 / 82 套件**（归属表逐行 + 计数派生 + 默认夹两重保护 + 两入口重名处置**有意相反** + 落盘往返与排序 + 5 档翻译 + 53×7 坐标与尾列 + 三统计项降级 + 单条 part 与三道分页闸门）· `make verify` 全绿 | ✅ |
| 9.2 | 数据层（`GitHubAPI`）：**一次 GraphQL 查询出两个字段**（`viewer.contributionsCollection.contributionCalendar` + `viewer.starredRepositories(first:1){totalCount}` + `viewer.repositories(first:1, affiliations:[…]){totalCount}`，决策 #76）· **我的会话列表端点**（`search/issues` 单条 part + **配额桶声明**：搜索桶，与搜索页共用）· 我的 Star **复用既有 `listStarred`**（不新写端点）。⚠️ `weeks` / `contributionDays` **是数组**，解码时不要按连接处理 | ✅ |
| 9.2a | **实际落地（2026-10-09）**：<br>① **`GitHubViewerProfileEndpoint`（REST）**：`GET /user` → `ViewerProfileDTO`，主桶、**缓存开着**（第二次带 `If-None-Match`，304 不计配额）—— 与登录路径那个 `GitHubUserEndpoint`（`cachesResponse: false`）**有意相反**。<br>② **`GitHubViewerActivityEndpoint`（GraphQL）**：`Response { let viewer: ViewerActivityDTO }` 直接把 `viewer` 当载荷解（字段逐字相同）。⚠️ **两个计数的 `first: 1` 写死在查询文本里、不进变量** —— 与 `GitHubPinnedItemsEndpoint` 的 `first: $first` **有意相反**：那里的 `6` 是会变的业务口径，这里的 `1` 是**点数预算的边界**（写成 100 ⇒ 100 点，而 `totalCount` 一模一样）。`affiliations` 也写字面量。<br>③ **`GitHubSearchIssuesEndpoint.search` 增加 `sort:` / `order:`**（默认 `nil` / `desc` ⇒ 搜索页行为不变）。⚠️ **续页那一路不带它们** —— 靠"GitHub 把查询串回显在 `Link` 头的 `rel="next"` 里"这条外部性质，已如实登记。<br>④ **新接缝 `ConversationSearchEndpoint`**（单方法，`extension GitHubSearchIssuesEndpoint: ConversationSearchEndpoint {}` 空扩展体）+ `GitHubMyConversationsDataSource(endpoint:)` 收协议 ⇒ **排序漏没漏可以不出网地断言**（它有两处规则：限定符按 kind 选、排序必须带，两处漏了都**不报错**）。<br>⑤ **`GitHubProfileDataSource`**（凑齐 REST + GraphQL 两个端点）—— 纯转发、**无专属测试**（同 `GitHubSearchEndpoints` 的处置：它没有规则可断，装配由接缝清点那一行保证）。<br>⑥ 接缝清点 **+1 行**（`sliceNineSeams`，含空扩展体那一条）。<br>测试：`GitHubAPI` 389 → **406**（资料端点 6 条含「缓存开着」与「401 原样抛」· 活动端点 6 条含「`first: 1` 恰好两处」「`weeks` 不许带 `first:`」「部分成功不打捞」· 排序 3 条 · **配额桶 +2**：资料=主桶、我的会话=**搜索桶**（本项目第二条该走搜索桶的路由））· `GitDuoKit` 978 → **987 / 83 套件**（适配器 9 条：限定符 / 排序 / 四个字段 / 行映射复用 / 失败原样抛）· **五包 1575 → 1601 项 / 141 套件** · `make verify` 全绿 | ✅ |
| 9.3 | 设计系统（`GitDuoDesign`）：热力图网格（**5 档配色走语义 token**，⚠️ **不用** API 返回的 `color` / `colors` —— `isHalloween` 为真时 GitHub 会换成南瓜色）· 资料头部 · 统计项三连 · 菜单卡片 · 设置页分区与条目行。⚠️ **逐条核实"预计新增"估对没估对**（切片 8.3 的「预计零新增」经核实成立，但三件既有组件各缺一个参数；本片照同一条流程走） | ✅ |
| 9.3a | **实际落地与逐条核实（2026-10-09）**：<br>**结论 = 不是零新增**（与 8.3 相反）：**四个新件 + 一条新令牌 + 一处既有件补口**。<br>**① 热力图 → 新增 `ContributionHeatmap`**（设计包原先**一件都没有**）：收 `levels: [[Int?]]`（`nil` = 补位、`0…4` = 档位，形状逐字同 `ContributionGrid.levelMatrix`）+ `totalText` + `rangeText`。⚠️ **格子尺寸由可用宽度算出来**（`TECH_SPEC §9.14` 末段明令）——只用 `aspectRatio` 声明比例、由 `Canvas` 拿到真实宽度反算，**没有**照抄原型那个 `11px`（照抄 ⇒ 53 列要 715pt，而屏幕只有 402pt ⇒ 卡片右边写着「过去一年」而图上只有半年）。落**量过一次**：iPhone 17 Pro（402pt）⇒ 可用 342pt ⇒ 一格 **5.28pt**、间距/圆角 **1.20pt**、整图高 **44.1pt**。⚠️ **刻意不做横向滚动**（原型 `.hm-grid{overflow-x:auto}` 实测 313pt 可视宽 / 538pt 内容宽 —— 照抄会只看见半年）。<br>**② 资料头部 → 新增 `ProfileHeader`**（收 `login` + 可空 `name` / `bio`；`nil`、空串、全空白**三种都整行不渲染**）。⚠️ **原型那个大头像是首字母块、不是网络图片**，而 `ViewerProfile` 有意不装 `avatarURL` ⇒ 直接走 `UserAvatar` 的兜底路径，**没有"图片加载失败"这个状态**。<br>**③ 统计项三连 → 新增 `ProfileStatBar`**：与既有 `StatButton`（§4.13 仓库头部）**四处都不同**（有无图标 / 有无灰底框 / 一行还是两行 / 等分还是紧凑居中）⇒ **不能合并**；`action` 是 Optional（原型三项里只有 Star 那一项挂 `onclick`），`nil` 时**根本不是 Button**（同决策 #51，不是 `.disabled`）。<br>**④ 菜单卡片 → 新增 `MenuCard` + `MenuRow`**：`.menu-item` 在切片 9 之前**没有任何对应实现** —— `LinkRow` 画的是 `.file-row`（`padding:11px 4px`、图标 17、恒带尖角），两者**内边距 / 图标 / 副标题 / 尾部 / 可点性五处都不同**。<br>**⑤ 设置页分区 → 复用 `SectionHeader`**（本就实现的是 `.section-label`，本区零改动）；条目行就是 ④ 的 `MenuRow`。<br>**⑥ 唯一一处既有件补口 = `UserAvatar`**：加第三档 `profileDiameter = 86` 与 `profileInitialFont`（30pt/800）+ 一个 `initialFont` 参数。⚠️ **原型的首字母字号三档是 13 / 19 / 30（对 34 / 52 / 86）—— 比值 0.382 / 0.365 / 0.349 不是一个比例**，所以**不能按直径推导**；`initialFont` 默认 `nil` ⇒ **34 / 52 两档一个像素都不变**（那两档本来就与原型差着 2px / 8px，属切片 4 / 5 已验收的观感，**本片不动** —— 要收口请单独决定，见下方提醒）。<br>**⑦ 新令牌 `Theme.Palette.heatmapLevels`（5 档，逐字 `#ebedf0 / #9be9a8 / #40c463 / #30a14e / #216e39`）** + `GitHubIcon` 补 `star` / `bookmark` / `settings` 三个常量（PR / Issue 两行**不新造**，取 `StateIcon` 那两个）。<br>⚠️ **两处"修正既有错注释"**（都不是新增功能）：`SheetPrimitives` 里把 `LinkRow` 说成在画 `.menu-item`（写错了，害得"`.menu-item` 已有实现"这句话看起来成立）；`MenuRow` 抬头记下**实测结论**——`.chev` 写的 `--text3` 被更具体的 `.menu-item svg{stroke:--text2}` 覆盖 ⇒ **尖角与前导图标同色**（2026-10-09 用 Chrome 读 `getComputedStyle().stroke` = `rgb(101,109,118)` 确认）。<br>⚠️ **一处靠原型的细节才没做错**：设置页那五行 `.menu-item` **一个图标都没有**（`12-me.js` 里没有任何 `svg(...)`）⇒ `MenuRow.systemImage` 做成 **Optional**（做成必填就得给它们随便配一个图标，而"多出一个小图标"很难被认成缺陷）。<br>测试：`GitDuoDesign` 88 → **103 / 11 套件** · **五包 1601 → 1616 项 / 142 套件** · `make verify` 全绿 · 强制全量重编**零警告** | ✅ |
| 9.4 | 表现层（`GitDuo/Features/Profile/`）：`ProfileView` **重写**（§4.17，摘掉 `SkeletonScreen`）· `MyStarsView`（§4.18）· `FoldersView`（§4.19）· `SettingsView`（§4.20）· `MyConversationsView`（§4.21，**结果行复用搜索页的 `ConversationResultRow` + `ConversationHit`**）· 弹层 §5.11 / §5.12 / §5.13 / §5.14 / §5.5 / §5.6。⚠️ `signOutRow` 从 `ProfileView` **迁进设置页**（它现在是一条"临时挂在我的页"的真实现，抬头注释已写明切片 9 的处置） | ⬜ |
| 9.5 | 装配与路由 + **占位清零**：`AppEnvironment` 接新用例（收藏夹存储 / 我的页取数 / 我的会话 / 缓存清理）；`RouteView` 三个 case 换真件 + 新增 `.myConversations`；**`SkeletonPlaceholders.registry` 消解（应清零）**；他人仓库详情 `myFoldersSection` 换真件；**`signOut()` ③ 步补收藏夹清空**（它现在只在注释里挂着"尚未接入（落地时补在这一处）"）。⚠️ 收藏夹存储**必须与仓库详情页共用同一个实例**，否则"在两个地方各建一份"表现为收藏时有时无（同 `branchMemory` 那条先例） | ⬜ |
| 9.6 | 测试 + 收尾：把 harness **465–556 段**的原型断言转成 Swift 测试（收藏夹增删改 + **计数派生** + 默认夹保护 + 删除回落 + 退出登录往返）· `make verify` 全绿 · **强制全量重编零警告** · 四份文档收口 · 记忆 · 一个提交 | ⬜ |

> **切片 6 施工图（2026-10-07 起）**：文件查看 + 提交详情 + 分支管理 **+ 仓库详情外壳（PRD §4.4）**。
> 对应 PRD **§4.4 / §4.5 / §4.7 / §4.8**（+ §5.7 切换分支弹层 / §5.8 添加文件弹层 / §3.10 分支）。
> ⚠️ 它同时是**接上主线的那一片**：`ReposView.open()` 按可写性二分，点**自己有权改的**仓库此前进的是占位屏 ——
> 「我的仓库列表 → 看代码」这条 App 最主线的路径到这一片才通。

| # | 内容 | 状态 |
|---|---|---|
| 6.0 | 文档先行：决策 **#49–#55**（文件树副标题来源 / 切片边界 / 别片入口按钮 / 合并弹层 / 删除分支判据 / 大文件与二进制降级 / 分支记忆落点）+ §9.4 / §9.4.1 / §9.5 / §9.7.1 / §11 / §13.2 改写 + PRD §3.10 / §4.4 / §4.5 / §4.7 / §4.8 补口径 | ✅ |
| 6.1 | 领域层（`GitDuoKit/Branches/` · `Files/` · `Rendering/` · `Repo/`，16 个文件）：分支**两段式解析 + 回落 + 404 静默重发**（`BranchResolver`）· **分支名校验**（git ref 八条规则 + 逐条中文提示）· 删除分支判据（`canDelete` = 非默认 **且** 非受保护）与未合并判定（只读 `ahead_by`）· **文件预览三档降级**（`FilePreviewKind`）· contents 解码三条规则（base64 剥换行 / 空壳判定 / 行拆分保空行）· 路径拼接校验（`RepoPath`）· 文件树条目 / 提交列表行 / 提交详情 / 文件改动 · **§11.1 Markdown 块级解析** · **§11.2 unified diff 解析** · **§11.3 语法高亮词法** · 四页文案常量。⚠️ 两处**实现偏离已登记**（见下方提醒） | ✅ |
| 6.2 | 数据层（已落地）：**14 条路由**，全落 `Repos/` 四个端点类 —— `repos/{o}/{r}`（详情头部，`RepositoryDetailDTO`）· `contents/{path}?ref=`（目录清单 + 单文件 base64 双形状）与 `readme`（raw，只吞 404）· `commits`（列表 + `?path=&per_page=1` 逐文件副标题，决策 #49）· `commits/{sha}`（`files[].patch` + `stats`）· `branches?per_page=100` · `branches/{branch}` · `compare/{base}...{head}`（决策 #53）· `git/refs` 建 / 删 · `merges`（201 合并 / **204 没有东西可合** / 409 冲突）。⚠️ 三条**按实测形状**加的：① `RepoContentType` **不能是 `String` 枚举**（目录取值是 **`dir`**，不是 `directory`）② `CompareDTO` **根本不声明** `commits`/`files`（会被截断 ⇒ 判据只剩 `ahead_by`）③ `MergeOutcome` 而不是 `MergeResultDTO?`（204 是确凿答案、不是失败）。⚠️ 14 条路由**配额桶逐个显式声明**（`.core`）+ `RepoEndpointQuotaTests` 用**"每个桶间隔都非 0"的探针策略**正面断言"落主桶且没误用搜索桶"（声明漏了本不会有任何报错） | ✅ |
| 6.3 | 设计系统（已落地）：**设计包四件** —— `CodeSurface`（等宽 + 横向滚动 + 行距用一个 `Text` 装全部行）· `DiffRow`（**六档**：原型四档 + `.note`/`.content` 兜住"少一行"）· `BreadcrumbBar`（路径段走 `FlowLayout` **折行不截尾**、分隔符作**每段前缀**）· `BranchRow`（当前胶囊 + 删除；**不判断能不能删**，判据在 `BranchSummary.canDelete`）+ `GitHubIcon`；配套令牌：**语法四色** · `accentSubtle`（`.hunk` 与 `.sha` 同值合一）· `codeInlineSurface`（半透明）· `Radius.control`(9) / `branchChip`(7) · 五档字号（`monospacedCode` / `markdownH1` / `markdownH2` / `markdownBody` / `breadcrumb`）。**Feature 层三件**（`GitDuo/Features/Repo/Components/`，判据 **#43** —— 收领域模型 ⇒ 留 Feature）：`CodeHighlighting`（`SyntaxTokenKind` 七档 → `CodeTone` 五档的**穷尽翻译**，漏档编译不过）· `MarkdownBody`（吃 `[MarkdownBlock]`）· `DiffCard`（吃 `FileChange`，**展开才解析** patch）。⚠️ 四处「规格未给，待评审」已登记（见下方提醒） | ✅ |
| 6.4 | 表现层（`GitDuo/Features/Repo/`，已落地）：**四页** —— `Views/RepoDetailView`（头部 + 四分段；Issues / PR 两段用 `PendingSection` 占位，**决策 #50**）· `Views/FileView`（PRD §4.5）· `Views/CommitDetailView`（§4.7）· `Views/BranchesView`（§4.8）+ **五个弹层**（`Views/Sheets/`：`BranchSheet` §5.7 · `CreateBranchSheet` · `DeleteBranchSheet` · `MergeSheet` **新弹层，决策 #52** · `AddFileSheet` §5.8）。并**把 `ExploreRepoDetailView` 那两处 `PendingSection`（⑤文件浏览 / ⑥README）换成真件**。⚠️ **四处结构性外置**（不是顺手重构，是 6.4d 绕不开的前置）：`ViewModels/RepoTreeSession`（目录浏览会话：两段式分支解析 / 记忆失效回落 / 副标题补填 / 分支列表 304）· `Components/RepoTreeSection`（§4.4 与 §4.13 共用的"面包屑 + 文件行 + README"）· `GitDuoKit/Repo/RepoWebLinks`（三处"跳网页端"出口）· `GitDuoDesign/Components/SHABadge` —— 判据都是"**同一个 UI 元素有两处定义 ⇒ 必然分叉**"。⚠️ **决策 #51 不可点的按钮**：`编辑` / `历史` / `更多` / `Fork 后可编辑` / 「＋ 添加」一律 `allowsHitTesting(false)` + 去掉 `.isButton` trait + 一句各不相同读屏 hint（**不是** `.disabled`，后者变灰像"暂时不可用"）；**`Raw` 当真做**（复制原文、零请求）。⚠️ **6.4e 修掉两条真缺陷**：① `LoadFileContent` 在 `size` 未知时按名字判 ⇒ 20MB 的 PNG 会被整张拉进内存（现改为**拿到真实字节数后重判一次**，落在第二个请求之前）② **0 字节的文件被判成 `.undecodable`** ⇒ 显示"这个 App 不认识它的编码"（假话）且用户看不到它（`decodeBase64("")` 返回 `nil` 是对的，错的是它后面那一步）。见下方提醒 | ✅ |
| 6.5 | 装配与路由（已落地）：`RouteView` 把 `.repoDetail` / `.fileView` / `.commitDetail` / `.branches` 四条从 `SkeletonScreen` 换成真实视图（依赖逐条从组合根传，页面自己只从 `@Environment` 拿 `router` / `toast` 这类 UI 通道）；`SkeletonPlaceholders.registry` 删掉"切片 6"那几条、并把它们的消解记进"已消解"清单。⚠️ **`AppEnvironment` 的八条用例与 `branchMemory` 装配在 6.4 那次提交里就顺手做完了**（含 `signOut()` ③ 步的 `await branchMemory.clear()`）—— 施工图原写在本片，实际提前兑现，故本片**只剩路由接线**。⚠️ 顺带修掉三处**陈旧说明**：`.repoDetail` 此前把 `path` 参数写成 `_`（接真件时**必须接上**，丢了它表现为"每次点面包屑都回到仓库根"而源码里看不出异常）· `PendingSection` 的类型注释仍写着"§4.13 有 3 个分区占位"（6.4d 后只剩 1 个）· 它的 `#Preview` 还在演示一个**已经不存在**的占位块（"文件浏览 · 切片 6 落地"）| ✅ |
| 6.7 | **目视修复 · 第 1 批**（用户对着原型走完之后报回 5 条，本行只记已修的 4 条 + 1 条已裁定"保持现状"）：① **首页「清除」确认改成弹层**（原先用 `.confirmationDialog`，在 iPhone 上贴着屏幕底、标题被压成一行小字；PRD §5.1 与原型 `openClearRecent()` 要的是"标题 + 说明 + 两个整宽按钮"那张卡片 ⇒ 新增 `Home/Components/ClearRecentSheet`，`HomeView` 换 `.sheet(isPresented:)`）② **搜索回车后收起键盘**（`.submitLabel(.search)` 只改字样、不关键盘，第一响应者仍是输入框 ⇒ 搜完键盘占半屏；`submit()` 里 `isFieldFocused = false`。⚠️ 与 PRD §4.2「刷新结果区时保持输入焦点与光标」**不冲突**：那条管的是"边打边搜"，这里管的是"用户主动提交"）③ **README 里的 HTML 降级**（新增 `GitDuoKit/Rendering/MarkdownHTML`：HTML 块 → Markdown 源的纯函数；`MarkdownParser` 在引用判定之后、列表判定之前接入，`isBlockStart` 同步；收尾条件是**空行**，照 CommonMark 6/7 型）④ **README 里的仓库内相对链接**（新增 `GitDuoKit/Repo/RepoLinkResolver`：相对路径 / 同仓库 blob·tree / 站点根 / 锚点 / 外部五档；`MarkdownBody` 加 `onOpenLink`，`RepoTreeSection` 接线到 `onOpenFile` / `onOpenDirectory` ⇒ §4.4 与 §4.13 同时受益）。⑤ 「＋ 添加 / 编辑 / 历史 / 更多」点不动 —— **这是决策 #51，不是缺陷**；✅ **2026-10-07 已裁定：保持现状**（不改代码、等切片 8 一起接上）。⚠️ **新写的 36 条单测当场抓到一个真缺陷**：HTML 块收集时**漏掉起始那一行**，单行 `<h1>x</h1>` 会整行消失，而多行输入里这个 bug 是**隐形的**（起始行通常只是一个纯标签，转换之后本来就是空串）。`make verify` 全绿（五包 **1060** 项 + 模拟器构建，0 error / 0 warning） | ✅ |
| 6.8 | **分支名校验 · 按 Unicode 标量判**（用户目视时连试两个"看起来非法"的名字 —— `～` · `？`，**全角**，正是中文输入法下的默认手感 —— 都建成功了）。查清后判定**不是缺陷**：git 的 `check_refname_format` 只禁**半角**那八个，全角同形字是**独立码位**、git 与 GitHub 都收（实测：半角八个全拒 / 全角同形字全收，客户端逐条一致；非 ASCII 名字的 URL 编码也实测读得回来）。⚠️ 但顺着这条探到一个**真缺口**：`BranchName.validate` 的禁用字符判据**按 `Character`（字素簇）比**，而 `"~\u{0301}"` 在 Swift 里是**一个**字素簇 ⇒ **放行**，可编码出来是 `~%CC%81` —— ASCII `~` 原封不动进请求 ⇒ git 拒、服务端 422，**正是本类型开头写明它存在的那条理由**。⇒ 正本从 `Set<Character>` 改成**有序 `[Unicode.Scalar]`**（判定用 `Set` 视图现算），顺带修掉提示语把命中字符**印两遍**。⚠️ **只堵漏、不加规则**：全角同形字照旧放行（"只许英文"是**另一个产品口径**—— 做法是反过来只放行 ASCII 白名单，不是拉黑同形码位）；`@{` 维持原判不动。 | ✅ |
| 6.9 | **完成定义第 3 条「与原型逐屏对照」收口**（2026-10-07）：四批走完 ⇒ **12 项全过 + README 复看完成**，**切片 6 的 4 条完成定义首次全部满足**（此前只有切片 1 走到过"4 条齐全"）。四批：① 首页 / 搜索 / 仓库详情 / 文件查看 / 探索 README ⇒ 报回 5 条（4 修 + 1 条决策 #51）；② 探索双榜 · Issues · PR · 资料弹层 ⇒ 未报问题；③ 提交详情 §4.7 · 分支管理 §4.8 ⇒ 均无问题（顺带补登有意偏差第 22 条）；④ **五个弹层**（§5.7 切换分支 / 新建 / 删除 / 合并 · §5.8 添加文件）⇒ 未报问题。⚠️ ②④ 是**口述未报问题** ⇒ 按"看过且未报问题 = 过"记，**正本那张表的状态列是唯一记录处，若哪一页其实有问题说一声就改回 ⬜**；⚠️ 第 ④ 批里 **§5.8 添加文件弹层在 App 里打不开**（入口「＋ 添加」按 #51 不可点）⇒ 只有代码核对这一层证据 | ✅ |

> ⚠️ **切片 6 有两条口径是「外部事实把文档里的旧写法推翻」后据实改正的**（与决策 #47 同性质，见 §1.1 决策 #53 后的提醒）：
> ① 目录清单 `GET /contents/{path}` **不带任何提交信息** ⇒ PRD §3.2 的「最近提交信息」必须**逐文件补请求**（决策 #49）；
> ② `GET /branches` 的每一项**还带 `protected`** ⇒ 删除按钮的判据是「非默认 **且** 非受保护」（决策 #53）。
> 两条都是 2026-10-07 直接打真实 API 实测出来的，不是读文档推断的。
> ③ 还有一条**不是外部事实、而是语言事实**：**Swift 把 `\r`、`\n`、`\r\n` 当作三个互不相同的 `Character`** ⇒
> `split(separator: "\n")` **在 CRLF 提交信息上一刀都切不动**（`"fix: x\r\n\r\n正文"` 被当成一整段没有换行的信息）。
> 6.2 的 `CommitMessage` 曾因此漏归一：目录行副标题把标题与正文挤成一段、详情页正文整块消失，
> **而单看任何一处都不报错**。判据：包内凡"按行拆"必先 `replacingOccurrences(of: "\r\n", with: "\n")`
> （`FileContent.lines(of:)` / `UnifiedDiffParser` 一直这么做）。已补 `CommitMessageTests` 直接钉住（含"根因本身"那条断言）。

> ⚠️ **6.1 有两处「实现层偏离规格」已登记**（都不是偏好问题）：
> ① **Markdown 解析输出的是纯结构（`[MarkdownBlock]`）而不是 `AttributedString`** ——
>    §11.1 的方案栏写的是后者，但本包**不得 import SwiftUI**、而 §11.1 自己又要求
>    "代码块单独用等宽视图"（输出从一开始就是异构的）；纯结构还能用 `==` 逐块断言。
> ② **语法高亮是「逐行独立」的**（§11.3 明写"逐行着色"，这里是把它做到底）⇒
>    跨行的块注释与多行字符串**只对首行着色**。代价是颜色不准（**内容仍然逐字正确**），
>    换来"只对可见区域着色"成立 —— 长文件滚到中间时不必先扫完前面所有行。

> ⚠️ **6.3 有四处「规格未给，待评审」**（原型 `.markdown` / `.diffcard` 只写了它演示到的那几样，
> 这四处它**一次都没渲染过**；逐条论证在各文件的注释里）。共同原则：**能不用新数字就不用、
> 能用既有令牌就不新造颜色** —— 原型是唯一可点验收依据，替它补一套它没写过的视觉
> 等于把验收对象换成了我的偏好：
> ① **`number` / `type` 两档不着色**（原型只给四色）· ② **`DiffLine.displayNumber` = 新号优先
> `newNumber ?? oldNumber`**（原型那段 diff 上下文行两侧的号恰好相同，看不出规则）·
> ③ **引用块加了 2pt 左侧竖条**（原型无 `blockquote` 规则，不加就与段落长得一样）·
> ④ **h3–h6 / 分隔线 / 通知样式**（原型无规则）分别取"正文同档加粗""1pt `borderSoft`"
> "次级色 + 既有内边距"。
> 另有一条**从原型继承来的不一致、本片据实改正**：`.dhead` 的 `▾` 在原型的折叠前后**都不变**
> （它只切 `.dbody` 的 `display`，而三个卡片全是 `open`，折叠态几乎没被看过）⇒
> 这里**保留同一字形**、只让它跟状态转 90°（不换成 `chevron.down`）。
> 以及一条**渲染层固有限制**：行内代码的底在 `AttributedString` 里是**紧贴字形的矩形**
> （`backgroundColor` 不能圆角、不能加内边距）⇒ 底色照原型，形状是方的、没有留白。

> ⚠️ **6.4 有八处「规格未给，待评审」**（原型**一次都没渲染过**这些情形，逐条论证在各文件注释里；
> 共同原则同 6.3 —— **能不用新数字就不用、能用既有令牌就不新造颜色**）：
> ① `RepoCopy.unsupportedEntryToast`（点 `symlink` / `submodule` 时的提示）·
> ② `FileCopy` 四条不可点 hint（编辑 / 历史 / 更多 / Fork 后可编辑，**四条各不相同** ——
> 同一句会让"历史"与"编辑"看起来是同一件做不了的事）· ③ `BranchCopy.mergeNoSourceHint` ·
> ④ `CommitCopy.shaAccessibilityLabel`（读屏怎么念一个短哈希）·
> ⑤ `ActionButton` 的 `horizontalPadding` / `fillsWidth` 两个新参数 ·
> ⑥ `ExploreRepoViewModel` 的**块级**失败态（§8.5 的三档用在"分区"这一层，不是整页）·
> ⑦ 提交信息**正文**的样式（原型只画了标题）· ⑧ `files.isEmpty` 用既有 `EmptyBox` 而不是自建空态。

> ⚠️ **6.4e 修掉两条真缺陷，都是"单看哪一处都不报错"那一类** —— 且**都是被 6.4e 新写的单测钉出来的**：
> ① **图片在 `size` 未知时会被整张拉进内存**：从提交详情点进一个文件时调用方只有文件名，
>    `FilePreviewKind.decide(name:size: nil)` 按**名字**那一侧处理 ⇒ 图片一律判 `.image`，
>    于是"**先看 `size` 再决定下不下**"这条当场落空（20MB 的 PNG 只为发现它太大然后丢掉）。
>    修法**不是**把判定挪到发请求之后 —— 第一趟 `contents` 本身就是为了拿判据；
>    **重判落在第二趟（raw）之前**，那一趟才是可能拉大字节流的那趟。
> ② **0 字节的文件被判成 `.undecodable`**（显示"这个 App 不认识它的编码" —— **假话**，而且用户看不到它）。
>    `isContentOmitted` 对空文件放行是对的（空文件走 raw 只会拿回同样一个空串），
>    错的是它后面那一步：`decodeBase64("")` 返回 `nil`（这条约定**是对的**、被 `FileContentCodecTests` 钉着），
>    于是 `content.flatMap(…)` 也是 `nil` ⇒ 落进"解不出来"那一档。
>    **判据**：`.unsupported` 与 `.undecodable` 分成两档的意义就在于文案不许二选一 ——
>    哪一边说错都是假话（见 `FileViewOutcome` 的说明）。两处均已在 `TECH_SPEC §9.5` 登记。

> ⚠️ **两条"只在 `make verify` 里才炸"的教训（6.4e 实录），都是工具链事实、不是偏好**：
> ① **`GitDuoDesign` 同时为 macOS 构建**（`swift test` 编的是 `arm64-apple-macos`）⇒
>    `textInputAutocapitalization` 这类 **iOS 独有**的修饰符必须 `#if os(iOS)` 包起来。
>    `make test-GitDuoKit` **不会**编到它（它只编自己那一个包），于是**它全绿**而 `make verify` 在这一行炸掉。
> ② **`SheetRow(systemImage:title:) { 内容 }` 里的尾随闭包绑不到 `trailing:`** ——
>    它会选中 `where Trailing == EmptyView` 的那个重载、绑到 **`action:`** 上，
>    于是**右侧那块内容根本不画**，唯一的迹象是一条 `result of call to 'foregroundStyle' is unused` 警告；
>    闭包体若只是 `{ source = name }` 这种赋值，**连那条警告都不会有**。
>    **规矩：要传右侧内容时必须把 `action:` 标签写出来**（`SheetRow(systemImage:title:action:) { … }`）。

> ⚠️ **6.5 是"零新增文件"的一片，但它有三条要记住的**：
> ① **`.repoDetail` 的 `path` 参数曾被写成 `_`**（骨架期用不到）⇒ 接真件时不接上，表现为
>    **每次点面包屑都回到仓库根**，而源码里看不出任何异常。**接真件时先把每条路由的参数逐个对一遍**，
>    别只看"能不能编译过" —— `_` 是合法的 Swift，编译器不会替你记这件事。
> ② **施工图与实际不符**：6.5 原写"`AppEnvironment` 接四条用例 + 分支记忆存储 + 补 `signOut()` 的 `clear()`"，
>    但这三件在 **6.4 那次提交里就顺手做完了**。⇒ **动手前先核一遍施工图那一行还剩多少**，
>    否则会照着过期的描述把已经做好的东西再装配一遍（重复装配**不会报错**，只会让两条装配悄悄分叉）。
> ③ **`PendingSection` 的类型注释与 `#Preview` 都过期了**（还写着"§4.13 有 3 个分区占位"、
>    还在演示"文件浏览 · 切片 6 落地"这个**已经不存在**的占位块）。**占位块是"会变短"的名单** ——
>    删掉一处占位就同步删掉它的说明与示例，否则读者会以为那页还没做完。

> ⚠️ **6.6 的教训只有一条，但它每片都会重演**：**"代码做完了、文档还欠着"是同一个缺陷的两种状态**。
> 本片唯一真正过期的一处是 `TECH_SPEC §3.6` 的登出 ③ 清单 —— 它把「按仓库的分支记忆」列在
> **「尚未接入」**，而 `AppEnvironment.signOut()` 里 `await branchMemory.clear()` **6.4 就在了**。
> 两处单看都"没错"（代码是对的、文档是照当时的实情写的），合起来却在骗人：
> **照它动手会把已经接好的线再接一遍**（重复装配不报错，只会让两条装配悄悄分叉 —— 6.5 已踩过同一形状）。
> ⇒ **每片的收尾都要把所有写着"尚未 / 待 / 未落地 + 本片编号"的句子逐个核一遍**，而不是只改自己那一行。

> **切片 6 交付（2026-10-07）**：6.0 文档先行（决策 #49–#55）· 6.1 领域层 · 6.2 数据层（14 条路由）· 6.3 设计系统 · 6.4 表现层（四页 + 五弹层 + 探索页两处换真件）· 6.5 装配与路由 · 6.6 收尾。
> **主线在此接通**：`我的仓库列表 → 看代码`，此前点自己有权改的仓库进的是占位屏。⚠️ 当时唯一未还的账是完成定义第 3 条
> （逐屏对照，**零次**）—— **该账已于同日 6.7 开跑、并在 6.9 收口（12 / 12）**，现行进度见本文档 §0。

> **切片 5 施工图（2026-10-07 起）**：搜索（PRD §4.2 + §5.10）—— 四范围 · 防抖与取消 · Search 配额纪律。
> 三个入口（首页 / 仓库 / 探索右上角）**都已存在且已接到真实页面**（`RouteView.search` 换成了 `SearchView`）。

| # | 内容 | 状态 |
|---|---|---|
| 5.0 | 文档先行：决策 #44–#46（分页口径 / 热门词来源 / 用户弹层按钮）+ §9.2 改写 + PRD §4.2 与 §5.10 补口径 | ✅ |
| 5.1 | 领域层（`GitDuoKit/Search/`）：`SearchScope` · `SearchDebounce` · `SearchRequestToken` · `SearchQuery`（拼 + 门槛判定）· `SearchHistoryStore` · `SearchRow`（四行）· `SearchCopy` · `SearchHotKeywords` · `LoadSearch`（分发 / 合并 / LRU 缓存） | ✅ |
| 5.2 | 数据层（已落地）：`SearchResult` 泛型信封（四端点唯一解码入口）+ `search/users` · `search/code`（带 text-match Accept）· `search/issues` 三端点与 DTO + `SearchRowMapper`（行级映射）· `SearchEndpoints` 接缝 · `GitHubSearchDataSource` 适配器。⚠️ 配额桶逐个显式声明（已各配单测守卫）；`/search/users` 的 `name`/`bio`/`public_repos`/`followers` 按可选处理（官方示例不含）—— 拿不到 ⇒ 副标题整段不渲染，**一处已报用户待裁定的取数缺口**（要不要逐条补 `GET /users/{login}`） | ✅ |
| 5.3 | 设计系统（已落地）：**三件** —— `StatusPill`（状态胶囊，`.pill`）· `CodePreviewLine`（等宽预览行，`.sr-code`）· `UserAvatar`（单个用户头像，`.avatar`，并把首字母 / djb2 兜底色算法从 `AvatarStack` 提上来、那边改为委派）+ 令牌（`codeSurface` · 状态胶囊三族的底 / 边 6 个 · `Font.tag` · `Font.monospacedPreview`）。⚠️ **施工图原估"仅可能补等宽预览行"，实查后是两件**：PRD §4.2 第 370 行明写会话行要有**状态胶囊**，而它在设计包里根本不存在（4.4 的卡片只用状态图标）；用户行 / §5.10 弹层的头像也没有单件（`AvatarStack` 只有堆叠版）| ✅ |
| 5.4 | 表现层（已落地）：`GitDuo/Features/Search/` —— `SearchView`（输入框 + 清除 + 四范围分段 + 空闲态/结果/空态/失败）+ 六个 `Components/`（`SearchField` · `SearchRowBox` · `SearchResultRows`（四路分派 + 四个行视图）· `SearchIdleSection` · `SearchResultsSkeleton` · `UserProfileSheet`）+ `ViewModels/SearchViewModel`。⚠️ **顶部输入框与分段条有意钉在滚动区之外**（PRD §4.2「刷新结果区时保持输入焦点与光标」—— 原型放在 `.content` 里一起滚，那一处**按 PRD 有意偏离原型**，已在代码注明）。另补领域层两个口：`PullRequestState.pillTitle`（英文胶囊词，与中文读屏 `label` 分开）· `ConversationHit.statusTone`（`.closed` 的族**取决于 `kind`** —— 已关闭 Issue 走紫族、已关闭未合并 PR 走红族，这条规则要在领域层才有人守）| ✅ |
| 5.5 | 装配与路由（已落地）：`AppEnvironment` 接 `search`（`LoadSearch`，**单实例** —— 缓存活在它里面）与 `searchHistory`（`UserDefaultsSearchHistoryStore`，键前缀 `GitDuo.searchHistory`）；`signOut()` ③ 步补 `searchHistory.clear()` + `search.invalidateAll()`（缓存里是**上一个账号搜出来的结果**，含私有仓库名）；`RouteView` 的 `.search` 换成 `SearchView` 并同步删掉 `SkeletonPlaceholders` 里那条登记 | ✅ |
| 5.6 | 文档收尾 + `make verify`：`TECH_SPEC §3.6`（登出 ③ 已接入清单）· `§9.2`（界面落点两行 —— 焦点保全 / 不复用 `LinkRow`）· `§10.7`（`Radius.field`）· `AGENTS.md §0` · `REVIEW-CHECKLIST §6` | ✅ |

> ⚠️ **切片 5 有一条被外部事实推翻的旧设计，已据实改正（决策 #47）**：
> `TECH_SPEC §9.2` 原写「Issue·PR 范围：一次 `GET /search/issues`、按类型字段区分 PR 与 Issue」——
> 那条路**只对 PAT / 无鉴权成立**。官方文档（`docs.github.com/rest/search/search`，多版本一致）明写：
> **App 用户令牌下不带 `is:issue` / `is:pull-request` 直接 422，两类必须分两次查询**。
> 本项目用的正是 `ghu_` ⇒ 现改为发两条（Issue 在前、PR 在后，两个独立游标），**每翻一页 2 格配额**。
> 同一次核实还确认了原 §9.2 里那条**本来就写对了**的：代码搜索必须含 ≥1 个非限定词。

> **切片 4 交付（2026-10-07）**：4.0 文档（决策 #38–#41）· 4.1 领域层纯逻辑 · 4.2 数据层（GraphQL 置顶 / Search 双榜 / 仓库洞察 / Star 写）
> · 4.3 设计系统（决策 #42/#43）· 4.4 表现层（5 个页面）· 4.5 装配与路由 · 4.6 收尾。
>
> ⚠️ **验收口径要分清**：单测与构建全绿 ≠ 切片验收完成。`REVIEW-CHECKLIST §2` 的完成定义有 4 条，
> 其中**第 3 条「与原型逐屏对照」当时一次都没做过**（那四个新页面都要登录才可达，只做过代码级检查）。
> ⚠️ **这条欠账从 6.5 起就不再成立理由**（那四个新页面已可达），**2026-10-07 的 6.7 开跑、6.9 收口** ——
> 现行进度见本文档 §0 与 `REVIEW-CHECKLIST §6` 末尾（12 项，**2026-10-07 已全部走完**）。

| # | 内容 | 状态 |
|---|---|---|
| 4.0 | 文档先行：决策 #38–#41 + §9.10/§9.11 改写 | ✅ |
| 4.1 | 领域层：探索筛选 / 榜单查询 / 星增幅与基线 / 趋势指标（`GitDuoKit/Explore/`） | ✅ |
| 4.2 | 数据层：统一解码器 `GitHubJSON` · 置顶（GraphQL）· 搜索双榜 · 仓库洞察（语言/Release/贡献者）· Star 写 | ✅ |
| 4.3 | 设计系统：`RepoAvatar` / `StatButton` / `AvatarStack` / `LanguageBar` + `GroupedNumber` / `LanguageComposition` + `RepoSummary` + 三个业务卡片 | ✅ |
| 4.4 | 表现层：`HomeView` / `ExploreView` / `ExploreRepoDetailView` / `ExploreIssueListView` / `ExplorePRListView` | ✅ |
| 4.5 | 装配与路由：`AppEnvironment` 接入（6 个用例 + 2 个落盘存储 + `ToastCenter`）+ `RouteView` 接三个新路由 | ✅ |
| 4.6 | 文档收尾 + `make verify`（642 项全绿） | ✅ |

> ✅ **已裁定（2026-10-07）：`.repoDetail`（PRD §4.4「仓库详情 · 自己的仓库」）归切片 6，整页押到那时做。**
>
> 它此前漂着的原因值得记一笔 —— **同一个编号撞了名**：施工图的「4.4」是**第 4 片的第 4 步**（表现层 5 个视图），
> 而 `RouteView` 里那条标着「切片 4 落地」的 `.repoDetail` 指的是 **PRD §4.4**，两码事。
> 施工图 4.4 那一行确实不含它，切片表里 §4.4 又没有被任何一片显式覆盖（切片 6 只领走了 §4.5/§4.7/§4.8）。
>
> ⚠️ **后果不是记账问题，是功能洞**：`ReposView.open()` 按可写性二分 —— 点别人的只读仓库进
> `ExploreRepoDetailView`（已实现），点**自己有权改的**仓库进 `.repoDetail` ⇒ **一张"切片 4 落地"的占位屏**。
> 即 App 最主线的路径（我的仓库列表 → 看代码）在切片 4 之后仍是断的。
>
> **为什么不能提前做**：它的四个分区零件在别人手上 —— 代码 / Commits / 分支依赖切片 6，
> Issues / PR 依赖切片 7。只有头部能立刻做 ⇒ 整页无法独立完成，提前只会打乱切片边界。
> 已登记进 `REVIEW-CHECKLIST §1`（切片 6 那行补入 §4.4）与 `SkeletonPlaceholders.registry`。

> ✅ 已裁定并落地（2026-10-06）：切片 3 的 `RepoCard` 图标与原型不一致（原型走深底 `.repo-avatar`，实现走浅底 `book.closed`）。
> 用户拍板「**两处都改回原型**」⇒ `RepoCard` 已改为复用 `RepoAvatar.standard`，同一 App 里不再有两种仓库图标。

> **切片 3 交付（2026-10-06）**：新增**领域层包 `GitDuoKit`**（决策 #34）+ 仓库列表的取数 / 分页 / 分区 / 卡片全线打通。
> 逐项见下表与 `REVIEW-CHECKLIST.md` §6。

| # | 内容 | 状态 |
|---|---|---|
| 3.1 | 新建 `GitDuoKit` 包（领域层）+ 登记 `Makefile PACKAGES` / `project.yml` | ✅ |
| 3.2 | `RepositoryDTO` + `GitHubRepositoryEndpoint`（`user/repos` · `user/starred`，口径见决策 #35） | ✅ |
| 3.3 | 领域模型 `Repository` / `Permissions` · `RepoListSegment` · `RepositoryMapper`（可写性判定唯一来源 = `permissions.push`） | ✅ |
| 3.4 | `PagedListState`（分页状态机）· `RepositoryDataSource` · `LoadRepositoriesPage` | ✅ |
| 3.5 | 设计系统：`CompactNumber`（k/m 缩写）· `LanguageColor`（linguist 词表 + 中性回退）· `SkeletonBar` | ✅ |
| 3.6 | 表现层：`ReposView` 重写 + `RepoCard` / `RepoCardSkeleton` / `RepoListViewModel` + `AppEnvironment` 装配 | ✅ |
| 3.7 | 文档同步 + `make verify` 闭环 | ✅ |

**五包单测 510 项全过**（GitHubAPI 264 · GitDuoAuth 57 · GitDuoCore 50 · GitDuoDesign 28 · GitDuoKit 111）。
⚠️ 网络桩件状态**按命名空间隔离**（每套件自持 `Harness`）⇒ 网络测试可自由并行，**不要加 `.serialized`**；忘了用 harness 会当场失败，那是**有意**的。

### 切片 1（Auth）—— 已验收

| # | 内容 | 状态 |
|---|---|---|
| 1.1 | `KeychainTokenStore`（GitDuoCore）—— 真实 Keychain，替换骨架期内存占位 | ✅（前置条件 **P4 已消解**） |
| 1.2 | `GitHubOAuthClient` / `GitHubAppCredentials`（GitHubAPI）—— 换令牌 / 刷新 / 撤销 | ✅ |
| 1.3 | `OAuthCallback`（GitHubAPI）—— 形状校验 + 一次性 `state` | ✅ |
| 1.4 | `AuthCoordinator`（**GitDuoAuth**，决策 #31）—— 授权编排 + **single-flight** 刷新 | ✅ |
| 1.5 | 登出四步：撤销 → 清 Keychain → 清账号数据 → 重置导航栈 | ✅ ①②④ 落地 + ③ 中**接口缓存**已收口（`AuthCoordinator.signOut` → `HTTPCachePurging`）；③ 其余项待各 Feature 存储就位后接入 |
| 1.6 | 登录段原型断言转 Swift 测试（权限 6 项 + 三项产品承诺） | ✅ |
| 1.7 | 门禁接线：`RootView` 二分 + `LoginFlowView` + `WebAuthenticationSession` | ✅ |

### 切片 2（GitHubAPI 客户端骨架）—— 2.1–2.6 全部落地（2026-10-06）

| # | 内容 | 状态 |
|---|---|---|
| 2.1 | 错误模型（9 case，含 5xx 兜底 `serverError`）+ 限流头解析 + `RateLimiter`（令牌桶 + 串行闸门） | ✅ |
| 2.2 | `Link` 分页解析 + `Page<T>`（**不能 `split(",")`**：URL 里可能有逗号） | ✅ |
| 2.3 | 自建 HTTP 响应缓存（内存 + 磁盘双层、LRU、`no-store` 尊重、写后按前缀失效） | ✅ |
| 2.4 | `HTTPTransport` —— 统一请求头 / 令牌 / ETag 条件请求 / 401 重放 / 错误归一化 / 幂等 GET 退避 | ✅ |
| 2.5 | `AuthCoordinator` 实现 `AccessTokenProviding`（**错误在出口归一化**，决策 #33）+ 配额闸门接线 + `GitHubRESTClient` + `GitHubGraphQLClient`（部分成功**抛错但带数据**） | ✅ |
| 2.6 | `GET /user` 迁到新通道（`explicitToken` 解决"令牌还没进 Keychain"的空窗）+ 文档同步 | ✅ |

▶ **当前切片 = 切片 4**（首页 + 探索 + 详情：置顶只读 / 双榜 / 只读态）。**下一步 = 4.4 表现层**；动手前先读 `REVIEW-CHECKLIST.md` §1 的正本。

✅ **1.8 真机验收 10/10 全过 → 切片 1 验收完成**（2026-10-06，iPhone 17 Pro，自动签名已打通）：
真授权（授权页权限 6 条＝P2）→ 令牌落 Keychain → **杀进程重启仍登录** →
自动跳回 App（回调可用＝P3）→ 登出回登录页 → **GitHub 侧那条授权记录真的消失了** →
**飞行模式下冷启动仍在主界面**（断网 ≠ 登出）→ 登出后 `Cache.db` **连一个 URL 都不剩**。
**逐步流程、验收清单、错误对照见 `DEVICE-TESTING.md`**（`make device` 一键：构建 → 安装 → 启动）。
⚠️ **真机上的一条硬经验**：改掉写入路径**不会**清除已经落盘的副本 —— 发现磁盘上有敏感残留时，
除了修写入路径，还要问"**谁负责清它**"（本项目补在 `AuthCoordinator.signOut`）。
⚠️ **同类第二课（同一天，更隐蔽）**：`URLCache` 落盘的**不只是响应体，还有序列化请求对象** ⇒
一个"响应里没有凭据"的请求（`GET /user`）照样把 `Authorization: Bearer ghu_…` 写进 `Cache.db`。
**"响应不含机密"推不出"这个请求可以走系统缓存"**；本包现在**所有出网会话都不挂 `URLCache`**（见 `GitHubURLSession`，决策 #32）。

未落地的界面一律用 `SkeletonScreen` 占位，**没有假数据冒充成品**（登记见 `AppEnvironment.swift`）。

---

## 1. 事实来源与优先级

| 文件 | 视角 | 用途 |
|---|---|---|
| `redesign/prototype/` | **唯一可点验收依据**（入口 `index.html`；`scripts/` 16 个 JS · `styles/` 5 个 CSS） | 交互、文案、布局的最终裁决者 |
| `PRD.md` | 产品 | 行为、文案、边界（**不得出现实现细节**） |
| `TECH_SPEC.md` | 技术 | 架构、API 映射、配额、数据模型、决策表（**70 项全部【已定】**） |
| `REVIEW-CHECKLIST.md` | 评审 + **切片计划正本** | 切片顺序 §1 · 完成定义 §2 · 前置条件 §3 · 断言→切片映射 §4 · **决策记录 D1–D4（已全部拍板）** §5 |
| `GITHUB-APP-SETUP.md` | 运维 | GitHub App 的手把手配置（表单逐栏值、权限 6 项、自检清单、错误码对照） |
| `DEVICE-TESTING.md` | 运维 | 真机测试：一次性准备（含 🔒 无法自动化的一步）、`make device`、1.8 验收清单、错误对照、真机才能验的 5 件事 |

**冲突裁决顺序：原型 > TECH_SPEC > PRD > 任何推测。**
发现三者不一致时：**先报告，不要自行选一个实现**。

⚠️ 原型是**多文件**页面（`redesign/prototype/`）：入口 `index.html` + `styles/` 5 个 CSS + `scripts/` 16 个 JS。
   16 个 JS **共享同一全局作用域，加载顺序即依赖顺序**（无 import/export，const 没有提升）；
   **不要给 script 加 `type="module"`** —— `file://` 下会被 CORS 拦掉，原型就没法双击打开了。
⚠️ 原型有一份 jsdom 回归脚本（**262 条断言**），它记录了历次讨论的结论。
位置：`/Users/jiangjiang/.workbuddy/binaries/node/workspace/harness.js`（在仓库外）。
它是**规格的结晶**，切片落地时按域逐条转成 Swift 测试，不要凭记忆重写行为。

---

## 2. 命令（验证闭环的唯一入口）

```bash
make gen      # xcodegen 生成 GitDuo.xcodeproj（改 project.yml / 增删文件后必跑）
make test     # 五个包的单测（Swift Testing，秒级）
make build    # 为 iOS 模拟器构建 App（不签名）
make verify   # 以上全跑 —— 提交前必跑
make device   # 真机：构建(带签名) → 安装 → 启动 —— 手测用，见 DEVICE-TESTING.md
```

> `make device` 与 `make verify` **互不影响**：前者需要 `Secrets.xcconfig` 里的 `GITDUO_DEVELOPMENT_TEAM`
> 且要设备在线；后者走 `CODE_SIGNING_ALLOWED=NO`，没有签名配置也能跑 ⇒ 保住秒级闭环。

**没有可执行的验证命令的改动，等于没做。** 改完必须给出 `make verify` 的结果。

> ⚠️ **`make test` 一个字都不编译 App target**（`GitDuo/**`）—— 它只跑五个 SwiftPM 包。
> 改 `GitDuo/**` 后**必须 `make verify`**（= `test` + `build`）。只跑 `make test` 会拿到"全绿"，
> 而 App 层可能**根本编不过**。**2026-10-07 实锤**：4.4 的视图/VM 全部写完后从未被编译过，
> 一编就是一片错（`AppEnvironment` 缺 6 个成员等），用户先发现了。

> ⚠️ **"页面没写完"不会产生任何失败信号 —— 这是本项目最危险的一类静默。**
> 未落地的路由显示的是 `SkeletonScreen`：**编译通过、能跑、四处无红灯**；`RouteView` 的穷尽性检查
> 只保证"每个 `Route` 有分支"，**不保证"分支不是占位屏"**（它的注释写"不会静默漏页"，指的是另一件事）。
> `SkeletonPlaceholders.registry` 也只是**手写字符串**，没有任何东西校验它与 `RouteView` 一致。
> ⇒ 宣称某片做完前，**必须逐项点名施工图里的每一条**，并跑一次完成定义**第 3 条（与原型逐屏对照）**
> —— 它是 4 条里**唯一**能发现"页面缺失"的一条（前两条 `make verify` 全绿、第 4 条文档还是自己写的）。
> **2026-10-07 实锤**：4.4 报"已落地"时实际 5 屏只做了 3 屏，而 `AGENTS.md` 与状态笔记都写着 ✅。

### ⚠️ 沙箱：报 `sandbox_apply: Operation not permitted` 时**不要改代码**

**口诀：只要出现 `sandbox_apply: Operation not permitted`，一律是运行环境问题。** 它长得极像工程坏了。

机理：某些受限运行环境（如被外层沙箱包裹的 shell）里，内核**拒绝一切嵌套 `sandbox-exec`** ——
`(allow default)` 能应用，`(deny default)` 一律被拒。而 SwiftPM 与 Xcode **都会用 `sandbox-exec` 包裹子进程**，
于是**同时**踩两个坑，且症状完全不同，极易把第二个误判成"源码写错了"：

| 坑 | 症状 |
|---|---|
| ① **包解析**：SwiftPM 用沙箱编译 `Package.swift` 清单 | `xcodebuild: error: Could not resolve package dependencies: sandbox_apply…`（**每个包一行**） |
| ② **宏展开**：编译器用沙箱拉起 `swift-plugin-server` | `@Observable` / `@State` / `#Preview` 报 *"produced malformed response"* —— **源码没问题**，宏根本没跑起来 |

**本项目已在 `Makefile` 里自愈**（2026-10-06）：`sandbox-fix` 目标先探测本机沙箱是否可用，
**探测通过 ⇒ 三个开关全为空，行为与从前一字不差**（健康机器上等于什么都没做）；探测失败才补开关。
`build` / `device` 已自动带上，无需手工干预。跳过偏好写入：`make build SANDBOX_FIX=`。

两个坑的开关不同，都不是"换个命令"能绕开的（**以下全是试过的死路，别再试**）：

- 🚫 `-IDEPackageSupportDisableManifestSandbox` —— **不是 `xcodebuild` 的合法参数**（会只吐帮助文本）
- 🚫 `SWIFTC_DISABLE_SANDBOX` / 任何环境变量形式 —— 管的是编译器子进程，**管不到清单沙箱**
- 🚫 PATH 前置一个假的 `sandbox-exec` —— SwiftPM 里 `/usr/bin/sandbox-exec` 是**硬编码绝对路径**
- 🚫 `HOME=<临时目录>` 隔离偏好 —— xcodebuild 走**真实用户偏好域**，不认 `$HOME`
- 🚫 只预热 `swift package` 的清单缓存 —— Xcode 用的是**自己内嵌的 SwiftPM**，不共享那份缓存
- ✅ 真正的开关：`swift`/`swiftc` 认 `--disable-sandbox` / `-disable-sandbox`；
  Xcode 清单沙箱**只认用户默认值** `IDEPackageSupportDisableManifestSandbox`
  （撤销：`defaults delete com.apple.dt.Xcode IDEPackageSupportDisableManifestSandbox`）

> 🕳️ **两个更隐蔽的次生坑（2026-10-05 实测踩到）**：
> 1. **放后台执行时沙箱豁免不生效** —— 但注意：**别只看这一条就断定"必须前台"**，先用上面的办法确认真因。
> 2. **`rm -rf <大目录>` 会被安全机制拦截** —— 拦截后 `&&` 短路、**后续命令压根没执行**，
>    而日志文件里还留着上一次的内容 ⇒ 看起来"跑了但没通过"。
>    **别用 `rm -rf` 做 clean**，直接让 xcodebuild 增量构建（`make clean` 里的 `rm -rf` 同样会被拦）。
>    ⚠️ 2026-10-06 又踩了一次：`rm -rf build/DerivedData && make verify` 被拦 ⇒ 整条短路、`make verify` 根本没跑。

---

## 3. 架构铁律（违反即返工）

```
表现层 Features/  →  领域层 Repository/UseCase  →  数据层 Client/Store
```
- **依赖单向**：数据层不得引用上层类型；领域层**不得出现 SwiftUI 类型**。
- `AppEnvironment` 是**唯一依赖装配点**（`GitDuo/App/AppEnvironment.swift`）。
  View / ViewModel **不得自行构造客户端**。
- **五个 Package** + App target（`Packages/` 与 `GitDuo/`）：
  `GitHubAPI`（网络 + OAuth **客户端**）· `GitDuoCore`（Keychain 等本地基础设施）·
  `GitDuoAuth`（认证**编排**，**决策 #31**）· `GitDuoDesign`（令牌 + 组件 + 玻璃封装）·
  **`GitDuoKit`（领域层，决策 #34）** · `GitDuo` App target（组合根 + 页面）。
  依赖铁律：`GitDuoDesign → GitDuoCore`；`GitDuoAuth → GitHubAPI + GitDuoCore`；`GitDuoKit → GitHubAPI + GitDuoCore`；**其余互不依赖**。
  ⚠️ `GitHubAPI` **绝不能** import `GitDuoAuth`（会成环）；**数据层不得引用领域层** ⇒ `GitHubAPI` 里只有 `RepositoryDTO`、没有 `Repository`。
  ⚠️ `GitDuoKit` **不得 import SwiftUI**（只出"是什么"，不出"长什么样"）。
  ⚠️ 编排为什么单独一层：它要**同时**用 `GitHubAPI`（换令牌）与 `GitDuoCore`（写 Keychain），
  而这两包互不依赖 ⇒ 只能在两者**之上**；落在包里而非 App，是为了能跑单测（App 无测试 target）。
  ⚠️ 领域层为什么也单独成包（决策 #34）：**同样的理由** —— 可写性判定与分页状态机最需要被单测钉住，
  放进没有测试 target 的 App 里等于只靠人工点击保证正确性。
- 四个 Tab **各持一条独立 `NavigationStack`**。路由逻辑一律经 `Router.path(for:)` 按 `selection` 取栈，
  **禁止写死某个 Tab 的栈**（原型阶段因此出过导航错乱）。
- 路由用值类型枚举 `Route` + `navigationDestination(for:)`；
  **禁止** `NavigationLink(destination:)` 闭包式写法（难单测、难程序化导航）。
  `RouteView` 的 switch 必须穷尽——新增 case 忘记接线应当**编译失败**，这是有意的。

---

## 4. 编码铁律

| # | 铁律 | 原因 / 出处 |
|---|---|---|
| 1 | **零第三方依赖**（含测试期尽量自建） | 决策 #12 / §11 |
| 2 | **Swift 6 严格并发**；App 层默认 MainActor，数据层 actor 隔离 | 决策 #9 / §12.1 |
| 3 | 颜色/字号/间距/圆角**一律引用 `Theme` 令牌**，禁写魔法值 | §10.7（为补深色预留，写死色值会导致全量返工） |
| 4 | `.glassEffect` **只允许出现在 `GitDuoDesign` 的组件封装内** | §10.2（玻璃只属导航层；业务代码直接调用必失控） |
| 5 | 玻璃**绝不用在内容层**（列表行、卡片、正文、图片） | §10.2 |
| 6 | 不用 `UIScreen.main`；布局看 size class 与容器尺寸 | PRD §1：**纯 iPhone，本期不做折叠屏 / iPad** |
| 7 | **只读态显式传参**（`readOnly:`），不让下层页自行推断仓库归属 | §8.2（可写性判定唯一来源 = `Repository.permissions.push`） |
| 8 | 凭据只进 Keychain；**绝不写入**日志 / 崩溃上报 / 剪贴板 / UserDefaults 明文 | §3.3 |
| 9 | `client_secret` **内嵌进 App**（构建期由 `Secrets.xcconfig` 注入，**不入库**）——官方 Required 且无法规避；它是**软机密**，只许出现在「换令牌 / 刷新 / 撤销」三条请求里，**不进日志、不进缓存、不进任何上报** | §3.1 / §3.7（决策 #30） |
| 10 | `code_verifier` 只存内存、**绝不随回调传输**；`state` 一次性 | §3.9（scheme 被抢注时唯一的防线） |
| 11 | "这个能力能不能做"**先查文档结论**（§3.9 / §16 已关闭项），不要凭直觉承诺 | 已核实：置顶无写 API、Revert 无端点、最近访问无 API、通知 API 不支持 App 令牌 |
| 12 | 加任何网络调用前，先看 §13.2 配额预算；GraphQL 单查询 ≤5 点 | 深层嵌套可一次烧掉 100 点 |
| 13 | 长任务/循环里的失败**不要静默吞掉**（尤其 404 与"无权限"被 GitHub 混同） | §14 |

---

## 5. 改动纪律

1. **先文档后代码**：新增/变更行为 → 先改 `PRD.md` + `TECH_SPEC.md`（含决策表与受影响章节）→ 再写代码。
   文档里的决策表是"已定"清单，**增删决策必须同步表末汇总行**。
2. **占位必须登记**：任何以占位（stub）形式存在的类型，登记到 `AppEnvironment.swift`
   底部的 `SkeletonPlaceholders.registry`；删除时一并删除登记项。
3. **文案是契约**：原型里的文案是验收依据；改文案要 grep 全仓（同一句话常散落 4–6 处）。
   行为类文案（承诺"会发生什么"）改完还要**真跑一遍**确认效果兑现得出。
4. **改完必须验证**：`make verify`；无法验证的改动要在回复里明确说"未验证 + 原因"。
5. **不要替用户拍板**：遇到文档未定义的点，写进 `REVIEW-CHECKLIST.md` 的"决策缺口"，
   给选项与推荐，**不要自定义一个值然后当成事实**（D1–D4 已全部拍板；新的待定点追加到该文件 §5）。
6. **提交**：一个切片一个提交；提交信息写"做了什么 + 为什么"，不写"update"。

---

## 6. 文档索引（要做什么 → 看哪一节）

| 要做的事 | 看这里 |
|---|---|
| 认证 / PKCE / 令牌刷新 / 权限 / 回调安全 | TECH_SPEC §3.1–§3.9；PRD §4.0 |
| 端点 ↔ 功能映射 | TECH_SPEC §4.6.x |
| 缓存 / ETag / 分页 | TECH_SPEC §4.4、§7.3 |
| 数据模型 | TECH_SPEC §6.2 |
| 持久化 / 登出清理范围 | TECH_SPEC §7.1、§7.2 |
| 导航 / 路由 / 弹层 / 加载态 | TECH_SPEC §8.1–§8.5 |
| 逐功能技术方案（Auth…Settings） | TECH_SPEC §9.1–§9.15 |
| Liquid Glass 规范与六个坑 | TECH_SPEC §10.1–§10.7 |
| 自研渲染（Markdown / diff / 高亮） | TECH_SPEC §11.1–§11.3 |
| 并发模型 / 测试策略 | TECH_SPEC §12.1、§12.2 |
| 配额与性能预算 | TECH_SPEC §13.2、§13.3 |
| 风险登记表 / 未来工作 | TECH_SPEC §15、§16 |
| 页面与行为（产品口径） | PRD §4（页面）· §5（弹层）· §6（横切） |
| 真机测试 / 手测验收 | `DEVICE-TESTING.md` |
| GitHub App 配置 / 凭据 | `GITHUB-APP-SETUP.md` · `Secrets.xcconfig.example` |

---

## 7. 切片计划 → 见 `REVIEW-CHECKLIST.md`（本节只放指针，不复制）

> **为什么是指针**：切片表原先在本节与 `REVIEW-CHECKLIST.md §1` 各存一份，而**两份都还在改**
> ⇒ 迟早"改一处漏一处"。**正本唯一 = `REVIEW-CHECKLIST.md`**，本节只负责指路。

| 要什么 | 正本位置 |
|---|---|
| 切片顺序、每片内容、对应 PRD 页面、验证方式、可否延后 | `REVIEW-CHECKLIST.md` **§1 清单 A** |
| 每片"做完"的 4 条定义（verify / 断言转测试 / 逐屏对照 / 文档同步） | `REVIEW-CHECKLIST.md` **§2 清单 B** |
| **本期明确不做**的 10 项（**动手前必看，防越界**） | `REVIEW-CHECKLIST.md` **§1 末** |
| 262 断言 → 切片的映射 | `REVIEW-CHECKLIST.md` **§4 清单 D** |
| 前置条件 P1–P6 状态 · 决策记录 D1–D4 | `REVIEW-CHECKLIST.md` **§3 / §5** |

> **排序原则（保留在此，它属于纪律）**：**先做能在本地 100% 验证的纯逻辑，最后做需要真机 / 真凭据的部分。**
> **当前进度**见本文 §0「当前阶段」。
