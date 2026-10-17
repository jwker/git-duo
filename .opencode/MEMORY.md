# GitDuo 2.0 —— AI 工作记忆

> 建档 **2026-10-17**。来源：`.workbuddy/memory/`（`MEMORY.md` + 7 份日记，约 240 KB）的提炼，
> **原目录已删**。仓库入口仍是根目录 `AGENTS.md`。
>
> **只读 §1 + §2 就能接手**；§3 之后是查得到的参考件，需要时再翻。
> ⚠️ **前期文档层（`archive/` 规格 + 决策表、`redesign/` 原型、`NATIVE-MIGRATION.md` 计划）
> 已于 2026-10-17 从工作区删除**，只在 git 历史里 ⇒ 代码注释里的 `TECH_SPEC §x.y` /
> `决策 #NN` / `偏差第 N 条` / `NATIVE-MIGRATION P#` 都是**历史出处**，别去找文件。

---

## §1 当前状态（2026-10-17）

主体已完成，`make verify` 全绿 —— **1776 项 / 153 套件**
（口径 = 五包各一行 `Test run with N tests in M suites` 相加，**不是** `grep -c "passed after"`，
那是输出行数）。

**进行中的改造 = 全面改用 SwiftUI 原生控件**（原计划文档 `NATIVE-MIGRATION.md` 已于 2026-10-17 删除，
只能在 git 历史里取：`git show <删除前那次提交>:NATIVE-MIGRATION.md`）。
口径：原型降级成「功能清单」，**视觉正本 = Apple HIG / SwiftUI 官方控件**。
- ✅ **P0** 口径落地 · **P1** 白拿系统行为（骨架 → `.redacted`，102 处自绘骨架全清）· **P2** 按钮与控件样式
- ✅ **P3** 列表主干（`List` 迁移边界由走查 **89/90** 定型：只迁朴素行列表，富详情页留 `ScrollView`）
- ✅ **P4** 弹层（`SheetPrimitives` 五件退休；`Repo/Views/Sheets/` 11 个 + `ExploreFilterSheet` 全走 `Form`）
- ⬜ **P5 令牌收尾 —— 未做**：`Theme.Palette` 48 色 → Asset Catalog / 语义色；`Spacing`/`Radius`/`Font` 瘦身；
  补 `@ScaledMetric` + 动态类型。**判据：全仓 `@ScaledMetric` 现在 0 处**。
- ◐ **P6 部分**：保留自绘件（热力图 / diff / Markdown / 高亮 / Toast / 面包屑 / 气泡）内部改用官方积木。
- 计划里的分组：**A 44 项**有官方对应 · **B 32 项**官方有积木但拼不出原形状、重写 · **C 7 项永远自绘**
  （**别把这 7 件当成"还没改完"**）。

**主色统一为橙（2026-10-17 新口径）**：原「蓝 + 绿」两个色相 → 一个橙。
`accent` L`#C2410C`/D`#FFA657`（链接、强调文字）· `accentStrong` `#EA580C`（主按钮实底）；
**新增 `success`**（= 原 `accentStrong` 的绿）接走 7 处 ✓ / 指标；
**新增 `hunkSurface`/`hunkText`** 收原 hunk 蓝；`MenuRow.IconTone` 五档统一中性灰。

**T1（给 App target 补测试 target）**：阶段 0–1 ✅（`project.yml` 加 `GitDuoTests`，挂 `TEST_HOST`）。
**阶段 2（补 ViewModel 测试）/ 阶段 3（`make test-app` 并进 `make verify`）待办** ——
在此之前 **`make verify` 不编译也不跑 `GitDuoTests`**。
⚠️ App 层测试必须**整块 `@MainActor`**：项目级 `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`
会让 `#expect` 宏里用 `Route: Equatable` 直接编译失败。

---

## §2 铁律

1. 改完必跑 `make verify`。宣布"零警告"前先
   `find Packages GitDuo -name '*.swift' -print0 | xargs -0 touch` 再跑（**增量构建会吞警告**）。
   单包用 `make test-<包名>`。
2. `sandbox_apply: Operation not permitted` = **环境问题，不是代码问题**（`Makefile` 已自愈）⇒ 别去改代码。
3. **绝不 `git add -A`** —— 逐文件 `git add`。推送走 SSH（`git@github.com:jwker/git-duo.git`）。
4. 改**已注册的既有决定**前别自己拍板 —— 规格表 / 偏差表的正本已删（只在 git 历史里）；
   拿不准就**问用户**，别默默改掉一个定过的事；确属新决定要在答复里写明"这是新口径"。
