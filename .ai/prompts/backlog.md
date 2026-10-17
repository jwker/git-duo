# 待办清单（backlog）

> 建档 2026-10-17。**只放"还没做的活"** —— 事实与口径在 `.ai/memory.md`，
> 单个改造的完整计划各自成篇（如 `T1-app-layer-test-target-plan.md`）。
> 做掉一条就**删掉**这条；别在这里记"已完成" —— 那属于提交历史。

## 待目视（只能人眼看，判据 = 用户说"我看了没问题"）

- ⚠️ **深色档至今一次都没在真机上看过**：三级层次（页面 `0x0D1117` / 卡面 `0x161B22` / 卡内控件 `0x0D1117`）、
  约 20 屏、跟随系统即时变色、强制档锁住、Toast 浮起、玻璃 tint 50% 是否过浓。
- 历史未目视项：走查 **66/67/68/70/72/74/76** 条的形变与观感；**`Menu` 的 iOS 外观**
  （自定义 label 会不会被套 tint / 自带按钮样式）；README 去面板通栏效果；长数字折行后是否顶齐；
  年份切换器在途转圈（`HeatmapHeader` 的 Preview 里并排摆着在途与不在途）。
- **App 卡在 GitHub 登录**（本机无真令牌）⇒ 大量 UI 改动属"未目视"，只经用户过目后提交。

## 待用户裁定 / 选定

- 待选定：`DiffCard → DisclosureGroup`（会丢有意保留的 `▾`）· `LanguageBar → Swift Charts`
  （布局与无障碍会变）· `.searchSuggestions` 没接 · 全站列表行是否补回 chevron
  （P3 如实登记的跨页不一致：首批六页无 chevron、第二批有）。
- 待裁定：`ExploreRepoCopy.failureTitle`（"加载失败 · 点击重试"）vs `PageFailure.title`（正本无"点击重试"）；
  三个 Explore 页各自的 failure 状态未并入 `PageFailure`。

## 待清脏（小、明确）

- `UserProfileSheet.swift:210` 圆角字面量 `9`（应用 `Theme.Radius.control`）；
  `LoginFlowView.swift:91` 漏 `.continuous`。
- `Packages/GitDuoKit` 里三处「App target 没有测试 target」的注释（`Package.swift`、`PagedListState.swift`、
  `LoadState.swift`）**已过期** —— **归 T1 计划管**（`T1-app-layer-test-target-plan.md` §4 文案契约 · §8 进度）。

## 已知未修（有编号 / 有代价的）

- 编辑器新建模式提交成功后**不刷新上一页目录**（`EditorViewModel.submit` 不调 `tree.reload()`；
  `RepoDetailView` 的 `.task` 因 `hasFinished` 不重跑）—— 与走查 **#98** 相关。
- 热力图 **A 案**（窗口起点改按 UTC 日历算、治本）留待坐实服务端切日口径；
  B 案已知代价：`totalContributions` 不裁 ⇒ 可能"空网格 + 非零总数"。
- md 图片两处已知代价：**下载完才知道高度 ⇒ 布局会跳**；仓库外的图拿不到原始尺寸 ⇒ 小图标被放大到整屏宽。
- `ProfileViewModel.load(year:)` 的 `guard !isLoading` 仍在 ⇒ 首屏取数期间点年份会被**静默丢弃**。
