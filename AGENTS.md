# AGENTS.md —— GitDuo 2.0（AI 的唯一常驻入口）

> **读这一份就够。** 规则、命令、代码地图都在这里。
> 更细的实测结论与背景说明在 **`.opencode/MEMORY.md`** —— 需要时再翻。

---

## 0. 这是什么

**GitDuo 2.0** —— 一个 iPhone 上的 GitHub 客户端（SwiftUI + Liquid Glass）。

- 纯 iPhone（**不做** iPad / 折叠屏）· iOS 27.0 · **零第三方依赖** · Swift 6 严格并发 · xcodegen 生成工程
- 五包 + 一个 App target（见 §2）
- **视觉正本 = Apple HIG / SwiftUI 官方控件。**「按原型」只指**功能**按原型，**不是视觉一模一样**。
- **方向是"自绘件分批退休、改用官方控件"** ⇒ **不要再为"对齐原型观感"新增自绘件**。
- ⚠️ **仓库里没有文档层**：规格 / 决策表 / 原型树 / 改造计划都不在工作区（只在 git 历史里）
  ⇒ 代码注释里的出处引用当"背景说明"读，见 §5 末。

**本仓库的活**：维护性改动（修 bug、加小功能、跟随系统升级）。
**动手前读本文 + 读你要改的那几个文件，就够。**

---

## 1. 命令（验证闭环）

| 命令 | 作用 |
|---|---|
| `make gen` | xcodegen 生成 `GitDuo.xcodeproj`（改 `project.yml` / **增删文件后必跑**） |
| `make test` | 五个包的单测（Swift Testing，秒级） |
| `make build` | 为 iOS 模拟器构建 App（不签名） |
| `make verify` | **以上全跑 —— 改完必跑** |
| `make device` | 真机：构建(带签名) → 安装 → 启动（手测用） |

**没有验证结果的改动等于没做。** 改完必须给出 `make verify` 的结果。

> ⚠️ **`make test` 一个字都不编译 App target（`GitDuo/**`）** —— 它只跑五个 SwiftPM 包。
> 改了 `GitDuo/**` 却只跑 `make test` 会拿到"全绿"，而 App 层可能**根本编不过**。⇒ **必须 `make verify`**。

> ⚠️ **宣布"零编译警告"之前先强制全量重编** —— **增量构建会吞掉警告**。
> 先 `find Packages GitDuo -name '*.swift' -print0 | xargs -0 touch`，再 `make verify`。

> ⚠️ **`GitDuoDesign` 同时为 macOS 构建** ⇒ iOS 独有修饰符（如 `textInputAutocapitalization`）必须 `#if os(iOS)` 包起来。
> `make test-GitDuoKit` **不会**编到它（只编自己那个包）⇒ 它全绿而 `make verify` 在这一行炸掉。

### 沙箱：报 `sandbox_apply: Operation not permitted` 时**不要改代码**

**只要出现 `sandbox_apply: Operation not permitted`，一律是运行环境问题**（不是源码写错）。
机理：受限环境里内核拒绝一切嵌套 `sandbox-exec`，而 SwiftPM 与 Xcode 都用它包子进程 ⇒
症状是包解析失败，或 `@Observable` / `#Preview` 报 *"produced malformed response"*（宏没跑起来）。
`Makefile` 已自愈（`sandbox-fix` 先探测，健康机器上等于什么都没做）⇒ `build` / `device` 自动带上。

> 另：**别用 `rm -rf` 做 clean** —— 本环境会拦截它，且 `&&` 短路会让后续命令**压根不执行**（看起来"跑了但没过"）。

---

## 2. 架构铁律（违反即返工）

```
表现层 GitDuo/Features/  →  领域层 GitDuoKit  →  数据层 GitHubAPI / GitDuoCore
```

**五包 + App target**（`Packages/` 与 `GitDuo/`）：

| 包 | 是什么 |
|---|---|
| `GitHubAPI` | 网络 + OAuth **客户端** + DTO + 缓存 |
| `GitDuoCore` | 本地基础设施（Keychain、图片处理…） |
| `GitDuoAuth` | 认证**编排**（要同时用上面两包 ⇒ 只能在其之上；落在包里而非 App 是为了能跑单测） |
| `GitDuoDesign` | 设计令牌 + 组件 + 玻璃封装 |
| `GitDuoKit` | **领域层** —— 只出"是什么"，不出"长什么样" |
| `GitDuo`（App target） | 组合根 + 页面 |

**依赖铁律**：`GitDuoDesign → GitDuoCore` · `GitDuoAuth → GitHubAPI + GitDuoCore` · `GitDuoKit → GitHubAPI + GitDuoCore` · **其余互不依赖**。

- ⚠️ `GitHubAPI` **绝不能** import `GitDuoAuth`（会成环）。
- ⚠️ **数据层不得引用领域层** ⇒ `GitHubAPI` 里只有 `RepositoryDTO`、没有 `Repository`。
- ⚠️ `GitDuoKit` **不得 import SwiftUI**。
- ⚠️ **接缝（seam）**：协议在 `GitDuoKit`、被扩展的类型在别的包，**扩展体可以空、但签名逐字一致**。
  空扩展体被整条删掉时**编译与其余测试都不会有反应** ⇒ **新增接缝要在
  `Packages/GitDuoKit/Tests/GitDuoKitTests/RepoEndpointsContractTests.swift` 同步加一行**（该文件按 `let _: any …` 逐条清点）。