5. 判据 / 规则写进**领域层纯函数**，不写进 ViewModel —— `make test` **不编译 App target**，
   写在 ViewModel 的规则跑不进单测。
6. 改观感必须**真机/模拟器目视**，用户说"我看了没问题"才算落笔。

---

## §3 GitHub 侧硬事实（实测，别再重新踩）

- `GET /contents/{path}` **一个提交字段都没有**（`git/trees` 也没有、无批量接口）
  ⇒ 文件树"每行最近提交"只能逐行问（30 项 = 30 请求）⇒ **决策 #49 已作废**并全链路删除。
- `rawFile` 走 `HTTPTransport` **自带内存 + 磁盘缓存 + ETag 条件请求**（`cachesResponse` 默认 `true`）
  ⇒ 同一张图第二次是 304、**不计配额**，不要再自建字节缓存。
- ⚠️ **同一 URL 只差 `Accept` 会撞缓存键**（`contents` 的 JSON 与 `rawFile` 的裸字节同 URL）
  ⇒ 304 后会把缓存里的 JSON 当响应体交出去（**走查 #59**）。修法 = `CacheKey` 加 `variant`
  （旧缓存要能解得出 ⇒ metadata 的 `variant` 必须**可选**）。
- `GET /user/starred/{owner}/{repo}` 是"**读**你与仓库的关系"，**不受 GitHub App 安装范围约束**
  （读他人仓库 200/204；写 403）⇒ 别人的仓库也能准确显示"你已 Star"。
- 头像原图约 **460px** 见方，而展示最大 86pt（提交行只要 28pt）；**头像 URL 支持 `?s=<size>`**。
  ⚠️ `AuthorDTO` **不声明** `avatar_url`；贡献者 / 提交作者另有 `avatar_url`。
- 匿名 `/users/{u}/contributions` **只认年份粒度**，忽略 `from`/`to` ⇒ 服务端切日口径**至今未坐实**。
- 全量语言 600+，移动端只取主流子集；`C++` / `C#` 必须靠 `URLComponents` 编码（`C%2B%2B`）。
- EMU / 头像地址是 **~20 分钟时效 JWT**（官方答复 #147297）⇒ 取不到一律兜底，别当长期资产。
- **SVG 系统层画不了**：`ImageIO`/`CGImageSource` 连 macOS 上都不认；Asset Catalog 放 SVG 是构建期烘成位图。
  ⇒ markdown 里的 `.svg`（含 shields.io 徽章）只能回落占位（**走查 #64**）。
  GitHub 官方 App 也不是 WKWebView —— 它内嵌 `BigBadaboom/androidsvg`，画不完美（外链 logo 空白）。

---

## §4 工具链 / 本机环境硬事实

- **包级 `xcodebuild test` 在本机跑不动**：`.iOS("27.0")` 要有 iOS 27 设备（本机有 runtime、无设备），
  `#Preview` 还会报 `swift-plugin-server produced malformed response`
  ⇒ `ImageRenderer` 只能在**宿主机**跑，拿到的是 **macOS 的 `Menu` / `ProgressView` 外观**
  ⇒ **尺寸结论有效、外观结论无效**。
- ⚠️ **不要比像素**：宿主机同一状态连渲两次能差 628×48（`Menu` 外观由系统定）⇒ 像素断言必假红，只能比尺寸。
- `ImageRenderer` **别串着连渲**（主线程、一张约 90ms）⇒ 每张之间 `await Task.yield()`，
  否则会把隔壁 `ToastCenter` 计时用例挤成假红。
- ⚠️ **`NSColor` 动态色在非主线程 resolve 会死锁**（`swift test` 跑 macOS 变体、测试线程非主）
  ⇒ 整包挂 20 分钟零输出。**iOS 走 `UIColor` provider 不受影响**。
- 宏探针限制：`/usr/bin/swift` 与 `swiftc` **加载不了 `@State`/`@Observable` 宏**
  ⇒ 探针改 `ObservableObject` + `@Published`。
- 验 SF Symbol 名字：AppKit `NSImage(systemSymbolName:accessibilityDescription:)` 逐名打印 OK/MISS。
  名字写错别处**不报错**，只是界面上凭空消失。
- 本机 `grep` **偶发返空** ⇒ 内容检索一律用内置 Grep 工具，别据此下"文件里没有"的结论。
  后台任务的 `/tmp` 与当前 shell **互相隔离**，不能跨 shell `tail` 它的日志。
