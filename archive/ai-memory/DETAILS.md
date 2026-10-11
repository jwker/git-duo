# DETAILS.md —— 模块级细节与逐条陷阱

> `MEMORY.md` 的附属文件：那里放**规则与索引**，这里放**穷举型的细节**（数据层每个易踩点、令牌与组件清单、各切片的落点）。
> 需要动数据层 / 设计系统 / 搜索表现层时读本文件。**动手前仍先读 `AGENTS.md`。**

## 1. 数据层（切片 2 / 4.2 / 5.2）

`HTTPTransport` 是**唯一出网通道**，收口六件事：统一请求头 · 令牌注入 · ETag 条件请求（304 不计配额）· 401→刷新→**重放一次** · 错误归一化 · 配额闸门。两个客户端都不发网络：`GitHubRESTClient` 管路径/查询串/解码/`Link` 分页，`GitHubGraphQLClient` 管 `{query,variables}` 与 `body.errors`。

⚠️ 容易踩反的：
- **`GitHubError` 9 case**：8 个来自 §4.3 + 兜底 `serverError(status:)`（5xx 与"其余未归类"都落这里）⇒ **判"能不能重试"必须再看 `status` 是否 5xx**，不能只看 case 名。
- **`graphQLErrors(messages:partialData:)` 必须带数据**（GraphQL 会部分成功，只抛错会丢已拿到的内容）。解析**两段式**：快路 `Envelope<T>` 一次解码 → 慢路 `JSONSerialization` 取 `errors` + 原始 `data`。⚠️ `path` 里可能是数字下标 ⇒ 逐元素 `"\($0)"`。
- **403 有三义**，只靠响应头区分：主桶耗尽（`remaining == 0`）/ 二级限流（有 `Retry-After`，**秒数与 HTTP-date 两种都认**）/ 权限不足。
- **`Link` 头不能 `split(",")`** —— URL 里可能有逗号，会静默少一页；按 `<…>` 括注分段。
- **配额闸门接在「每一次尝试」上**（重试也消耗）；`rateLimitResource` 默认 `.core`（间隔 0），**搜索类必须显式声明**（`.search` / 代码 `.codeSearch`）；映射不到已知桶 ⇒ **不限速，不落回 `.core`**；代码搜索额外**串行**。
- **缓存自建**（`HTTPResponseCache`：内存+磁盘、LRU、尊重 `no-store`、写后按前缀失效），**绝不启用系统 `URLCache`**。`invalidate(pathPrefix:)` 匹配**必须含"相等"且补斜杠**。`entry(for:)` **有意不判过期**（ETag 长期有效）。
- ⚠️ **204 会被写进响应缓存**（`CachedHTTPResponse.isStorable` 只挡 `no-store`、不看状态码）⇒ 直接读缓存的一方必须先看 `statusCode`。
- **`GET /user` 折返表不可照抄**：`GitHubUserEndpoint` 对外仍抛 `OAuthError`（保住切片 1 契约），是**唯一**例外路径。
- **`GitHubJSON.decoder()` 是唯一解码器**：`dateDecodingStrategy = .custom` 认 ISO 8601（⚠️ 不配就整页解不出）；有意**不**用 `.convertFromSnakeCase`（键没转过来不报错、只静默变 `nil`；显式 `CodingKeys` 才可 grep）。
- **`SearchRepositoryDTO` 有意不复用 `RepositoryDTO`**：搜索响应**不返回 `permissions`** ⇒ 复用会让 `canWrite` 恒 `false`，而搜索结果里**也可能是你自己的仓库**。（`total_count` 已按 #44 接出来 —— 探索榜标题仍用"已加载条数"，搜索页用 `total_count`，**不矛盾**：数字必须是"对屏幕上这个列表的真话"。）
- **`RepositoryDetailDTO` 的 Watch 数读 `subscribers_count`**，**不是 `watchers_count`**（后者是 `stargazers_count` 历史别名）；`open_issues_count` **有意不解码**。
- **`latestRelease` 是唯一「404 → nil」处**；**只有 404 可吞**，5xx / 断网必抛。`contributors` 空仓库回 **204 No Content** ⇒ **必须先认状态码再解码**。
- **`RepoContributorDTO` 的 `login`/`avatar_url` 都可空且必须**（GitHub 只把前 500 个邮箱关联到账号）。**`IssueDTO.pullRequest`** 是空结构体；**数据层不过滤 PR**。`PullRequestDTO.isMerged` 存在是因为每个调用点各写一次那句判断、**总有一处漏 `merged_at`**。
- **`GitHubPinnedItemsEndpoint`**（GraphQL `pinnedItems(first:6)`，1 点）：⚠️ GraphQL 是 `stargazerCount`（单数）、REST 是 `stargazers_count`（复数），写错不报错只整条失败；`nodes` 元素**可空**（失效置顶回 `null`）；`... on Repository` **必须**（元素是 union）。

**搜索接缝的分层（5.2）**：`SearchResult<Item>` = 四端点**唯一解码入口** `SearchResult.decoded(from:)`（`Envelope<Item>` 用显式 `CodingKeys`）· `sort` 改**可选**（nil ⇒ 不带 sort/order = 服务端 best match）· `q` 校验收进 `SearchEndpointSupport`（空 q 必 422，**那次失败照样扣配额**）· 三个新端点 + DTO（`users`/`code`/`issues`）· `SearchRowMapper`（行级纯映射：类型取自响应不猜、`repository_url` 走契约解析三段且首段 `repos`）· `SearchEndpoints` 接缝 · `GitHubSearchDataSource` 适配器（按 `part.scope` 分发；⚠️ **配错端点只有单测能抓** —— 症状是"该范围永远搜不到东西"而不是报错）· `SearchQueryPart` 补 `scope` · `PullRequestState(state:mergedAt:)` 把"已合并"判定收进唯一初始化器。

**`LoadSearch`（actor）**：四件事钉在一处 —— 拼查询（`SearchQueryBuilder`，纯逻辑已单测）· 按 part 分发并合并 · 累加去重（按 `SearchRow.id`，**保留先到的**）· 按「范围 · 关键词」LRU（容量 12）。
- **已到底不再出网**：`reset == false` 且各 part 游标全 `nil` ⇒ 直接返缓存，**一发请求都不发**（漏了 ⇒「加载更多」在到底后每点一次白扣配额，Issue·PR 是**两格**）。
- **续页是追加不是重排**：重排会把新条目插到已渲染列表的中段（Issue·PR 范围尤其明显 ⇒ 滚动位置当场跳走）。代价是整份列表非全局有序。
- **还有游标的那条才发**，到底的那条**跳过**（用上一次的游标与计数）。
- **任一条 part 失败 ⇒ 整次失败，且不改动缓存**（`try` 抛在写回之前 ⇒ 已加载内容留在屏幕上、游标不丢）；不做"哪条成功写哪条"（会让计数与游标进入"一半新一半旧"，用户无从判断屏幕上是哪一版）。
- `Result.totalCount` = 各 part **之和**（issue 与 PR 是不相交集合，相加不重复计）；`hasMore` = **任一** part 还有游标。

## 2. 设计系统（`GitDuoDesign`，只收基础类型、绝不认识领域模型）