**导航**：
- 四个 Tab **各持一条独立 `NavigationStack`**；路由一律经 `Router.path(for:)` 按 `selection` 取栈，**禁止写死某个 Tab 的栈**。
- 路由用**值类型枚举 `Route`** + `navigationDestination(for:)`；**禁止** `NavigationLink(destination:)` 闭包式写法。
- `RouteView` 的 switch **必须穷尽** —— 新增 case 忘记接线应当**编译失败**，这是有意的。

**装配**：`GitDuo/App/AppEnvironment.swift` 是**唯一依赖装配点**；View / ViewModel **不得自行构造客户端**。

---

## 3. 编码铁律

| # | 铁律 | 原因 / 出处 |
|---|---|---|
| 1 | **零第三方依赖**（含测试期尽量自建） | 决策 #12 |
| 2 | **Swift 6 严格并发**；App 层默认 MainActor，数据层 actor 隔离 | 决策 #9 |
| 3 | 颜色 / 字号 / 间距 / 圆角**一律引用 `Theme` 令牌**，禁写魔法值 | 为补深色预留 |
| 4 | `.glassEffect` **只允许出现在 `GitDuoDesign` 的组件封装内** | 玻璃只属导航层 |
| 5 | 玻璃**绝不用在内容层**（列表行、卡片、正文、图片） | 同上 |
| 6 | 不用 `UIScreen.main`；布局看 size class 与容器尺寸 | 纯 iPhone |
| 7 | **只读态显式传参**（`readOnly:`），不让下层页自行推断仓库归属 | 可写性唯一来源 = `Repository.permissions.push` |
| 8 | 凭据只进 Keychain；**绝不写入**日志 / 崩溃上报 / 剪贴板 / UserDefaults 明文 | |
| 9 | `client_secret` 由 `Secrets.xcconfig` 构建期注入、**不入库**；只许出现在「换令牌 / 刷新 / 撤销」三条请求里，不进日志与缓存 | |
| 10 | `code_verifier` 只存内存、**绝不随回调传输**；`state` 一次性 | scheme 被抢注时唯一的防线 |
| 11 | "这个能力能不能做"**先查文档结论**，不要凭直觉承诺 | 已核实：置顶无写 API · Revert 无端点 · 最近访问无 API · 通知 API 不支持 App 令牌 |
| 12 | 加任何网络调用前先看配额预算；**GraphQL 单查询 ≤5 点** | 深层嵌套可一次烧掉 100 点 |
| 13 | 长任务 / 循环里的失败**不要静默吞掉**（尤其 404 与"无权限"被 GitHub 混同） | |

---

## 4. 改动纪律

1. **先想清楚"这是不是已定过的事"** —— ⚠️ 规格与偏差表的正本**不在工作区**（只在 git 历史里）。
   拿不准时**别自己拍板**：要么去 git 历史里捞（见 §5 末），要么**问用户**。
   **不要默默改掉一个定过的事**；确属新决定，就在答复里**写明"这是新口径"**。
2. **文案是契约** —— 改文案要 grep 全仓（同一句话常散落 4–6 处）；行为类文案改完还要**真跑一遍**确认兑现得出。
3. **改完必须验证** —— `make verify`；无法验证的改动要在答复里明确说"未验证 + 原因"。
4. **不要替用户拍板** —— 遇到未定义的点，**给选项与推荐**，不要自定义一个值然后当成事实。
5. **提交** —— 提交信息写"做了什么 + 为什么"，不写 "update"。

---

## 5. 代码地图（要改什么 → 去哪找）

**App 层** `GitDuo/`
- `App/` —— `GitDuoApp`（入口）· `RootView`（登录门禁）· `MainTabView` · `AppEnvironment`（**唯一装配点**）· `AuthState` · `Stores/`
- `Navigation/` —— `Route`（枚举）· `RouteView`（穷尽 switch）· `Router`
- `Features/<域>/` —— 域名 = `Auth` `Home` `Explore` `Repos` `Repo` `Search` `Profile`；每个域下 `Views/` · `Components/` · `ViewModels/`
- `Resources/`

**领域层** `Packages/GitDuoKit/Sources/GitDuoKit/` —— `Home` `Explore` `Repos` `Repo` `Branches` `Files` `Search` `Profile` `Rendering`（Markdown / diff / 高亮）· `Mapping` `Models` `Paging` `Loading`

**数据层** `Packages/GitHubAPI/Sources/GitHubAPI/` —— `REST/`（端点 + DTO）· `GraphQL/` · `HTTP/`（传输 / 缓存 / 错误）· `Auth/` · `Cache/` · `Pagination/`

**设计系统** `Packages/GitDuoDesign/Sources/GitDuoDesign/` —— `Tokens/`（`Theme`）· `Components/`

**测试** `Packages/<包>/Tests/<包>Tests/` —— Swift Testing（`@Test` / `#expect`）。
⚠️ 网络桩件**按命名空间隔离**（每套件自持 `Harness`）⇒ 网络测试可自由并行，**不要加 `.serialized`**。

---

> ⚠️ **代码注释里的出处编号 `TECH_SPEC §x.y` / `决策 #NN` / `偏差第 N 条` / `NATIVE-MIGRATION P#`，
> 以及 `redesign/prototype/**` 这类路径 —— 正本都不在工作区** ⇒ 当"背景说明"读、**别去找那个文件**
> （找不到是正常的）。要追溯原文只有 git 历史一条路：`git show <删除前那次提交>:archive/TECH_SPEC.md`。