- `ToastCenter` 时序断言在高负载全量轮**偶发假红、单包重跑即过**（走查 77/78/81/82/85 条多次）⇒ 见到先重跑。
- App Store 官方宣传图取全分辨率：把 `screenshotUrls` 的 `/320x480bb.jpg` 换成 `/1290x2796bb.png`。

---

## §5 SwiftUI / iOS 27 硬事实

- **顶栏三档实测**：`.inline` = 17pt **居中**；`.large` = 34pt 靠左**但在内容区**；
  「顶栏 + 放大 + 居左」系统**给不出** ⇒ 只能自绘放 `topBarLeading`。
- 工具栏会**压缩**自定义视图 ⇒ 必须 `.fixedSize(horizontal: true, vertical: false)`；
  还要用 1×1 透明 `principal` 顶掉系统的 inline 标题（否则屏上出现两遍标题）。
- iOS 26+ 工具栏默认给自定义视图套**玻璃胶囊** ⇒ 要做正圆得 `ToolbarItem.sharedBackgroundVisibility(.hidden)`。
- 动态色 `Color ==` 比的是**实例身份不是值**；NSColor resolve 与 SwiftUI 直构在 Float32 最低位差 **1 ulp**
  ⇒ 比较要**半格（0.5/255）容差**（`Tests/GitDuoDesignTests/ColorResolve.swift`）。
- `.swipeActions` **只在 `List` 行里生效**（`ScrollView + CardBox` 里是死手势）。
- `.alert` **没有 `onDismiss`** ⇒ 用 `.onChange(of: 呈现值)` 接"关完了"这一刻。
- `.safeAreaInset(edge: .top)` 会**吞掉大标题**；「大标题 + 分组形状 + 吸顶」**三者不可兼得**。
- `.redacted` **不拦点击** ⇒ 骨架逐处补 `.allowsHitTesting(false)`；
  但**不能加在整张 `List` 上**（会连滚动手势一起关）⇒ 逐块/逐行加。
- ⚠️ **`NavigationStack` 全仓只能一个顶层**：一个容器里两条栈会被并成一条并抛
  `AnyNavigationPath.Error.comparisonTypeMismatch`（代码页崩过，**排除法定根因**）。
  多目的地 = 一个栈挂多个 `navigationDestination`。
- **推入页里的 `.toolbar(.hidden, for: .navigationBar)` 藏的是外层那条** ⇒ 连标题与返回键一起消失。
- `NavigationLink(value:)` + `.simultaneousGesture(TapGesture)` **吞掉跳转**（整行点不动）
  ⇒ 改 `Button { router.push(...) } + .buttonStyle(.plain)`。
- `Button` 命中区默认只算子视图几何并集，**`Spacer` 的空白不接点击**；
  `.contentShape(Rectangle())` 放 `Button` **外层会被忽略** ⇒ 要加到**行组件的根视图**。
- **`List` 迁移边界（走查 89/90 定型）**：只迁「朴素行列表」（菜单 / 分支 / 链接 / 首页行 / 搜索结果）；
  **富详情页（自带白面、圆角、`FlowLayout` 这类自定义布局的块）一律 `ScrollView`** ——
  `List` 行给的是 ideal-size 测量，会把这种块压窄、甚至让 `FlowLayout` 塌缩到只剩图标
  （仓库首页头部 Star/Watch/Fork 数字消失就是这条）。
- 自定义 `View` 的 `body` 是 `ForEach`/`Section` 时放进 `List` 会**摊成多行**；
  `List` 套 `List` **不会**摊平 ⇒ 被嵌件必须吐 `Section`。
- `.insetGrouped` 里 `NavigationLink` 行的分隔线默认缩到 disclosure 左侧（`.listRowInsets` 改不了）。
- **分隔线两套相反口径**：**顶线件**（`MenuRow`/`PinRow`/`RecentRow`/`SearchRowBox`/骨架）**第一行**传 `false`；
  **底线件**（`LinkRow`/`BranchRow`/`RepoFileRow`/`RepoCommitRow`）**最后一行**传 `false`。
  混用件规则：坐 `List` 传 `false`，坐 `CardBox` 按首/末行规则传。
  `MenuRow` 坐 `CardBox(horizontal: 0)` 时**必须显式传 `contentPadding: 14`**，否则内容贴边。