- `RepoAvatar` —— 深底 `#24292f` + 白色**文件夹**字形；三档 `standard`(34) / `row`(30) / `compact`(32)。（切片 3 的 `RepoCard` 已按用户拍板改回复用它，同一 App 里不再有两种仓库图标。）
- `StatButton` —— ⚠️ **激活态图标由调用方显式给**：`arrow.triangle.branch` **没有 `.fill` 变体**，靠"名字追加 `.fill`"推导会拿到**不存在的符号名** ⇒ 图标凭空消失且不报错。
- `AvatarStack` —— ⚠️ 兜底色用 **djb2 稳定哈希**，**绝不能用 `hashValue`**（每进程带随机种子 ⇒ 同一账号每次冷启动换色）；`login`/`avatarURL` **都可空**。
- `LanguageBar` —— ⚠️ 各段宽度**让最后一段吃掉舍入余数**；图例用 `ViewThatFits`，**不截断语言名**。
- **5.3 三件**：`StatusPill`（⚠️ **只有三族不是四族** —— 原型四个类名但 `.closed-i` 与 `.merged` 配色逐字相同；只收 `title`+`tone`，不收 `PullRequestState`）· `CodePreviewLine`（只收一段 `String`，**单行截尾** —— 折行会让一条结果变三行）· `UserAvatar`（`rowDiameter` 34 / `sheetDiameter` 52；**首字母 + djb2 兜底色下标从 `AvatarStack` 私有提为公开纯函数** `UserAvatar.initial(for:)` / `UserAvatar.colorIndex(for:)`（须标 `nonisolated`），`AvatarStack` 改为委派）。
- `GitDuoCore/Format/`：`GroupedNumber`（千分位全量 `2,341`；**与 `CompactNumber` 有意并存** —— 原型卡片侧 `124k`、头部统计侧 `11,240`；手写分组**不用 `NumberFormatter`**，分组符随 `Locale` 变）· `LanguageComposition`（各段百分比之和恒 100，最大余数法；放 `GitDuoCore` 因 `GitDuoDesign` 不得依赖 `GitDuoKit`）。
- 令牌：`starActive`(#EAC54F) · `shareNeutral`(#D1D5DA) · `repoAvatarSurface`(#24292F) · `avatarFallback`(8 色) · `Font.label`(12pt) · **5.3**：`codeSurface`（⚠️ 与 `background` 同值但**不是同一 token**）· 状态胶囊三族底/边 6 个 · `Font.tag`(11pt semibold) · `Font.monospacedPreview`(11.5px) · **5.4**：`Radius.field`(11，原型 `.searchfield` 与 `.iconbtn` 同为 11)。
  ⚠️ **已知偏差（未改）**：`starActive` 压在 `surfaceSunken` 上只有 **≈1.48:1**（非文字图形门槛 3:1）。接受理由：**不是唯一线索**（"已 Star"同时由文案与星形填充表达）。护栏断言同时钉住「≥1.4」与「仍 < 3.0」。**绝不许用作文字色 / 背景色**。同理 `textTertiary` 在页面底 **2.89:1**（门槛 3:1），护栏是「≥ 2.85」。
- 卡片留各自 Feature：`Home/Components/{PinCard,RecentRow}` · `Explore/Components/TrendCard`。⚠️ `TrendCard` 仓库名用**链接色**。⚠️ **`RecentRow` 不收 `RepoSummary`**（参数是基础类型；`description`/`isPrivate` **无默认值**，`nil` 表达"调用方手上没有"）。

## 3. 切片 5.4 表现层（`GitDuo/Features/Search/`）

- `Components/`：`SearchField`（`.searchfield` 逐字：gap 8 / padding 8·10 / radius 11 / 清除圆 19、xmark 11pt bold；`@Binding text` + `@FocusState.Binding`；清除时 `text = ""; isFocused = true`）· `SearchRowBox`（`.sr-item` 泛型容器：`padding(.vertical, 11)` + `.horizontal(Theme.Spacing.xxs)`）· `SearchResultRows`（`SearchRowView` 四路分派 + `RepositoryResultRow` / `UserResultRow` / `CodeResultRow`（`alignment: .top`，**无尖角**）/ `ConversationResultRow` + 共用 `RowChevron`）· `SearchIdleSection`（最近搜索 + `EmptyBox` + 热门词 `FlowLayout`）· `SearchResultsSkeleton`（骨架屏对齐 `SearchRowBox` 的 11/11/2 几何）· `UserProfileSheet`（§5.10 弹层 + 私有 `SheetActionButton`）。
- `ViewModels/SearchViewModel.swift`：`@MainActor @Observable`，`Content` 六态（`idle`/`needsKeyword`/`skeleton`/`rows`/`empty`/`failure`）、私有 `Load` + `Combo`、防抖（缓存命中**不**防抖）+ `token` 取消 + LRU 缓存优先 + 分页 + 历史。
- `SearchView.swift`：顶部 `SearchField` + `SegmentedBar` **钉在滚动区之外**；`keywordBinding` 用**显式 `Binding`**（不用 `@Bindable`+`.onChange`）；`.task { await model.loadHistory(); isFieldFocused = true }`（焦点放在 `await` **之后**，否则键盘不弹而代码看起来没错）；`open(_:)` 先 `recordCurrentTerm()` 再跳路由。
- ⚠️ **不复用 `LinkRow`**、新写 `SearchRowBox`：与 `.file-row` 不只差 1–2pt（`11px 2px` vs `11px 4px`、图标 16 vs 17+frame 20），**语义也不同** —— `LinkRow` 是"可导航的链接行"（链接色 + 按下态），而 `.sr-item` 里有一半（用户行 / 代码行的非链接部分）不是那个意思。复用会让后续改 `LinkRow` 意外波及搜索结果行。差异已登记在注释里。
- **两个概念要分清**：`SearchDebounce`（300ms / 代码 500ms = 「什么时候发」）与 `SearchRequestToken`（「发回来的还要不要」）。只防抖不够 —— 先输 `swi` 再输 `swiftui`，若 `swi` 的响应后到，屏幕上留下的是 `swi` 的结果而输入框里写着 `swiftui`。
- **状态族**：`.closed` 的画法取决于 `kind`（已关闭 Issue = `completed` 紫族、已关闭未合并 PR = `closed` 红族）⇒ 上提为领域层 `ConversationHit.statusTone`（`ConversationStatusTone` 三值，名字**有意不与** `StatusPill.Tone` 同名，沿 `TrendingMetric.Role` / `TrendCard.Badge` 先例）。`PullRequestState.pillTitle` 是英文胶囊词（`Open`/`Merged`/`Closed`，与中文读屏 `label` **刻意分开并存**；**有意不带**原型前置字形 `●`/`⇿`）。
- ⚠️ `SearchViewModel.Load.loaded` 把**结果与"它属于哪个组合"绑在一起存**：分开存会出现"关键词已经换成新的、屏幕上还是上一个关键词的结果"那一帧 —— 而它**看起来完全正常**（有内容、有标题、不报错），只是结果不对。配套：`content` 里"手上这份属于别的组合"与"正在加载"**都返回骨架屏**。
- `recordCurrentTerm()` **同步**取词（落盘在内部分起一个不等候的 `Task`）：调用它的那一刻页面就要跳走，用户回来很可能立刻改关键词；把取词放进 `Task` 里读，读到的会是**改过之后**的词 ⇒「最近搜索」里留下一条从没搜过的词。
- **未定两处（已登记，未替用户拍板）**：① 会话行的状态**图标**是否按状态给（已合并 ⇒ 汇合箭头），原型只按 `kind` 二分；② `SearchHotKeywords` 里「设计令牌」/「折叠屏」是否替换（后者与 PRD §1「纯不做折叠屏」相冲）。另有两处待裁定：`/search/users` 的 `public_repos`/`followers` 是否逐条补 `GET /users/{login}`。

## 4. 切片 5.5 装配（`AppEnvironment`）

- `search: LoadSearch`（**单实例** —— 缓存活在它里面；§4.2 要求切范围"不清空已加载的页"，而搜索桶只有 30/min）。
  构造只走 `GitHubSearchDataSource(client: client)` 一句 —— ⚠️ 四个端点在它内部由**同一个** `client` 生成；在组合根 new 四个端点再各传一个，会让缓存分成几份、配额各算各的，而且**不报错**。
- `searchHistory: any SearchHistoryStore` → `UserDefaultsSearchHistoryStore`（`GitDuo/App/Stores/UserDefaultsStores.swift`）。与 `UserDefaultsRecentVisitStore` 逐条同构（语义在领域包的 `InMemorySearchHistoryStore`，编解码走 `SearchHistoryCoding`）。
  ⚠️ 键前缀**必须**与 `recentVisits` 不同（`GitDuo.searchHistory` vs `GitDuo.recentVisits`）—— 共用前缀只是在等一次"清 A 顺手清掉 B"。
- `signOut()` ③ 步补两条：`searchHistory.clear()` + **`search.invalidateAll()`**。后者容易漏且后果具体：`LoadSearch` 缓存的是**上一个账号搜出来的结果**（含私有仓库名）。

## 5. 真机测试的逐条坑（先读 `MEMORY.md §6` 的判据）

- **URLCache 三课（已修，#30/#32）**：
  ① 默认缓存策略把**换令牌响应**（含 `access_token`/`refresh_token`）落盘到 `Library/Caches/<bundle>/Cache.db`；
  ② **改写入路径不清残留** ⇒ 登出显式清（`HTTPCachePurging`，`GitDuoCore`）；
  ③ **`URLCache` 连「序列化请求对象」一起落盘**（`proto_props` 里明文 `Authorization: Bearer ghu_…`）
  ⇒ `GET /user` 这种"响应干净"的请求照样泄。
  **结论：本包所有出网会话都不挂 `URLCache`**（`GitHubURLSession.noCache()`）。
  ⚠️ **"响应不含机密"推不出"该请求可走系统缓存"**；只设 `URLRequest.cachePolicy` 挡不住（那是"取用"不是"存"）。
  ⚠️ **本条认识最贵**：改写入路径**只能阻止将来再写**，已落盘的副本只有显式清理才会消失。
- **读设备证据的坑**：同 URL 在 `URLCache` 是**替换非新增**（判"清干净"要条目归零 **+ 登出前基线**）·
  **重装 App 不清数据容器**（可用它做对照实验）· WAL 要连 `-wal`/`-shm` 一起拉 ·
  `cfurl_cache_response.time_stamp` 是 **TEXT(UTC)** 不是 CF 绝对时间，**直接读原列**。
  排查令牌落盘：`strings Cache.db Cache.db-wal | grep -c 'ghu_\|ghr_'`（**只看计数**）。
  ⚠️ **新常态：`Cache.db` 恒为 0 条** ⇒ ETag 缓存**自建存储**。
- **1.8 验收第 10 步的取证过程值得记**：修复前那次登录留下的 `api.github.com/user` 一条，
  在重装（**升级安装不清容器**）后理应仍在，而登出后**消失了** ⇒ 只能是被登出清理删掉的
  （首次那个"空"还夹着"重装可能清容器"的混淆项，第二次没有）。判据见 `DEVICE-TESTING.md §2`。
- **Swift 测试跨套件陷阱**：`URLProtocol` 桩件状态曾是**进程级全局**，而 Swift Testing **默认让不同套件并行**、
  `.serialized` 只管套件内部 ⇒ 第二个用桩件的套件一进来就"**单跑全绿、全量跑挂**"
  （失败信息还指向别处，极难定位）。现已全线改命名空间 `Harness`（会话挂附加请求头）+
  把"默认 harness"后门连根删掉（没有命名空间 ⇒ 请求当场失败），四处 `.serialized` 全撤，
  两包各配守卫套件 `StubURLProtocolIsolationTests` 把性质钉住。
- **`make device` 的 launch 失败不中断**是有意的：最高频原因是设备锁屏，而此刻构建与安装其实都已成功。
- **签名**：Team ID = **`35FZY67FQU`**（免费 Personal Team，**签名 7 天过期**，重跑续期），放 git-ignored 的 `Secrets.xcconfig`。
  ⚠️ **判据：见到 `No Accounts` 先对 Team、再怀疑账号** —— 钥匙串里有别的 Team 的旧证书残留
  （`59T955ND9K`，**正是 `security find-identity` 显示的那个**）⇒ 照它填会报极具误导性的 `No Accounts`。
- **`devicectl` 用法**：`device capture screenshot` · `device copy from --domain-type appDataContainer --domain-identifier <bundle-id>` ·
  `device info processes` / `process terminate --pid <pid> --kill`（**必须带 `--pid`**）。
  ⚠️ **不能模拟点击** ⇒ 分工永远是"用户动手、我事后核对"。
- ✅ **1.8 真机验收（2026-10-06）：10 步 10 过 ⇒ 切片 1 验收完成**（两条核心价值：**杀进程重启仍登录** · **GitHub 侧授权记录真的消失**）。
  流程见 `DEVICE-TESTING.md`。

## 6. 沙箱绕行：试过的死路与真开关（`MEMORY.md §2` 指向这里）

症状：`sandbox_apply: Operation not permitted`。它不是代码问题 —— 受限环境的内核**拒绝一切嵌套 `sandbox-exec`**：
`(allow default)` 能应用，`(deny default)` 一律失败。而 SwiftPM 与 Xcode 都会用 `sandbox-exec` 包裹子进程，于是同时踩两处：

1. **包解析** —— SwiftPM 用沙箱编译 `Package.swift` 清单 ⇒ `xcodebuild: error: Could not resolve package dependencies: sandbox_apply…`
2. **宏展开** —— 编译器用沙箱拉起 `swift-plugin-server` ⇒ `@Observable` / `@State` / `#Preview` 报
   **"produced malformed response"**（**极像源码写错，其实源码没错** —— 上一轮就是这么误判的）

两个坑的开关不同，且都**没有 per-invocation 的命令行形式**。**试过的死路（别再试）**：
- `-IDEPackageSupportDisableManifestSandbox` 直接当 xcodebuild 参数 —— 不是合法参数
- 环境变量（`IDEPackageSupportDisableManifestSandbox=YES` 导出） —— 无效
- PATH 前置一个假的 `sandbox-exec` —— 无效（系统硬编码绝对路径）
- `HOME` 隔离 —— 无效

**真开关**：`swift` / `swiftc` 认 `--disable-sandbox` / `-disable-sandbox`；
Xcode 清单沙箱**只认用户默认值** `IDEPackageSupportDisableManifestSandbox`（`defaults write com.apple.dt.Xcode …`）。

**策略（`Makefile` 已实现）**：**先探测** —— `/usr/bin/sandbox-exec -p '(version 1) (deny default)' /usr/bin/true` 失败才补开关。
本机沙箱正常 ⇒ 三个变量全为空，行为与从前一字不差；受限环境 ⇒ 自动补。跳过那次 `defaults write`：`make build SANDBOX_FIX=`；
恢复 SwiftPM 自身沙箱：`make test SWIFT_FLAGS=`。

## 7. 切片 6 相关端点的实测结论（2026-10-07，全部裸 curl + `X-GitHub-Api-Version: 2026-03-10`）

> 记这里的理由：这些都是**"看着显然、其实不成立"**的地方 —— 与决策 #47 / #53 同一类事故。
> 凡是结论依赖"某个端点会给我们什么"，**引原文或实测一次**，别按直觉写。

- **`GET /contents/{path}` 的目录清单不带任何提交信息**：项只有
  `name` / `path` / `sha` / `size` / `type` / `url` / `_links` / `git_url` / `html_url` / `download_url`。
  PRD §3.2 的「最近提交信息」只能**逐条补** `GET /commits?path={p}&per_page=1`（决策 #49）。
  `git/trees?recursive=1` 同样不含提交信息（`path`/`mode`/`type`/`sha`/`size`/`url`），别指望用它省请求。
- **contents 的大文件行为（实测）**：>1MB ⇒ **HTTP 200 + `encoding:"none"` + `content: ""`**
  （实测 `kubernetes/kubernetes` 的 `api/openapi-spec/swagger.json`，`size=4280356`）。
  该端点的 `Accept: application/vnd.github.raw` 对**同一个文件返回完整原文**（实测 `size_download=4280356`，
  首尾完整 —— 第一次测到 1.2MB 是**传输被打断**，不是服务端截断；**单跑复现为完整**，别据此写"raw 也有 1MB 上限"）。
- **`GET /readme` 的 raw 媒体类型**：`application/vnd.github.raw` 与 `application/vnd.github.raw+json`
  **两种写法都回 200 + 裸 Markdown**（实测 `cli/cli`）。
  ⚠️ **别按响应 `content-type` 判内容类型** —— 它把请求里那个串原样回带（`raw` 就回 `application/vnd.github.raw; charset=utf-8`）。
- **`GET /compare/{base}...{head}` 字段（实测）**：`status` / `ahead_by` / `behind_by` / `total_commits`，
  外加 `base_commit` / `merge_base_commit` / `commits` / `files` / 三个 url。
  两端相同时 `status == "identical"`（实测 `trunk...trunk` ⇒ 三者皆 0）。
  ⚠️ `commits` / `files` **会被服务端截断** ⇒ 判"有没有未合并提交"**只读 `ahead_by`**，不要数数组长度（决策 #53）。
- **`GET /commits` 列表 vs 详情**：`?path=` 过滤可用（决策 #49 靠它）；
  ⚠️ 列表项**不含** `files` / `stats`，增删统计只在 `commits/{sha}` 详情里（`stats{additions,deletions,total}` + `files[].patch`）。
  列表项含 `sha` / `commit.message` / `commit.author` / `author` / `committer` / `parents`。
- **`GET /branches` 与 `/branches/{branch}`**：列表项 = `name` / `commit` / **`protected`**（无 `_links`）；
  单分支端点另给 `_links` / `protection` / `protection_url`（实测 `cli/cli/branches/trunk` ⇒ `protected=True`，`commit.sha` 可用）。
  ⇒ 删除入口判据 = `name != defaultBranch && !protected`（决策 #53）。

## 8. 原型 `redesign/prototype/` 的结构与验证纪律（判据见 `MEMORY.md §5`）

- ⚠️ **16 个 JS 共享同一全局作用域** ⇒ **加载顺序即依赖顺序**（`const` 无提升）；**禁止 `type="module"`**（`file://` 下被 CORS 拦）。
  顶层 `const`/`let` **不挂 `window`** ⇒ 探针只能用 DOM 事实。
- 渲染模型 = **状态驱动 + 模板字符串全量重绘**（`SCR{}` 注册 19 屏，`paintTab()` 重写 `#stackArea`）。
  **不要"简化"成静态 HTML 多页** —— ① 参数化 ② 状态唯一副本（`favMap`→`favTotal()` 派生）
  ③ 导航栈三层同屏是**转场行为**（不是排版）④ 与 SwiftUI `View = f(State)` 同构。
- 改**行为类文案**后必须**真跑一遍**该路径 —— `grep` 只查得出词，查不出"承诺落空"
  （曾发现种子计数是静态字段 ⇒ 删夹后默认夹不动）。
- **验证纪律**（skill `gitduo-prototype-loop`）：文本/结构/状态 → **只走 jsdom 加断言**
  （`harness.js` 在仓库外 `/Users/jiangjiang/.workbuddy/binaries/node/workspace/harness.js`，262 项断言、
  **0 处 `getBoundingClientRect`** —— jsdom 无布局引擎）；**版式三类才开 Chrome**（间距均分 / 裁切溢出 / 层叠遮挡），攒一批跑一次。

## 9. 决策口径与外部硬事实

> **规则正本 = `TECH_SPEC.md` 决策表（当前 70 项全【已定】）** —— 本节**不再复制它**。
> ⚠️ 2026-10-08 复核：本节原先的复制版写着"决策表（55 项）"，**已过期 15 项** —— 这正是"两份真相必然漂移"的实例。
> 故本节只留**判据一句话**与**最容易搞错的点**，推导一律回查决策表。外部事实**会变，用前复查**。

### 9.1 决策速查（只留"容易搞错"的那一句）

| # | 一句话判据 |
|---|---|
| #30 | 换令牌 `client_secret` 为 Required ⇒ **没有"用 PKCE 换掉 secret"这条路**；PKCE + 一次性 `state` 是主防线，自定义 scheme **不是安全边界** |
| #33 | 令牌出口只有一个（`AccessTokenProviding`），出口**归一化一次**：凭据失效 ⇒ `.unauthorized`、断网 ⇒ `.transport`、**其余原样抛不编造结论** ⇒「断网 ≠ 登出」在数据层也成立。**例外**：登录第 8 步 `/user` 走 `explicitToken`，**带它时 401 不刷新** |
| #35 | 仓库列表用**默认 affiliation**，**不能**写死 `affiliation=owner`（会漏协作 / 组织仓库）；公开私有**本地过滤** |
| #38 / #39 | 探索 Issues **只列开放**，PR **开放 + 已合并都列**（**有意不对称**） |
| #41 | Star ±1 的基准**必须先查一次** `GET /user/starred/{o}/{r}` |
| #42 | 语言占比条 = **前 2 个语言 + 「其他」= 最多 3 段** |
| #43 | **归属判据**：参数用**领域模型** ⇒ 卡片留各自 Feature；只收基础类型且与业务无关 ⇒ 进 `GitDuoDesign`。`RepoSummary.canWrite: Bool?`（`nil` = "数据源给不给"）⇒ 分流**一律**走 `canOpenWritableDetail`（`nil` 按**不可写**） |
| #44 / #45 | 搜索超一页 ⇒ **「加载更多」按钮**（理由**是配额**：滚太快 403 会拖垮四范围共用的整页）；热门关键词 ⇒ **内置静态词表** |
| #46 / #51 | 「不可点」= `allowsHitTesting(false)` + 读屏 hint，**不是** `.disabled`。**例外**：`Raw` 当真做（零请求）、`Revert` 跳网页端。⚠️ **8.4 已把「＋ 添加」「编辑」「更多」接通** ⇒ 之后仍不可点的只剩 `历史` / `Fork 后可编辑` |
| #47 | ⚠️ **被外部事实推翻过的旧设计**：`ghu_` 下 Issue 与 PR **必须分成两条查询**（不然 422）⇒ **每翻一页 2 格配额** |
| #49 | 文件树副标题 ⇒ **逐文件补 `GET /commits?path={p}&per_page=1`**（目录清单**不带**它） |
| #50 / #52 | §11.2 diff 解析在切片 6；合并分支**单独新弹层** |
| #53 | ⚠️ 外部事实修正：不给删除入口的分支 = **默认 且 非受保护**；未合并判定只读 `compare` 的 **`ahead_by > 0`**（**不数 `commits`**，会被截断） |
| #54 | 文件查看三档降级（`FilePreviewKind`）：≤1MB base64 / **>1MB 走 `vnd.github.raw`**（contents 回 200 + `encoding:"none"` + 空 content）/ 图片按扩展名 + `size` 决定下不下 / 其余「不支持预览」。⚠️ **不按"UTF-8 解码失败"判二进制** |
| #55 | 分支记忆**持久化** + **两段式解析**（记忆值立即用 ⇒ 列表回来校正 ⇒ 因 ref 失踪 404 则**静默重发一次**）。⚠️ `didFallBack` 必须与"本来就没记忆"**分开**；**分支列表为空 = "无法验证"不是"什么都不存在"** |
| #64–#70 | 切片 8 写通道：**`PUT` 不传 `branch` ⇒ 静默进默认分支**（签名上无默认值）· **sha 在提交时刻现取**（409 永不触发 ⇒ 会静默丢远端改动）· 写**不重试** · 重命名 = `PUT` 新 → **串行** `DELETE` 旧 · **相册拿不到文件名** ⇒ `UploadFileName.photo(…)` 生成（见 §9.3） |
| — | **登出四步**：撤销授权（失败降级 `revokedLocallyOnly`）→ 清 Keychain → 清账号数据 → 重置导航栈 |
| — | **本期不做**：通知（Tab 5→4）· 深色模式 · 多账号 · Revert · 置顶增删 · 大文件上传 · Git Data API。**未决**（用户"暂都不补"）：界面语言、App 图标与品牌视觉、发布准备 |

### 9.2 踩坑与方法论（原 `MEMORY.md §2` 的过程叙述，2026-10-07 下沉）

> `MEMORY.md §2` 只留**触发条件 → 判据**；这里是"为什么"与"当时怎么发现的"。

**工程纪律**
- 加包必须登记 `Makefile` 的 `PACKAGES` —— 漏了**不报错**，只是该包单测永远不被跑。
- ⚠️ **`make test` 一个字都不编译 App target**（只跑五个包 `GitHubAPI` / `GitDuoCore` / `GitDuoAuth` / `GitDuoDesign` / `GitDuoKit`）；改 `GitDuo/**` 后必须 `make build` / `make verify`，否则一屏"没有成员 / 构造器不可见"会一路攒到用户手里才暴露（2026-10-07 实录）。
- ⚠️ **`make verify` 是增量构建，看不见警告** —— 只有真正被重编的文件才吐诊断 ⇒ 查警告要 `touch` 新文件强制重编再 grep `warning:`。
- ⚠️ **别用 `rm -rf` 做 clean**（被安全机制拦 ⇒ `&&` 短路 ⇒「看着跑了其实没跑」；一天内踩两次）。让 xcodebuild 增量构建。
- `project.yml` 声明依赖 ≠ 源码可见，仍须 `import GitDuoDesign`。
- `sandbox_apply: Operation not permitted` **一律是环境问题、不是代码问题**（`Makefile` 已做成自检式自愈：健康机器上零变化，受限环境下自动补开关）。**宏报 "produced malformed response" 也要先怀疑它。** 死路清单与真开关见 `§6`。
- ⚠️ `@Suite` 内的成员**不能靠位置互相发现**：跨测试文件用不了别的套件的辅助函数（编译期看起来像"类型没定义"）⇒ 新断言自带辅助或与所属套件同文件。

**编码**
- 不用 `UIScreen.main`（布局看 size class / 容器尺寸）；`.glassEffect` **只许**在 `GitDuoDesign` 封装内、**只用于导航层**（导航栏 / Tab / 工具栏 / Sheet / 自定义控件），绝不用于内容层（列表行 / 卡片 / 正文 / 图片）；颜色/字号/间距/圆角一律走语义 token，禁写魔法值。
- 文案 / 权限清单 / 产品承诺要提为**可测领域数据**，不许散在 `Text("…")` —— 曾出过"文案承诺撤销授权、实现却做不到"。
- 循环/长任务里的失败**不要静默吞掉**（尤其 404 与"无权限"被 GitHub 混同）。
- `Text + Text` 自 iOS 26 起已废弃 ⇒ 两色拼接用 `Text("\(a)\(b)")` 插值。
- ⚠️ **编译器会"指错行"**：报错说某成员"类型是个闭包"时，先找同段里别的调用有没有**过时签名**。
- ⚠️ **令牌名与系统名撞车**（6.3 发现）：`Theme.Font.caption` 这个**令牌名**指的是 `.caption2`（11pt），而**系统** `.caption` 是 12pt —— 两套词汇撞车。新增 `Theme.Font.breadcrumb`（系统 12pt）时踩到，命名/读代码都要先分清是哪一套。

**解析器 / 扫描器（切片 6.1 换来，几条都极贵）**
- ⚠️ **"找到下一个 X 就闭合"必须先问 X 是否可重复**：行内代码曾只找"下一个反引号" ⇒ **三个反引号被错配成一对、吃掉两个字符**（**内容被改，页面上完全看不出来**）。可重复的（反引号 / `~` / 引号）必须按 **run length 等长匹配**。
- ⚠️ **词法扫描器：起始字符集合必须 ⊆ 后续字符集合**。起始集含 `@` 而后续集不含 ⇒ `@available(…)` 走进去 `index` 原地不动 ⇒ **死循环**，症状是 **`swift test` 整个进程被 SIGKILL（exit 137）、一行输出都没有**。
  **判据：`swift test` 无输出地被杀 ⇒ 先查死循环，不要先怀疑沙箱**（沙箱报的是 `sandbox_apply`，不是"没输出"）。定位法：逐 `--filter` 缩小套件。兜底 `defer { if index == iterationStart { index += 1 } }`。
- ⚠️ **Swift 把 `\r` / `\n` / `\r\n` 当作三个互不相同的 `Character`** ⇒ `split(separator: "\n")` **永远匹配不上 CRLF**（`"a\r\nb"` 按 `"\n"` 拆出来**仍是一段**）。凡"按行拆"必先 `replacingOccurrences(of: "\r\n", with: "\n")`（`FileContent.lines(of:)` / `UnifiedDiffParser` 都这么做，6.2 的 `CommitMessage` 曾漏）。
  **归一必须集中在一处**：另有一处漏了它就是一条**看不见的缺陷**，集中后至少 `grep "\r\n"` 查得出来。另：**归一只认 `\r\n`，单独的 `\r` 是内容**（跟随 git 的 `%s`）。
- **解析器一律做成纯函数**（吃 `String`、吐结构体、不碰 UI 类型），否则落进 View 就等于没测（App target 没有测试 target）。

**思路类**
- 写「待办/前置条件/切片」前**必须回查当前 PRD 与 TECH_SPEC**，不要从历史笔记带概念。同一句文案常散落 4–6 处，改口径要 `grep` 打全（**含原型文案**）。
- **测试自己会写错 → 看到失败先怀疑测试**（6.1 六处失败里三处是断言写错）。字典字面量迭代顺序不确定 ⇒ 断言"重复键哪个赢"会间歇失败；`URLCache.shared` 在测试进程容量为 0 ⇒ `storeCachedResponse` 静默丢弃 ⇒ **永远绿的假测试比没有测试更危险**。⚠️ **没核实过的事实不该拿来做守卫**。
- ⚠️ **"不变量断言"比"逐处期望值断言"更容易抓出真缺陷**：`firstLineRuleIsShared` 本意只钉"三处显示必须一致"，它**不关心** CRLF、也不检查任何具体文案，却把 CRLF 真缺陷钉出来了 —— 因为不需要预先想到那个输入。⇒ 凡"多处共用一份实现"，就补一条一致性断言。
- **凡是要改「已验收行为」的口径，一律先问用户。** 切片 1 四条"看着能跑、其实会伤人"的行为各有权重断言守着：**单飞刷新** / **断网 ≠ 登出** / **登出撤销失败仍登出** / **回调可能被投递两次**（`apply` 的守卫不可删）。
- **「一次查询拿两类」这类结论必须核对令牌类型**：同一端点对 PAT / 无鉴权 / **App 用户令牌**行为可能不同（`/search/issues` 就是，见 #47）。查外部事实要**引原文 + 多版本交叉**。
- **"取数时就过滤"会静默丢数据**：分段列表若在请求里带过滤条件，那一页的其他条目被当场丢弃，切回"全部"时**永远不存在**。正解：**取数只取数、过滤在展示层**；分页状态机判空要接收 `matching:` 谓词（已写死进 `TECH_SPEC §9.3`）。
- ⚠️ **"默认值恰好也正确"的声明类断言必须让默认值变错**：配额桶守卫要喂一份**"每个桶间隔都非 0"**的探针策略，才能**正面**断言"落了主桶 **且** 没误用搜索桶"；断言"它没被限速"对 `.core` 与"压根没声明"给出**同一个结果** ⇒ 永远绿，比没有测试更危险（6.2 `RepoEndpointQuotaTests` 的做法）。
- ⚠️ **提交前看 `git diff -w --stat`**：忽略空白后仍显示几百行 ⇒ 有**无关的整文件重排**（表格 pipe 对齐 / 行尾双空格）混进来了，先还原再重做改动（6.2 实录：`REVIEW-CHECKLIST.md` 被格式化污染**且内容退回旧值** —— 修法是 `cp` 备份 → `git checkout --` → 重新精确追加，`git diff --stat` 从 408 行变 17 行）。
- **"`nil` 是脏数据"与"`nil` 是接口不给"不是一回事**：填 `0`/`false` 会显示成 `Fork · 0` 与"公开仓库"，而真实含义是"没问过"—— 决策 #43 整条论证建在这个区分上。
- **定位方法（有效）**：把可疑片段复制进**临时探针文件**逐个摘成分看错误何时消失。⚠️ **探针"编过了"可能是假的** —— 同一批 `-primary-file` 里别的文件报错会**压掉**其余诊断 ⇒ 以"**错误消失/出现**"为准。
- **不许替用户拍板文档未定义的点**：未定义的自拟文案 / 口径要逐条登记为「规格未给，待评审」（6.1 的 `BranchCopy` 四组、6.3 的 `number`/`type` 不着色与 `DiffLine.displayNumber` 就是这么来的）。

### 9.3 外部硬事实

- 权限 **6 项**：Contents(R/W) · Issues(R/W) · Pull requests(R/W) · Metadata(R) · **Starring(R/W)** · **Followers(R/W)**（后两个是**账号级**，缺了 Star/关注全 403；Contents 只读则 `PUT .../contents/{path}` 403）。
- ⚠️ **不要勾** "Request user authorization (OAuth) during installation" —— 勾了安装完直接跳 `?client_id=…`，**没有 `state`、没有 `code_challenge`**。
- ⚠️⚠️ **账号级权限（`Starring` / `Followers`）改了之后，手里那张旧令牌不会自动获得它**（2026-10-09 查得，官方《Approving updated permissions for a GitHub App》原文：「**If the app is authorized but not installed or if the GitHub App only requested additional account permissions, GitHub will not notify you. Instead, the GitHub App will prompt you to reauthorize the app in order to enable the new account permissions.**」；配套另一句：*you will need to send existing users through the user authorization flow to authorize the new permission and get a new user-to-server token for these requests*）。⇒ 三件事**同时**成立，合起来长得像"这一颗按钮坏了"：**GitHub 不通知你** · **旧令牌继续有效**（登录 / 浏览 / 看仓库全正常）· **只有 Star / 关注那一个动作 403**。**唯一的修法是重新走一遍授权拿新令牌**（App 内退出登录 → 重新登录）。⚠️ **判据**：**"授权页列出 6 条"与"手里这张令牌带 `Starring`"是两件事** —— 前者看 App **当前的声明**，后者是**授权那一刻的快照**；两者不一致时，**屏幕上只看得见后者**。排查入口：`REVIEW-CHECKLIST` 清单 C 的 P2 段（1 分钟三步，第 3 步**必须挑一个"本来就已 Star 过"的仓库** —— 决策 #41 先查真实状态再切，否则看到的是"Star 成功"、验不出这条通道）。
- 令牌：`ghu_` **8 小时**、`ghr_` refresh **6 个月**；`scope` 恒为空串 ⇒ 权限 = App 声明 ∩ 用户自身。API 版本头 **`X-GitHub-Api-Version: 2026-03-10`**。**令牌可见范围 = 用户权限 ∩ App 权限 ∩ 安装时勾的仓库** ⇒ 必须引导选「All repositories」。
- GraphQL 错误走 **200 OK + body.errors**、还可能"部分成功" ⇒ **绝不能只看状态码**；配额按**潜在最大节点数**预扣（集合元素下再开连接：1 点 → 100 点；单查询 ≤5 点）。
- Issues 列表**会混入 PR**（按 `pull_request` 过滤）；无独立 merged 状态（`state=closed` + `merged_at != null` 本地判）。404 与无权限被混同 ⇒ 文案统一"不存在或无权访问"。
- **无任何 API**：通知（仅 classic PAT）· 置顶写 · Revert · 最近访问 · 星增幅 · Trending。**仅 GraphQL**：Discussions / Projects V2 / 贡献热力图。**仅 REST**：Search / Actions / Gists / secrets / PR diff 原文 / 语言构成。
- `/search/users` 的 `name`/`bio`/`public_repos`/`followers` **官方 OpenAPI 与 200 示例都不给** ⇒ 全按可选，拿不到 ⇒ 副标题**整段不渲染**（`nil` = 不知道，`0` = 就是零）；要数只能**逐条补 `GET /users/{login}`** —— **待用户裁定**。
- `/search/code` 预览行**必须带** `Accept: application/vnd.github.text-match+json`，**首屏与每页续页都要带**（漏了 ⇒ 前 30 条有预览、后面全没有，最像服务端的问题）。
- **切片 6 端点实测**（contents 大文件行为 / readme raw 媒体类型 / compare 字段 / commits 列表与详情分工 / branches 的 `protected`）：**逐条见 `§7`**，别按直觉写。
- ⚠️ **`contributionsCollection(from:to:)` 的"一年"是**日历**意义的**（2026-10-09 查得，官方 schema 原文：`from` 省略 = "**a year ago**"、`to` 省略 = "the current time or **one year from the provided `from` argument**"）。⇒ **"一年"不是 365 天**：2024 整年窗口（1/1 0 点 → 12/31 23:59:59）是 **366 天减 1 秒**。把它实现成"≤ 31,536,000 秒"的判断会把 2024 判成越界，而症状是"那一年永远切不过去"。⚠️ **残留不确定**：闰年窗口没在真机验过（2024 正是本期三个选项之一）—— 排查线索写在走查单 #123。
- ⚠️ **贡献日历的"日桶"与 `from` / `to` 的时区偏移无关**（外部证据：第三方项目实测，`octomation/maintainer` issue #457 称同一个窗口按 `Z` / `+03:00` / `-07:00` 写返回的 `date` 完全一样）⇒ 本项目的 `dateTime` 固定按 GMT 序列化**不会**让某些天的贡献错位一天。⚠️ 这是**别人报的实测**、不是官方承诺 ⇒ 项目里那条理由仍然是"可读性"（同一瞬间只 24 种写法里的一种），别升级成"官方保证时区无关"。

## 10. 「规格被推翻」的四次记录（2026-10-09 由 `MEMORY.md` 下沉）

> `MEMORY.md` 只留判据；这里是过程。**每一次的处置同一句话：先改文档，再动代码。**

1. **`search/issues` 的「一次拿两类」（决策 #47）** —— 原 `TECH_SPEC §9.2` 写「一次查询、按类型字段区分」。官方文档明写 **App 用户令牌（`ghu_`）下不带 `is:issue` / `is:pull-request` 直接 422，两类必须分两次查询**；「一次拿两类」只对 PAT / 无鉴权成立。⇒ 改为**发两条**（Issue 在前、PR 在后，两个独立游标），每翻一页 **2 格配额**。同一次核实还确认原 §9.2 的「代码搜索需 ≥1 非限定词」**写对了**（`language:go` 不合法、`amazing language:go` 合法）。
2. **iOS 27.0 的 `PhotosPickerItem` 没有文件名（切片 8.4）** —— 规格默认可取到文件名，实测取不到 ⇒ 自拟 `UploadFileName.photo` 生成，并回改规格。
3. **`#70③`「不重编码」第一次被收窄（8.7 / 决策 #71）** —— >1MB 改为**自适应压缩**。
4. **`#70③` 第二次被收窄（8.8 / 决策 #72）** —— **网页端显示不出来的格式一律转码，≤1MB 也转**。

⚠️ **教训**：②③④ 都是「用户自己推翻自己先前定的规格」。⇒ 下次遇到"规格说取某个字段"，**先去 SDK 里确认那个字段存在**；**"尊重用户的东西"这类规格（取原始字节 / 不重编码），每加一层治理都要回头把上一层的绝对性收窄** —— 否则两句话会同时成立而其中一句是假的。

## 11. 五条「错了都不报错」（均已做成断言）

| # | 陷阱 | 判据 |
| - | ---- | ---- |
| 1 | 写**永不自动重试** | `isSafelyRetryable` **只认 GET** |
| 2 | `FileWriteResultDTO` 的 `content.sha` 与 `commit.sha` | **不能混**（一个是文件对象、一个是提交对象） |
| 3 | `PUT contents` 的 `branch` | **必传** —— 官方默认值 = 仓库默认分支 ⇒ 不传会「在 feature/x 上编辑却提交到 main」 |
| 4 | `CGImagePropertyHasAlpha` | 走 `NSNumber` —— `as? Bool` 对 `NSNumber(0/1)` 会**静默**得 `nil` |
| 5 | 有损压缩阶梯 | **单调不增** |

## 12. 高频坑速查（完整清单）

`SwiftUI.Label` 与 `GitDuoKit.Label` **同名**必写全 · 带初始值的 `let` **不进**自动 memberwise init · `SheetRow` 传右侧内容**必须写出 `action:` 标签** · 测试字面量里别嵌 ASCII 双引号（用「」）· `try #require` **别写在 `#expect` 里面** · **`await` 也别写在 `#expect` 里**（autoclosure，先取出再断言）· `??` **优先级高于**比较运算符 · `CGImage(...)` 的 `bitsPerPixel` **必传** · **`UTType.avif` / `.jpeg2000` 不存在**（要运行时 `UTType("public.avif")` 查；`UTType.svg.identifier` 反直觉地是 `public.svg-image`）· **别用 `rm -rf` 做 clean** · `sandbox_apply: Operation not permitted` / 宏报 "malformed response" **一律先怀疑环境**。

**2026-10-09（切片 9）新加四条 —— 前三处都是"只在强制全量重编时才现形"：**

- ⚠️ **`defer` 写在 `if` / `else` 分支末尾 ⇒ 离开分支瞬间就执行**，闸门等于没上。
  编译器只给一句 `'defer' statement at end of scope always executes immediately`（**在增量构建里被吞过**）。
  ⇒ `defer` 必须包住**整个函数体**；两个标志（首屏 / 分页）一起在末尾收尾。
- ⚠️ **`catch` 自带一个叫 `error` 的隐式绑定**（一个 `let`）—— `error = …` 报
  `cannot assign to value: 'error' is immutable`；要写 **`self.error`**。
- ⚠️ **`defaultFolderName` 不能在 `any FolderStore` 上用** ——
  `static member 'defaultFolderName' cannot be used on protocol metatype '(any FolderStore).Type'`。
  本项目**所有消费点持有的都是 `any FolderStore`** ⇒ 一律写 **`FolderDefaults.name`**。
- ⚠️ **`View`（隐式 `@MainActor`）里的 `static let` 被 `nonisolated` 纯函数读到 ⇒ 报
  `main actor-isolated static property … can not be referenced from a nonisolated context`**
  （9.3 的 `ContributionHeatmap` 踩的）⇒ 补 **`nonisolated`**。
  同因：`make test-<包>` 绿、`make verify` 绿，**只有全量重编看得见**。
- ⚠️ **泛型视图的 `static` 成员在外部引用会报 `generic parameter '…' could not be inferred`**
  （切片 10 踩的）：`RepoTreeSection<Trailing: View>` 是个泛型视图，写 `RepoTreeSection.skeleton`
  编译不过 ⇒ **要共享的骨架必须落成一个独立的非泛型类型**（`RepoTreeSkeleton`）。
  **判据**：泛型视图的 `static` 成员 = 类型名 + 未定的泛型参数，**外部拿不到**。

**2026-10-09（走查修复批）新加一条 —— 这一条的特殊之处是「代码全对、只是屏幕上找不到」：**

- ⚠️⚠️ **挂在根容器上的 `.overlay` 到不了 `.sheet` 里面**：`Toast` 挂在 `MainTabView` 的 `.overlay` 上，
  而 `.sheet` 是一层**独立呈现** ⇒ **弹层开着时提示条被整块盖住**。走查第 4 条报的"点了创建没反应"
  就是这么来的 —— 文案、判定、单测**一处都没错**，因此**任何断言都抓不到它，只有人走一遍屏幕能发现**。
  **判据**：**弹层留着 ⇒ 那句话画在弹层里**（`SheetFailureHint`，动作按钮上方）**；弹层关掉 ⇒ 照旧走提示条**
  （决策 #77 / 偏差第 45 条）。
  ⚠️ `PullDetailView` 合并那处的「**先关弹层再发请求**」是**逐处绕开的临时处置**、不是通则 ——
  它只在"关掉弹层也不损失什么"时可用（收藏夹那两处要求"留在弹层里让用户改名再试"，绕不了）。
  新写的弹层**别默认靠它**。
  ⚠️ 推广一句：**凡是"把原型的做法照搬到另一层容器 / 另一个生命周期"的地方，都要重新问一次
  "它在新的那一层还成立吗"**（原型里弹层与 toast 同层 DOM，`toast{z-index:90}` 盖在弹层上 —— 那是看得见的）。

**2026-10-09（切片 11 · Star 可写范围）新加两条 —— 第一条比"测试失败"更阴险：**

- ⚠️⚠️ **`swift-testing` 默认没有超时 ⇒ 一个"永远等不到"的测试会让整套 `make test` <u>永久挂住</u>**，
  而外部看到的只是"**命令跑不完、一个字都不打印**" —— 最容易被误读成"编译很慢"（本次白等了 **11 分 45 秒**才发现）。
  具体是这样写错的：`StarWriteScopeTests.cacheSharesInFlightRequest` 用闸门替身
  `GatedScopeSource.waitForCallers(2)` 等"两个调用者都进来"，而那条用例要证的就是
  **两个调用者只打 1 次源调用** ⇒ `callCount` 永远到不了 2。
  **判据**：**闸门的 n 不能超过"这段代码最多会打到源几次"**；写下 `waitForCallers(n)` 之前先回答
  "它最多被调用几次"，答案就是 n（等的是"那一次请求真的飞起来了"，不是"几个调用者到了"）。
  这一条与 §11 那五条不同类：那五条是"错了不报错"，**这一条是"错了不结束"** —— 后者更贵，
  因为它把"验证失败"伪装成了"机器慢"。
- ⚠️ **本环境的 `grep` 会偶发返回空**（`grep -n 模式 文件` 明明有匹配却返回空 + 退出码 1，
  `--include=*.swift` 也时报 `no matches found`）⇒ **内容检索一律用内置 Grep 工具**，别据此下"文件里没有"的结论。

## 13. 切片 8 的追加与并入（口史）

- **8.5 整片并入 8.4** —— 「表现层 vs 装配与路由」那条边界**不可执行**。
- **8.7 / 8.8 是 2026-10-09 连着来的两笔追加**（用户上手看效果后提的，都是"用户自己推翻自己先前定的规格"）。
- 8.4 起「＋ 添加」「编辑」「更多」三颗死按钮全部接通 ⇒ **决策 #51 只剩 `历史` / `Fork 后可编辑`** 两颗。

## 14. 切片 10「收尾」的三条判据（2026-10-09）

施工图对最后一片只有三个词（**骨架屏统一 / 无障碍 / 性能预算核对**），**没有任何细则**
⇒ 10.0 的全部工作是**把它们展开成可执行判据**，落点：`TECH_SPEC §8.5 / §10.5 / §13.1 / §10.7`。
这里只留"最容易做错"的那几句。

### 14.1 骨架屏「统一」的四条判据（`§8.5`）

① **单一原子**（全部骨架块由 `SkeletonBar` 产生，不许自画圆角矩形）·
② **形状留 Feature**（卡 / 行 / 网格形状的骨架**不进设计包**，必须挨着真实组件）·
③ **尺寸对齐**（容器参数 + 行内边距与真实列表逐字一致）· ④ **三档不互换**（首屏骨架 / 续页 `ProgressView` / 按钮内联）。

- ⚠️ **③ 的坑**：骨架写了 `CardBox(vertical: Theme.Spacing.m)`（12），而真实列表是 `Theme.Spacing.xs`（4）——
  **默认状态下完全看不出来**，只有"数据到达那一瞬"会看到整块上移。切片 10 查出并修了 4 处。
- ⚠️ **骨架行必须补上真实行自己的行内边距**（`RepoFileRow` 的 `padding:11px 4px` / `BranchRow` 的 `13px 14px`），
  否则骨架 6 行挤成一条、真实 6 行摊开。
- ⚠️ **"逐字相同的两份骨架"不一定该合并**：`LabelPickerSheet` 与 `BranchSheet` 那两份代码一样，
  但**各对着不同的真实行**（标签行 vs 分支行）⇒ **有意保持独立**（收成一份，改一处的人会以为改了两处）。
- ⚠️ **共享骨架不能挂在泛型视图上**：`RepoTreeSection<Trailing: View>` ⇒ `RepoTreeSection.skeleton`
  编译不过（见 `§12` 那条语言事实）⇒ 落成独立的非泛型件 `RepoTreeSkeleton`。

### 14.2 无障碍的五条（`§10.5`）

① 文字动态字体 · ② 可点控件能念出 · ③ 装饰件不念 · ④ 降低动态效果（判定做成纯函数可测）· ⑤ 触控目标。

- ⚠️ **① 必须拆成两句说**：**文字** 100% 走 `Theme.Font` 相对令牌 ✅；
  **图标**有 **50 处** `.font(.system(size:))`（逐处看过，全是 SF Symbol 图标或头像首字母）⇒
  **不随「更大字体」缩放**，**登记为有意取舍**（偏差 **41**）。
  合成一句"动态字体没问题"必有一处说假话。
- ⚠️ **⑤ 是"核对并登记"，不是"全改成 44pt"**：SwiftUI 里**要扩大命中区就得先扩大 frame** ⇒ **行高会变** ⇒
  动的是原型定下的视觉。**"只补命中区、不动视觉"做不到**（偏差 **42**）。
  零代价的那一类（可点区已够大、只是没声明）才补 `.contentShape(Rectangle())`。

### 14.3 性能预算（`§13.1`）

| 指标 | 证据类型 |
|---|---|
| 冷启动 ≤1.5s | **只能真机**（秒表 / Instruments）⇒ 用户目视项 |
| Tab 切换无网络等待 | 代码级（取数只在 `.task`；`AppEnvironment.init` 不联网） |
| 列表 60fps | **一半**代码级（列表 `Lazy*` / **有无自定义玻璃** / `onAppear` 有无同步重活）+ 一半要真机 |

- ⚠️ **"玻璃单元数量受控"在本项目是结构性达标**：全 App **没有任何自定义玻璃控件**，
  `.glassEffect` 全项目**只在注释里出现**，导航层玻璃全由系统提供 ⇒ **不需要逐页数**
  （这也是 `§10.7` 那三个封装组件从未存在的原因）。
- ⚠️ **不许把这三条混成一句"性能没问题"** —— 它们的证据强度差三档，`§13.1` 里那张表专门为此而加。

### 14.4 切片 9 收尾时留下的两条（还没走）

- ⚠️ **完成定义第 3 条「与原型逐屏对照」整个切片 9 一次都没做过**（5 页 + 6 弹层全要登录才可达）。
  用户 2026-10-09 拍板：**攒到最后一起走**（走查单 22–26 + 切片 10 改过的三处首屏骨架）。
- 两个待拍板点**用户明确"维持现状"**：`UserAvatar` 34 / 52 两档首字母字号 ·
  `NSImage(systemSymbolName:)` 图标名校验那类可选改进。

