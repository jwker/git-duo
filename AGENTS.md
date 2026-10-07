# AGENTS.md —— GitDuo 2.0 的 AI 开发入口

> 这个文件是**每次动手前必读**的唯一入口：规则、命令、文档索引都在这里。
> 它与 `PRD.md` / `TECH_SPEC.md` 的关系：**规格看文档，纪律看这里**。

## 0. 当前阶段

**切片 1（Auth）已验收；切片 2（GitHubAPI 客户端骨架）2.1–2.6 已落地；切片 3（仓库列表）3.1–3.7 已落地；切片 4（首页 + 探索 + 详情）4.0–4.6 已落地；切片 5（搜索）5.0–5.6 全部落地；切片 6（文件查看 + 提交详情 + 分支管理 + 仓库详情外壳）6.0–6.6 全部落地，并已开始**陪跑目视修复（6.7 起，现已到 6.8）**。**
`make verify` = **五包单测 1063 项 + 模拟器构建**，一条命令，**零编译警告**。
（**GitHubAPI 337** · GitDuoAuth 57 · GitDuoCore 50 · GitDuoDesign **60** · **GitDuoKit 559**）

✅ **6.5 起「我的仓库列表 → 看代码」这条主线**真的通了 —— `RouteView` 里 `.repoDetail` /
`.fileView` / `.commitDetail` / `.branches` 四条已从占位屏换成真页面，四个入口
（仓库列表 / 首页置顶 / 最近访问 / 搜索）都点得进去。

✅ **完成定义第 3 条「与原型逐屏对照」已经开跑（2026-10-07）**，不再是一次都没做过。
第 1 批报回来 5 条，**前 4 条是真缺陷（已修，见 6.7 与 `REVIEW-CHECKLIST §6`）、第 5 条是拍过板的设计**：
① 首页「清除」确认是系统动作表（贴屏幕底）而 PRD §5.1 与原型要的是弹层；
② README 里的 HTML 标签**原样打出来**（真实 README 大量用 `<p align>/<img>/<br>/<details>`）；
③ README 里的**仓库内相对链接点了没反应**（`[中文](README_zh.md)`）；
④ 搜索回车后**键盘一直挂着**，不收起；
⑤ 「＋ 添加 / 编辑 / 历史 / 更多」**点不动** —— 这一条**是决策 #51（有意为之）**，不是接线漏了。
   ✅ **已裁定（2026-10-07）：保持现状** —— 四个候选（保持现状 / 改灰 / 先藏着 / 提前做编辑器）里用户选第一个：
   **本轮不改代码，等切片 8（编辑器）一起接上**。
   ⚠️ 已知代价：这几个按钮"看起来能点"，本轮目视已经被命中过一次 ⇒ **别再当缺陷报/改**；
   真要动它，等于同时改 `AGENTS.md §0`、`PRD §4.4` 与已验收口径。
**清单正本在 `REVIEW-CHECKLIST §6` 末尾（页级 12 项 + 逐项细则 82 条 + 已知有意偏差 22 条 + 已完成 6.7 / 6.8）**：
**截至 2026-10-07 已过 11 / 12，只剩「五个弹层」**（看正本那张表的状态列）：
- 切片 4 / 5 交的 7 项 —— 首页（✅ 6.7①）· 探索（双榜）✅ · 探索仓库详情 ✅ · 探索 Issues 列表 ✅ ·
  探索 PR 列表 ✅ · 搜索页（✅ 6.7④）· 用户资料弹层 ✅；
- 切片 6 交的 5 项 —— 仓库详情（§4.4 四分段）（✅ 6.7⑤）· 文件查看（§4.5 三档结局）（✅ 6.7⑤）·
  提交详情（§4.7）✅ · 分支管理（§4.8）✅ · **五个弹层（§5.7 切换分支 / 新建 / 删除 / 合并 / §5.8 添加文件）⬜**。

✅ **目视陪跑里用户自己试出的一条（6.8）**：在「新建分支」连试 `～` 与 `？`（**全角** —— 中文输入法下打 `~` `?` 的默认手感）
**都建成功了**。判定**不是缺陷**：git 的 `check_refname_format` 只禁**半角**那八个，全角同形字是**独立码位**，
`git` 与 GitHub 都收（实测：半角八个全拒 / 全角同形字全收，客户端逐条一致；非 ASCII 名字的 URL 编码实测也读得回来）。
⚠️ 但顺着这条探到一个**真缺口**：禁用字符的判据**按 `Character`（字素簇）比** ⇒「禁用字符 + 组合记号」（`~\u{0301}`）
在客户端**放行**、到服务端吃 422 —— **正是 `BranchName` 开头写明它存在的那条理由**。已改为**按 Unicode 标量判**，
并修掉提示语把命中字符**印两遍**。⚠️ **只堵漏、不加规则**：全角照旧放行；`@{` 维持原判不动。

⇒ **接着跑**两件事：① **五个弹层**（唯一没过的一项；⚠️ 删除 / 合并是**真写操作**，只看形态、别真删真合）；
② 探索仓库详情的 README 那两条（6.7②③，HTML 与内链）修完要**回头复看一次**。

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
> （逐屏对照，**零次**）—— **该账已于同日 6.7 开跑，现行进度见本文档 §0（截至 2026-10-07 已过 11 / 12）**。

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
> ⚠️ **这条欠账从 6.5 起就不再成立理由**（那四个新页面已可达），**2026-10-07 的 6.7 已正式开跑** ——
> 现行进度见本文档 §0 与 `REVIEW-CHECKLIST §6` 末尾（12 项，截至 2026-10-07 **已过 11**、只剩「五个弹层」）。

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
| `TECH_SPEC.md` | 技术 | 架构、API 映射、配额、数据模型、决策表（**43 项全部【已定】**） |
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