- `.task(id:)` 的 id **必须带全内容身份**（本仓用 `Equatable` 结构体如 `RepoCodeLoadKey`，漏一半**编译不过**）。
  滚动归零靠内容 `.id(path)`，与取数 id 分开写。
- 设计包 `#Preview` **不能写 `.listStyle(.insetGrouped)`**（iOS-only；`swift test` 编 macOS 变体 ⇒ 整包编不过）。
- `ProgressView().controlSize(.small)` 在 iOS 最小 **20pt 见方**，`.frame` 只改布局建议 ⇒ 要 `scaleEffect`。
- 字体令牌全走系统文本样式（动态类型通），但**间距 / 行高 / 固定 frame 是写死 pt** ⇒ 大字号会挤。

---

## §6 已定口径（最容易搞错的几条）

- **2026-10-16 新口径**：「按原型」= **功能**按原型，**不是视觉一模一样**；视觉正本 = Apple HIG。
- **2026-10-17 新口径**：主色统一为橙（见 §1）。
- **2026-10-13 用户整体否决 UI 视觉改版**（"不好看，放弃 UI 改版"）——
  但 **10-15 晚用户主动重启卡片改版，推翻前者**。现行视觉 = **方案 A**
  （浅灰页 `0xF6F8FA` + 白卡 + 卡间 10 + 卡内 hairline）；**方案 D 已作废**。
  ⚠️ 除非用户重新提，**不要再提**层次反转 / 压深底色 / 去饱和 / 圆角收敛。
- **走查 #69** 推翻旧口径「不提供主题切换器」：深色三档切换器 · Primer dark · 一次性全量。
- **走查 #85**：底部「我的」→「搜索」，首页右上角圆形头像进「我的」
  （`Route.profile` 新增，`Route.search` 已删；三页右上角放大镜移除）。
- **走查 #70** 推翻 2026-10-09 走查 #3「Star 列表照常可点」⇒ Star 入口只剩详情页头部。
  ⚠️ `MyStarsViewModel.toggleStar/toggling/toggled`、`ProfileCopy.unstarAction`、`ToggleStar` 接线
  **保留但暂无调用方**（第 70 条的"先"= 可能回加）—— **别顺手清**。
- **走查 #63（偏差）**：仓库页 = 枢纽页 + 四行入口；代码页**自带页内层级**（保住走查 #54"进一层是页内推进"）。
  代价：**无系统推进动画、无系统左滑** —— 用户裁定：要左滑 = 自写手势 ⇒ 与 PRD §1 相悖，**不做**。
- **走查 #62**：文件/代码页操作收进右上角 `ToolbarItem(.topBarTrailing)` 的「⋯」菜单；
  不可点项**撤下不进菜单**；"编辑"不可用时用 `.disabled`（与**决策 #51「不用灰」有意分岔**）。
- **走查 #58 当天被用户打回一次**：判据过窄会写出"看起来像功能没做"的降级 ——
  「`Text` 里插不进图」≠「图不画」；"图与文字同段"才是最常见的写法。
- **决策 #49 作废**（文件树每行最近提交）；**走查 #52** 根因是**原型自己把同一意思画了两遍**。
- `LinkRow` 现仅剩自己的 `#Preview` 引用（**无生产调用方**），**有意保留作设计原件**。
- `Picker.selection` 是受控绑定；值要等一个往返才变 ⇒ 表现为"选不生效、要点两次"。
  **"值要等一个往返才变"的选中态不能交给受控控件接**（走查 #61 改 `Button`）。
- 文案：README 写平实白话、**不要 AI 味**（反对功能罗列与状态汇报）；不解释 GitDuo 名字含义。
- "逐字不许动"保护的是**句子不走样**，不是"句子不能被产品撤下"—— 用户是 PRD 主人，
  裁定即改、文档侧加补记留痕（走查 #68）。
- 原型 CSS 特异性：轨道图标上色必须写全 `.menu-item svg.tint-open`（单类会被 `.menu-item svg` 压掉）。

---

## §7 方法论（这些是省往返的）

- **退回验证**：把判据临时改坏 ⇒ 断言**必须变红并点名** ⇒ 再还原。
  **只绿不变红 = 测试没咬住东西**（本项目惯例）。视图身份 / `.task` 时机这类无可写单测的，
  用**宿主机最小复现**（`swiftc` + `NSHostingView`）实跑。
- **"全绿"只证明被测到的路径是对的** —— 桩件的盲区恰是"只在真实服务端成立的失效模式"（304 是典型）
  ⇒ 改数据层行为至少要一次**不经桩件**的端到端验证。
- 报缺陷先**排除法定根因**（不猜）＋ **先给结论、再上证据链**；
  用户报的症状按用户自己的更正读（用户会中途撤回半句）。
- **写代码前先做探针实锤**（`swiftc` + `NSHostingView`，或 iOS 模拟器）。
  看不到图时：用像素行块/列投影脚本把截图变成数字（块的 x/y/宽/高）再程序化判定。
- 未定义点用 **AskUserQuestion**：给「选项 + 推荐档」，**不要自定义一个值然后当成事实**。
- 动手前先定性三选一：**实现走样 / 规格本身就错 / 原型与规格都没定义（用户点名新增）** ——
  后两类要登记走查编号，不要当 bug 偷偷改。用户原话与事实不符时要**点明**。
- 文档漂移**当独立任务登记**，不顺手改。
- 拆分交织在同一 hunk 的改动前先看 `git diff -U0 -- <file> | grep '^@@'`：
  hunk 铺到文件尾 = 整体重写 ⇒ 拆不出可编译的中间态。
- 宣布结论前看 `grep error:`，别只看 tail（曾把"App 编译失败"误判成"只挂一条测试"）。
- 交付前自问「**用户会怎么用**」，而不是「我的判据有没有被满足」。
- 本仓 Swift 里自然语言引号用 `「」`，**别用 ASCII `"`**（会截断报错）。
- 改文案 / 改名要 **grep 全仓**（含注释、原型、harness）；删符号时连注释里的引用一起数。
- 改共享令牌前**先查借用链**，并数清这族落在几种底上（面板 / 页面 / 弹层），批量替换后逐处复查。

---

## §8 未完成 / 待目视

- **T1 阶段 2 / 3**（见 §1）。`Packages/GitDuoKit` 里三处「App target 没有测试 target」的注释
  （`Package.swift`、`PagedListState.swift`、`LoadState.swift`）**已过期**。
- ⚠️ **深色档至今一次都没在真机上看过**：三级层次（页面 `0x0D1117` / 卡面 `0x161B22` / 卡内控件 `0x0D1117`）、
  约 20 屏、跟随系统即时变色、强制档锁住、Toast 浮起、玻璃 tint 50% 是否过浓。
- 历史未目视项：走查 **66/67/68/70/72/74/76** 条的形变与观感；**`Menu` 的 iOS 外观**
  （自定义 label 会不会被套 tint / 自带按钮样式）；README 去面板通栏效果；长数字折行后是否顶齐；
  年份切换器在途转圈（`HeatmapHeader` 的 Preview 里并排摆着在途与不在途）。
- 待用户选定：`DiffCard → DisclosureGroup`（会丢有意保留的 `▾`）· `LanguageBar → Swift Charts`
  （布局与无障碍会变）· `.searchSuggestions` 没接 · 全站列表行是否补回 chevron
  （P3 如实登记的跨页不一致：首批六页无 chevron、第二批有）。
- 两处清脏：`UserProfileSheet.swift:210` 圆角字面量 `9`（应用 `Theme.Radius.control`）·
  `LoginFlowView.swift:91` 漏 `.continuous`。
- 待裁定：`ExploreRepoCopy.failureTitle`（"加载失败 · 点击重试"）vs `PageFailure.title`（正本无"点击重试"）；
  三个 Explore 页各自的 failure 状态未并入 `PageFailure`。
- 编辑器新建模式提交成功后**不刷新上一页目录**（`EditorViewModel.submit` 不调 `tree.reload()`；
  `RepoDetailView` 的 `.task` 因 `hasFinished` 不重跑）—— 与走查 **#98** 相关，未改。
- 热力图 **A 案**（窗口起点改按 UTC 日历算、治本）留待坐实服务端切日口径；
  B 案已知代价：`totalContributions` 不裁 ⇒ 可能"空网格 + 非零总数"。
- md 图片两处已知代价：**下载完才知道高度 ⇒ 布局会跳**；仓库外的图拿不到原始尺寸 ⇒ 小图标被放大到整屏宽。
- `ProfileViewModel.load(year:)` 的 `guard !isLoading` 仍在 ⇒ 首屏取数期间点年份会被**静默丢弃**。
- **App 卡在 GitHub 登录**（本机无真令牌）⇒ 大量 UI 改动属"未目视"，只经用户过目后提交。
